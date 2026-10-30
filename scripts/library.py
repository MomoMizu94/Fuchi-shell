#!/usr/bin/env python3
"""Local image-book library. JSON lines on stdin/stdout; downloads use a detached worker.

Archive handling and metadata conventions adapted from MangaReaderQS.
Copyright (c) 2026 Teemu, MIT. See licenses/MangaReaderQS.txt.
"""
import argparse
from contextlib import ExitStack, contextmanager
import fcntl
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import urlsplit
import warnings
import xml.etree.ElementTree as ET
import zipfile

IMAGES = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif", ".bmp"}
ARCHIVES = {".cbz", ".cbr"}
FIELDS = ("tags", "languages", "characters", "parodies", "artists", "censorship")
IMPORT_RECORD = ".quickshell-library.json"
MAX_ENTRY_BYTES = 200 * 1024 ** 2
MAX_CHAPTER_BYTES = 2 * 1024 ** 3
MAX_LISTING_BYTES = 8 * 1024 ** 2
DOWNLOAD_STOP_TIMEOUT = 5
DOWNLOAD_EVENT = b"\x1eQS_LIBRARY_IMAGE\n"
MAX_LOG_BYTES = 2 * 1024 ** 2
CACHE_DAYS = 90
HISTORY_LIMIT = 200
COVER_CACHE_BYTES = 128 * 1024 ** 2
METADATA_CACHE_BYTES = 16 * 1024 ** 2


def natural(value):
    return [int(part) if part.isdigit() else part.casefold()
            for part in re.split(r"(\d+)", str(value))]


def digest(value):
    return hashlib.sha256(str(value).encode()).hexdigest()[:20]


def load_json(path, default):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default
    except (ValueError, UnicodeError, RecursionError) as error:
        raise ValueError(f"Could not read {Path(path).name}. Restore it from a backup: {error}") from error


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix="." + path.name, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(value, stream, ensure_ascii=False, allow_nan=False)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def touch_cache(path):
    try:
        if time.time() - path.stat().st_mtime > 86400:
            os.utime(path)
    except OSError:
        pass  # Access-time bookkeeping must not prevent reading a valid cache.


def document(path):
    value = load_json(path, {})
    if not isinstance(value, dict):
        raise ValueError(f"Expected an object in {Path(path).name}")
    return value


def check_data(condition, path, field):
    if not condition:
        raise ValueError(f"Invalid {Path(path).name}: {field}. Repair this entry or restore the file from a backup.")


def reading_state(path):
    value = document(path)
    progress, settings = value.get("progress", {}), value.get("settings", {})
    check_data(isinstance(progress, dict), path, "progress must be an object")
    check_data(isinstance(settings, dict), path, "settings must be an object")
    for file, mark in progress.items():
        field = f"progress[{file!r}]"
        check_data(isinstance(mark, dict), path, field + " must be an object")
        page, done, read = mark.get("page", 0), mark.get("done", False), mark.get("read", 0)
        check_data(type(page) is int and page >= 0, path, field + ".page must be a nonnegative integer")
        check_data(type(done) is bool, path, field + ".done must be a boolean")
        check_data(type(read) in (int, float) and read >= 0 and
                   (type(read) is int or math.isfinite(read)), path,
                   field + ".read must be a finite nonnegative timestamp")
    for key, choices in (("rtl", (True, False)), ("fit", ("page", "width")), ("sort", ("recent", "name"))):
        if key in settings:
            check_data((type(settings[key]) is bool if key == "rtl" else isinstance(settings[key], str))
                       and settings[key] in choices, path, f"settings.{key} has an unsupported value")
    if "autoTurnSeconds" in settings:
        seconds = settings["autoTurnSeconds"]
        check_data(type(seconds) is int and 1 <= seconds <= 3600, path,
                   "settings.autoTurnSeconds must be an integer between 1 and 3600")
    return value


def download_url(value):
    message = "Paste an HTTP or HTTPS URL without embedded credentials"
    if not isinstance(value, str):
        raise ValueError(message)
    parsed = urlsplit(value.strip())
    if parsed.scheme not in ("https", "http") or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError(message)
    return value.strip()


def download_state(path):
    value = document(path)
    jobs = value.get("jobs", [])
    check_data(isinstance(jobs, list), path, "jobs must be a list")
    identities = set()
    for index, job in enumerate(jobs):
        field = f"jobs[{index}]"
        check_data(isinstance(job, dict), path, field + " must be an object")
        identity = job.get("id")
        check_data(isinstance(identity, str) and re.fullmatch(r"[A-Za-z0-9_-]+", identity)
                   and len(identity) <= 100, path, field + ".id must be a safe, nonempty identifier")
        check_data(identity not in identities, path, field + ".id is duplicated")
        identities.add(identity)
        check_data(job.get("status") in ("pending", "running", "completed", "failed", "cancelled"),
                   path, field + ".status has an unsupported value")
        root = job.get("root")
        check_data(isinstance(root, str) and "\x00" not in root and Path(root).is_absolute(),
                   path, field + ".root must be an absolute folder path")
        try:
            download_url(job.get("url"))
        except ValueError as error:
            raise ValueError(f"Invalid {Path(path).name}: {field}.url. {error}") from error
        outputs = job.get("outputs", [])
        check_data(isinstance(outputs, list) and all(isinstance(item, str) and "\x00" not in item
                   and Path(item).is_absolute() for item in outputs),
                   path, field + ".outputs must be a list of absolute file paths")
        for key in ("files", "device"):
            if key in job:
                check_data(type(job[key]) is int and job[key] >= 0,
                           path, field + f".{key} must be a nonnegative integer")
        check_data(type(job.get("cancelled", False)) is bool, path, field + ".cancelled must be a boolean")
        check_data(type(job.get("discarded", False)) is bool, path, field + ".discarded must be a boolean")
        if "finished" in job:
            finished = job["finished"]
            check_data(type(finished) in (int, float) and finished >= 0
                       and (type(finished) is int or math.isfinite(finished)),
                       path, field + ".finished must be a finite nonnegative timestamp")
        check_data(isinstance(job.get("error", ""), str), path, field + ".error must be text")
    return value


@contextmanager
def changing(path, write=True, reader=document):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        value = reader(path)
        yield value
        if write:
            atomic_json(path, value)


def archive_output(command, max_bytes, timeout, limit_message):
    """Drain both pipes with bounded buffers and one deadline, then reap the tool."""
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
        output, errors = io.BytesIO(), io.BytesIO()
        deadline = time.monotonic() + timeout
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ, (output, max_bytes, limit_message))
                selector.register(process.stderr, selectors.EVENT_READ,
                    (errors, 64 * 1024, "Archive tool diagnostics exceed the 64 KiB limit"))
                while selector.get_map():
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise subprocess.TimeoutExpired(command, timeout)
                    for key, _ in selector.select(remaining):
                        buffer, limit, message = key.data
                        available = limit - buffer.tell()
                        chunk = os.read(key.fd, min(64 * 1024, available + 1))
                        if not chunk:
                            selector.unregister(key.fileobj)
                        elif len(chunk) > available:
                            raise ValueError(message)
                        else:
                            buffer.write(chunk)
            returncode = process.wait(timeout=max(0, deadline - time.monotonic()))
            if returncode:
                raise ValueError(errors.getvalue().decode(errors="replace").strip()
                                 or f"Archive tool exited with code {returncode}")
            return output.getvalue()
        finally:
            if process.poll() is None:
                process.kill()  # Popen's context manager also waits and closes both pipes.


def members(path):
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            return [name for name in archive.namelist() if not name.endswith("/")]
    listing = archive_output(["bsdtar", "-tf", str(path)], MAX_LISTING_BYTES, 30,
                             "Archive listing exceeds the 8 MiB limit")
    return listing.decode(errors="replace").splitlines()


def page_names(names):
    return sorted((name for name in names if Path(name).suffix.lower() in IMAGES
                   and "__MACOSX" not in Path(name).parts), key=natural)


def member_bytes(path, name):
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            if archive.getinfo(name).file_size > MAX_ENTRY_BYTES:
                raise ValueError("An archive entry exceeds the 200 MiB page limit")
            return archive.read(name)
    pattern = re.sub(r"([\[\]*?\\])", r"\\\1", name)
    return archive_output(["bsdtar", "-xOf", str(path), "--", pattern], MAX_ENTRY_BYTES, 60,
                          "An archive entry exceeds the 200 MiB page limit")


@contextmanager
def bounded_image(source):
    from PIL import Image
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(source) as image:
                yield image
    except (Image.DecompressionBombWarning, Image.DecompressionBombError) as error:
        raise ValueError("Image exceeds the safe pixel limit. Use a smaller image.") from error


def values(value):
    pending, result = [value], set()
    while pending:
        entry = pending.pop()
        if isinstance(entry, dict):
            pending.append(entry.get("name") or entry.get("tag") or list(entry.values()))
        elif isinstance(entry, list):
            pending.extend(entry)
        elif entry is not None:
            result.update(item.strip().casefold() for item in re.split(r",\s*", str(entry)) if item.strip())
    return sorted(result)


def metadata(data):
    result = {field: [] for field in FIELDS}
    aliases = {"tags": ("tags",), "languages": ("language", "languages", "lang"),
               "artists": ("artist", "artists", "writer", "author"),
               "characters": ("characters", "character"), "parodies": ("parody", "parodies")}
    for field, keys in aliases.items():
        result[field] = sorted({item for key in keys for item in values(data.get(key))})
    for tag in result["tags"][:]:
        prefix, _, value = tag.partition(":")
        field = {"language": "languages", "character": "characters", "parody": "parodies",
                 "artist": "artists"}.get(prefix)
        if field and value:
            result[field] = sorted(set(result[field] + [value]))
    result["tags"] = sorted({tag.split(":", 1)[-1] if tag.startswith(
        ("female:", "male:", "tag:", "misc:", "other:", "mixed:")) else tag for tag in result["tags"]})
    result["languages"] = [v for v in result["languages"] if v not in ("translated", "rewrite")]
    if any(tag in ("uncensored", "decensored") for tag in result["tags"]):
        result["censorship"] = ["uncensored"]
    elif "censored" in result["tags"]:
        result["censorship"] = ["censored"]
    result["title"] = str(data.get("title") or data.get("manga") or "")
    return result


def archive_metadata(path, names):
    xml = next((n for n in names if Path(n).name.casefold() == "comicinfo.xml"), None)
    info = next((n for n in names if Path(n).name.casefold() == "info.json"), None)
    try:
        data = json.loads(member_bytes(path, info)) if info else {}
    except (ValueError, UnicodeError, RecursionError) as error:
        raise ValueError(f"Could not read info.json: {error}") from error
    check_data(isinstance(data, dict), path, "info.json must contain an object")
    if xml:
        tree = ET.fromstring(member_bytes(path, xml))
        for source, target in (("Title", "title"), ("Writer", "writer"), ("LanguageISO", "language"),
                               ("Tags", "tags"), ("Characters", "characters")):
            value = tree.findtext(source)
            if value:
                data[target] = value
        genre = tree.findtext("Genre")
        if genre:
            data["tags"] = values(data.get("tags")) + values(genre)
    return metadata(data)


def cached_pages(destination, count):
    listing = destination / "pages.json"
    if destination.is_symlink() or listing.is_symlink():
        return None
    try:
        pages = load_json(listing, None)
        if not isinstance(pages, list) or len(pages) != count:
            return None
        total = 0
        for index, value in enumerate(pages):
            if not isinstance(value, str) or "\x00" in value:
                return None
            page = Path(value)
            if page.parent != destination or page.suffix not in IMAGES \
                    or page.name != f"{index:05d}{page.suffix}":
                return None
            entry = page.lstat()
            if not stat.S_ISREG(entry.st_mode) or not 0 < entry.st_size <= MAX_ENTRY_BYTES:
                return None
            total += entry.st_size
            if total > MAX_CHAPTER_BYTES:
                return None
        return pages
    except (ValueError, FileNotFoundError, NotADirectoryError):
        return None  # Generated data can be reconstructed from the archive.


@contextmanager
def worker_lock(library, inherited_fd=None):
    library.state.mkdir(parents=True, exist_ok=True, mode=0o700)
    stream = os.fdopen(inherited_fd, "a") if inherited_fd is not None else (
        library.state / "worker.lock").open("a")
    with stream as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            yield None
        else:
            yield lock


def recover_jobs(queue):
    """Caller holds both queue and worker locks; no worker owns these jobs."""
    changed = False
    for job in queue.get("jobs", []):
        if job["status"] in ("pending", "running"):
            job.update(status="failed", error="Download worker stopped. Retry to resume.")
            changed = True
    return changed


class Library:
    def __init__(self, root, state, cache):
        self.root = Path(root).expanduser().absolute()
        self.state = Path(state)
        self.cache = Path(cache)
        self.progress_path = self.state / "reading.json"
        self.queue_path = self.state / "downloads.json"
        self.log_path = self.state / "download.log"

    def contained(self, value, archive=False):
        path = Path(value).absolute()
        resolved = path.resolve()
        if resolved == self.root.resolve() or self.root.resolve() not in resolved.parents:
            raise ValueError("Choose an item inside the library folder")
        if any(part.startswith(".") for part in path.relative_to(self.root).parts):
            raise ValueError("Hidden working files are not library entries")
        if path.is_symlink() or (archive and path.suffix.lower() not in ARCHIVES):
            raise ValueError("Choose a CBZ or CBR file inside the library")
        return path

    def details(self, path, *, refresh=False):
        stat = path.stat()
        identity = digest(f"{path}|{stat.st_size}|{stat.st_mtime_ns}")
        note = self.cache / "metadata" / (identity + ".json")
        if not refresh and note.exists():
            try:
                result = document(note)
                check_data(result.get("key") == identity, note, "key does not match this archive")
                check_data(type(result.get("pages")) is int and result["pages"] > 0,
                           note, "pages must be a positive integer")
                meta = result.get("meta")
                check_data(isinstance(meta, dict), note, "meta must be an object")
                check_data(isinstance(meta.get("title"), str), note, "meta.title must be text")
                for field in FIELDS:
                    check_data(isinstance(meta.get(field), list) and all(isinstance(item, str)
                               for item in meta[field]), note, f"meta.{field} must be a list of strings")
                touch_cache(note)
                return result
            except ValueError:
                pass  # Rebuild this generated cache; archive errors still propagate below.
        names = members(path)
        pages = page_names(names)
        if not pages:
            raise ValueError("Archive has no supported page images")
        result = dict(key=identity, pages=len(pages), meta=archive_metadata(path, names))
        atomic_json(note, result)
        return result

    def cover(self, path, key, art=None, *, generate=True):
        identity = key if art is None else digest(f"{art}|{art.stat().st_mtime_ns}")
        target = self.cache / "covers" / (identity + ".jpg")
        if not target.exists():
            if not generate:
                return ""
            source = art if art else io.BytesIO(member_bytes(path, page_names(members(path))[0]))
            with bounded_image(source) as image:
                image.thumbnail((360, 520))
                target.parent.mkdir(parents=True, exist_ok=True)
                image.convert("RGB").save(target.with_suffix(".tmp"), "JPEG", quality=85)
                target.with_suffix(".tmp").replace(target)
        touch_cache(target)
        return str(target)

    def scan(self, publish=None):
        if not self.root.is_dir():
            raise ValueError("Library folder is unavailable. Choose an existing folder in Settings.")
        if not os.access(self.root, os.R_OK | os.X_OK):
            raise ValueError("Library folder is not readable. Check its permissions or choose another folder.")
        reading_state(self.progress_path)
        groups = {}
        covers = {}
        artwork = {}
        errors = []
        for folder, directories, filenames in os.walk(self.root, followlinks=False,
                onerror=lambda error: errors.append(str(error))):
            directories[:] = sorted((d for d in directories if not d.startswith(".")
                                      and not (Path(folder) / d).is_symlink()), key=natural)
            for filename in sorted(filenames, key=natural):
                path = Path(folder) / filename
                if filename.startswith(".") or path.is_symlink() or path.suffix.lower() not in ARCHIVES:
                    continue
                relative = path.relative_to(self.root)
                group = str(self.root / relative.parts[0]) if len(relative.parts) > 1 else str(path)
                try:
                    info = self.details(path)
                    chapter = dict(file=str(path), name=path.stem, pages=info["pages"],
                                   page=0, done=False, read=0)
                    book = groups.setdefault(group, dict(id=group, name=Path(group).stem if
                        len(relative.parts) == 1 else relative.parts[0], chapters=[], cover="",
                        meta={field: [] for field in FIELDS}))
                    if len(relative.parts) == 1 and info["meta"].get("title"):
                        book["name"] = info["meta"]["title"]
                    book["chapters"].append(chapter)
                    for field in FIELDS:
                        book["meta"][field] = sorted(set(book["meta"][field] + info["meta"][field]))
                    if not book["cover"]:
                        if group not in artwork:
                            directory = Path(group) if Path(group).is_dir() else None
                            artwork[group] = self.local_cover(directory) if directory else None
                        art = artwork[group]
                        book["cover"] = self.cover(path, info["key"], art, generate=False)
                        covers.setdefault(group, []).append((path, info["key"], art))
                except (OSError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError,
                        subprocess.SubprocessError) as error:
                    errors.append(f"{filename}: {error}")
        for book in groups.values():
            book["chapters"].sort(key=lambda c: natural(Path(c["file"]).relative_to(self.root)))

        def result():
            saved = reading_state(self.progress_path)
            for book in groups.values():
                for chapter in book["chapters"]:
                    mark = saved.get("progress", {}).get(chapter["file"], {})
                    chapter.update(page=min(mark.get("page", 0), chapter["pages"] - 1),
                                   done=mark.get("done", False), read=mark.get("read", 0))
                book["done"] = sum(c["done"] for c in book["chapters"])
                book["read"] = max(c["read"] for c in book["chapters"])
                last = max(range(len(book["chapters"])), key=lambda i: book["chapters"][i]["read"])
                book["resume"] = min(last + int(book["chapters"][last]["done"]), len(book["chapters"]) - 1)
            return dict(books=list(groups.values()), warnings=errors, settings=saved.get("settings", {}),
                        writable=os.access(self.root, os.W_OK))

        if publish:
            publish(result())
        last_publish = time.monotonic()
        changed_covers = {}
        for group, candidates in covers.items():
            book = groups[group]
            if book["cover"]:
                continue
            for path, key, art in candidates:
                try:
                    book["cover"] = self.cover(path, key, art)
                    changed_covers[group] = book["cover"]
                    break
                except (OSError, ValueError) as error:
                    errors.append(f"{path.name}: could not create cover, {error}")
                    if art is not None:
                        break  # Every chapter uses this same local artwork.
            if publish and time.monotonic() - last_publish >= 0.25:
                publish(dict(covers=changed_covers, warnings=errors))
                changed_covers = {}
                last_publish = time.monotonic()
        return result()

    @staticmethod
    def local_cover(directory):
        candidates = sorted((p for p in directory.iterdir() if p.stem.casefold() == "cover"
                             and p.suffix.lower() in IMAGES and not p.is_symlink()), key=natural)
        covers = directory / "covers"
        if not candidates and covers.is_dir() and not covers.is_symlink():
            candidates = sorted((p for p in covers.iterdir() if p.suffix.lower() in IMAGES
                                 and not p.is_symlink()), key=natural)
        return candidates[0] if candidates else None

    def open_archive(self, file):
        path = self.contained(file, archive=True)
        info = self.details(path)
        destination = self.cache / "pages" / info["key"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        # Cache repair and eviction share a lock across helper processes.
        with (self.cache / "pages.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            pages = cached_pages(destination, info["pages"])
            if pages is None:
                with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
                    temporary = Path(temporary)
                    extracted = temporary / "new"
                    extracted.mkdir()
                    pages = []
                    total = 0
                    # Open the ZIP once. Reopening it for every page repeatedly
                    # parses the central directory and is costly for large books.
                    if not zipfile.is_zipfile(path):
                        output = archive_output([sys.executable, "-B", str(Path(__file__).with_name("library_archive.py")),
                            str(path), str(extracted), str(MAX_ENTRY_BYTES), str(MAX_CHAPTER_BYTES),
                            str(MAX_LISTING_BYTES), str(os.getpid())], MAX_LISTING_BYTES, 60,
                            "Archive page listing exceeds its limit")
                        filenames = json.loads(output)
                        pages = [str(destination / name) for name in filenames]
                        if not pages:
                            raise ValueError("Archive has no supported page images")
                    else:
                        with zipfile.ZipFile(path) as archive:
                            names = page_names(archive.namelist())
                            if not names:
                                raise ValueError("Archive has no supported page images")
                            for index, name in enumerate(names):
                                size = archive.getinfo(name).file_size
                                if size > MAX_ENTRY_BYTES:
                                    raise ValueError("An archive entry exceeds the 200 MiB page limit")
                                source = archive.open(name)
                                total += size
                                with source:
                                    if not size:
                                        raise ValueError("An archive page image is empty")
                                    if total > MAX_CHAPTER_BYTES:
                                        raise ValueError("Extracted chapter exceeds the 2 GiB cache limit")
                                    filename = f"{index:05d}{Path(name).suffix.lower()}"
                                    with (extracted / filename).open("wb") as target:
                                        shutil.copyfileobj(source, target)
                                pages.append(str(destination / filename))
                    if len(pages) != info["pages"]:
                        info = self.details(path, refresh=True)
                        if info["key"] != destination.name:
                            raise ValueError("Archive changed while opening. Try again.")
                    atomic_json(extracted / "pages.json", pages)
                    previous = temporary / "old"
                    if os.path.lexists(destination):
                        destination.rename(previous)
                    try:
                        extracted.rename(destination)
                    except OSError:
                        if os.path.lexists(previous):
                            previous.rename(destination)
                        raise
            os.utime(destination)
            folders = sorted((p for p in destination.parent.iterdir() if p.is_dir() and not p.is_symlink()),
                             key=lambda p: p.stat().st_mtime, reverse=True)
            for folder in folders[6:]:
                if folder != destination:
                    shutil.rmtree(folder)
        mark = reading_state(self.progress_path).get("progress", {}).get(str(path), {})
        return dict(file=str(path), pages=pages,
                    page=0 if mark.get("done") else min(mark.get("page", 0), len(pages) - 1))

    def save_progress(self, file, page, done=None):
        path = self.contained(file, archive=True)
        count = self.details(path)["pages"]
        if type(page) is not int or not 0 <= page < count:
            raise ValueError("Page is outside this chapter")
        with changing(self.progress_path, reader=reading_state) as state:
            marks = state.setdefault("progress", {})
            old = marks.get(str(path), {})
            marks[str(path)] = dict(page=page, read=time.time(),
                                    done=old.get("done", False) if done is None else bool(done))
        return {}

    def mark(self, files, done):
        paths = [self.contained(file, archive=True) for file in files]
        with changing(self.progress_path, reader=reading_state) as state:
            marks = state.setdefault("progress", {})
            for path in paths:
                old = marks.get(str(path), {})
                marks[str(path)] = dict(page=0, done=bool(done), read=old.get("read", 0))
        return {}

    def trash(self, file):
        path = self.contained(file)
        if not path.exists():
            raise ValueError("This library item no longer exists")
        reading_state(self.progress_path)
        for job in download_state(self.queue_path).get("jobs", []):
            if job["status"] in ("pending", "running") and any(
                    item == str(path) or path in Path(item).parents for item in job.get("outputs", [])):
                raise ValueError("Cancel this book's active download before moving it to Trash.")
        result = subprocess.run(["gio", "trash", "--", str(path)],
                                capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise ValueError(result.stderr.strip() or "Could not move the item to Trash")
        with changing(self.progress_path, reader=reading_state) as state:
            state["progress"] = {key: value for key, value in state.get("progress", {}).items()
                                 if key != str(path) and path not in Path(key).parents}
        # Own download records are per job. Forget affected jobs only, never the
        # user's global gallery-dl archive. A later pasted URL can restore them.
        with changing(self.queue_path, reader=download_state) as queue:
            for job in queue.get("jobs", []):
                if any(item == str(path) or path in Path(item).parents for item in job.get("outputs", [])):
                    (self.state / "archives" / (job["id"] + ".sqlite3")).unlink(missing_ok=True)
        return {}

    def status(self):
        queue = download_state(self.queue_path)
        if any(job["status"] in ("pending", "running") for job in queue.get("jobs", [])):
            with changing(self.queue_path, write=False, reader=download_state) as queue:
                with worker_lock(self) as lock:
                    if lock is not None and recover_jobs(queue):
                        atomic_json(self.queue_path, queue)
        try:
            with self.log_path.open("rb") as stream:
                stream.seek(max(0, self.log_path.stat().st_size - 32000))
                log = "\n".join(stream.read().decode(errors="replace").splitlines()[-150:])
        except FileNotFoundError:
            log = ""
        return dict(jobs=queue.get("jobs", []), log=log, galleryAvailable=bool(shutil.which("gallery-dl")))

    def add(self, url):
        url = download_url(url)
        if not self.root.is_dir() or not os.access(self.root, os.W_OK):
            raise ValueError("The library folder is unavailable or read-only. Check the drive or Settings.")
        if not shutil.which("gallery-dl"):
            raise ValueError("Install gallery-dl to download books")
        identity = digest(f"{self.root}|{url.strip()}")
        # Hold an idle worker's lock before enqueueing and pass it to its child.
        # Status checks can then distinguish startup from an abandoned queue.
        with ExitStack() as resources:
            with changing(self.queue_path, write=False, reader=download_state) as queue:
                # Check ownership while holding the queue lock: a worker which
                # finishes just before this append must be replaced here.
                lock = resources.enter_context(worker_lock(self))
                if lock is not None:
                    recover_jobs(queue)
                jobs = queue.setdefault("jobs", [])
                existing = next((job for job in jobs if job["id"] == identity), None)
                if existing and existing["status"] in ("pending", "running"):
                    raise ValueError("That URL is already in the download queue")
                if existing:
                    if any(not Path(path).is_file() for path in existing.get("outputs", [])):
                        (self.state / "archives" / (identity + ".sqlite3")).unlink(missing_ok=True)
                    existing.update(status="pending", error="", cancelled=False, discarded=False,
                                    device=self.root.stat().st_dev)
                else:
                    jobs.append(dict(id=identity, root=str(self.root), url=url.strip(), status="pending",
                                     files=0, error="", outputs=[], device=self.root.stat().st_dev))
                atomic_json(self.queue_path, queue)
                if lock is not None:
                    self.start_worker(lock.fileno())
            return self.status()

    def start_worker(self, lock_fd):
        self.state.mkdir(parents=True, exist_ok=True, mode=0o700)
        worker_log = self.state / "worker.log"
        if worker_log.exists() and worker_log.stat().st_size >= MAX_LOG_BYTES:
            worker_log.replace(worker_log.with_suffix(".previous.log"))
        with worker_log.open("a") as log:
            process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--root", str(self.root),
                                        "--state", str(self.state), "--cache", str(self.cache),
                                        "--worker-lock-fd", str(lock_fd), "worker"],
                                       stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True,
                                       pass_fds=(lock_fd,))
        # Reap children while this helper lives; the independent worker survives
        # if the window closes and the helper exits.
        threading.Thread(target=process.wait, daemon=True).start()

    def cancel(self, identity):
        with changing(self.queue_path, reader=download_state) as queue:
            for job in queue.get("jobs", []):
                if job["id"] == identity and job["status"] in ("pending", "running"):
                    job["cancelled"] = True
                    if job["status"] == "pending":
                        job["status"] = "cancelled"
        return self.status()

    def discard(self, identity):
        with changing(self.queue_path, reader=download_state) as queue:
            job = next((item for item in queue.get("jobs", []) if item["id"] == identity), None)
            if job is None or job["status"] not in ("failed", "cancelled"):
                raise ValueError("Cancel the download before discarding its working files")
            root = Path(job["root"])
            if not root.is_dir() or root.stat().st_dev != job.get("device", root.stat().st_dev):
                raise ValueError("Library drive is unavailable or changed. Reconnect it before discarding files.")
            stage = root / ".library-downloads" / identity
            check_download_path(root, stage)
            if stage.exists():
                shutil.rmtree(stage)
            (self.state / "archives" / (identity + ".sqlite3")).unlink(missing_ok=True)
            (self.state / (identity + ".config.json")).unlink(missing_ok=True)
            job.update(status="cancelled", files=0, discarded=True, finished=time.time(),
                       error="Working files discarded. Retry to download again.")
        return self.status()

    def prune_history(self):
        cutoff = time.time() - CACHE_DAYS * 86400
        with changing(self.queue_path, write=False, reader=download_state) as queue:
            migrated = False
            for job in queue.get("jobs", []):
                if job["status"] == "completed" and "finished" not in job:
                    job["finished"] = time.time()
                    migrated = True
            eligible = sorted((job for job in reversed(queue.get("jobs", []))
                if (job["status"] == "completed" or (job["status"] == "cancelled" and job.get("discarded") is True))
                and type(job.get("finished")) in (int, float)),
                key=lambda job: job["finished"], reverse=True)
            expired = {job["id"] for index, job in enumerate(eligible)
                       if index >= HISTORY_LIMIT or job["finished"] < cutoff}
            if not expired:
                if migrated:
                    atomic_json(self.queue_path, queue)
                return
            for identity in expired:
                (self.state / "archives" / (identity + ".sqlite3")).unlink(missing_ok=True)
                (self.state / (identity + ".config.json")).unlink(missing_ok=True)
            queue["jobs"] = [job for job in queue.get("jobs", []) if job["id"] not in expired]
            atomic_json(self.queue_path, queue)

    def maintain_cache(self, protected=()):
        self.cache.mkdir(parents=True, exist_ok=True)
        with (self.cache / "maintenance.lock").open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return
            marker = self.cache / "maintenance.json"
            if marker.exists() and time.time() - marker.stat().st_mtime < 86400:
                return
            cutoff = time.time() - CACHE_DAYS * 86400
            for folder, suffix, budget in (("covers", ".jpg", COVER_CACHE_BYTES),
                                            ("metadata", ".json", METADATA_CACHE_BYTES)):
                entries = sorted((path for path in (self.cache / folder).glob("*" + suffix)
                                  if str(path) not in protected and path.is_file() and not path.is_symlink()),
                                 key=lambda path: path.stat().st_mtime, reverse=True)
                used = 0
                for path in entries:
                    info = path.stat()
                    used += info.st_size
                    if used > budget or info.st_mtime < cutoff:
                        path.unlink()
            for folder, pattern in (("covers", "*.tmp"), ("metadata", ".*.json*")):
                for path in (self.cache / folder).glob(pattern):
                    if path.is_file() and not path.is_symlink() and time.time() - path.stat().st_mtime > 86400:
                        path.unlink()
            atomic_json(marker, {})

    def job(self, identity):
        job = next((item for item in download_state(self.queue_path).get("jobs", [])
                    if item["id"] == identity), None)
        if job is None:
            raise ValueError("Download job disappeared from downloads.json")
        return job

    def dispatch(self, command):
        op = command["op"]
        if op == "scan":
            return self.scan()
        if op == "open":
            return self.open_archive(command["file"])
        if op == "progress":
            return self.save_progress(command["file"], command["page"], command.get("done"))
        if op == "mark":
            return self.mark(command["files"], command["done"])
        if op == "trash":
            return self.trash(command["file"])
        if op == "setting":
            key, value = command["key"], command["value"]
            if (key == "rtl" and type(value) is bool) or (key == "fit" and value in ("page", "width")) \
                    or (key == "sort" and value in ("recent", "name")) \
                    or (key == "autoTurnSeconds" and type(value) is int and 1 <= value <= 3600):
                with changing(self.progress_path, reader=reading_state) as state:
                    state.setdefault("settings", {})[key] = value
                return {}
            raise ValueError("Unknown reader preference")
        if op == "status":
            return self.status()
        if op == "add":
            return self.add(command["url"])
        if op == "cancel":
            return self.cancel(command["job"])
        if op == "discard":
            return self.discard(command["job"])
        raise ValueError("Unknown library command")


def download_config(stage, archive):
    """Top-level options override destination/postprocessors, preserving private auth."""
    return {
        "base-directory": str(stage),
        "archive": str(archive),
        "directory": {
            "manga and chapter is not None": ["{category}", "{manga}",
                "c{chapter:>04}{chapter_minor:?//}{title:? //}"],
        },
        "image-filter": "extension in ('jpg', 'jpeg', 'png', 'webp', 'gif', 'avif', 'bmp')",
        "postprocessors": [{"name": "metadata", "mode": "json"},
                           {"name": "metadata", "mode": "print", "event": "after",
                            "format": DOWNLOAD_EVENT.decode().rstrip("\n")}],
        "sleep-request": [0.5, 1.5],
        "path-restrict": "unix",
    }


def safe_name(value):
    name = re.sub(r"[/\\\x00-\x1f]", "_", str(value)).strip(" .")
    # Leave room for the identity suffix and extension without splitting UTF-8 characters.
    return (name or "Untitled").encode("utf-8")[:150].decode("utf-8", errors="ignore")


def identity_key(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def metadata_id(data, fields, fallback):
    for field in fields:
        value = data.get(field)
        if value is not None and value != "":
            return [field, value]
    return fallback


def import_identity(data, relative, source):
    """Titles alone cannot establish ownership across different source URLs."""
    category = str(data.get("category") or (relative.parts[0] if relative.parts else "images"))
    identity = dict(source=digest(source), category=category)
    if data.get("manga") and data.get("chapter") is not None:
        identity.update(kind="series",
            book=metadata_id(data, ("manga_id", "series_id"), ["manga", data["manga"]]),
            chapter=metadata_id(data, ("chapter_id",),
                ["chapter", data["chapter"], data.get("chapter_minor"), data.get("volume")]),
            variant={field: data[field] for field in ("group", "groups", "language", "lang") if field in data})
    else:
        identity.update(kind="gallery",
            book=metadata_id(data, ("gallery_id", "album_id", "post_id", "id"),
                             ["directory", relative.as_posix()]))
    return identity


def book_key(identity):
    return identity_key({field: identity[field] for field in ("source", "category", "kind", "book")})


def read_import_record(path):
    try:
        with zipfile.ZipFile(path) as archive:
            record = json.loads(archive.read(IMPORT_RECORD))
            images = page_names(archive.namelist())
    except (KeyError, ValueError, RecursionError, zipfile.BadZipFile) as error:
        raise ValueError(f"Cannot safely merge {Path(path).name}: no valid Library import identity. "
                         "Move the old download aside before retrying a fresh download.") from error
    if not isinstance(record, dict) or record.get("version") != 1 \
            or not isinstance(record.get("identity"), dict) or not isinstance(record.get("pages"), dict):
        raise ValueError(f"Cannot safely merge {Path(path).name}: invalid Library import identity.")
    identity, pages = record["identity"], record["pages"]
    required = ("source", "category", "kind", "book")
    if any(field not in identity for field in required) or identity["kind"] not in ("series", "gallery") \
            or (identity["kind"] == "series" and ("chapter" not in identity or "variant" not in identity)) \
            or set(images) != set(pages) or len(images) != len(pages) \
            or any(not isinstance(value, str) for value in pages.values()) \
            or len(set(pages.values())) != len(pages):
        raise ValueError(f"Cannot safely merge {Path(path).name}: invalid Library import identity or page ownership.")
    return record


def check_download_path(root, path):
    """Allow the configured root itself to be a symlink, but no child paths."""
    root, path = Path(root).absolute(), Path(path).absolute()
    try:
        relative = path.relative_to(root)
    except ValueError:
        raise ValueError("The download path points outside the library folder") from None
    if not relative.parts or ".." in relative.parts:
        raise ValueError("The download path points outside the library folder")
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError(f"The download path contains a symbolic link: {current.name}. "
                             "It could point outside the library folder.")


def staging_folders(root, stage):
    check_download_path(root, stage)

    def failed(error):
        raise error

    for directory, children, filenames in os.walk(stage, followlinks=False, onerror=failed):
        # Include sidecars and partial files: gallery-dl writes those before import.
        for name in children + filenames:
            entry = (Path(directory) / name).lstat()
            if stat.S_ISLNK(entry.st_mode):
                raise ValueError(f"Download staging contains a symbolic link: {name}. "
                                 "Remove the link before retrying.")
            if stat.S_ISREG(entry.st_mode) and entry.st_nlink > 1:
                raise ValueError(f"Download staging contains a hard link: {name}. "
                                 "Move the linked file aside before retrying.")
            if not (stat.S_ISDIR(entry.st_mode) or stat.S_ISREG(entry.st_mode)):
                raise ValueError(f"Download staging requires a regular file or folder: {name}.")
        yield directory, children, filenames


def owned_imports(root, previous):
    owned = {}
    for filename in previous:
        path = Path(filename)
        check_download_path(root, path)
        if not path.is_file():
            continue
        record = read_import_record(path)
        key = identity_key(record["identity"])
        if key in owned and owned[key][0] != path:
            raise ValueError("Multiple archives claim the same Library import identity. Resolve the copies before retrying.")
        owned[key] = (path, record)
    return owned


def import_download(stage, root, previous, checkpoint=None, *, source=None):
    """Convert downloaded image directories to CBZs, merging retried/new pages."""
    stage, root = Path(stage), Path(root)
    source = source if source is not None else str(stage.absolute())
    outputs = {path for path in previous if Path(path).is_file()}
    owned = owned_imports(root, outputs)
    series_folders = {book_key(record["identity"]): path.parent for path, record in owned.values()
                      if record["identity"].get("kind") == "series"}
    groups = {}
    for directory, children, filenames in staging_folders(root, stage):
        images = sorted((Path(directory) / name for name in filenames
                         if Path(name).suffix.lower() in IMAGES),
                        key=natural)
        relative = Path(directory).relative_to(stage)
        for image in images:
            note = Path(str(image) + ".json")
            data = document(note)
            identity = import_identity(data, relative, source)
            key = identity_key(identity)
            group = groups.setdefault(key, dict(identity=identity, data=data, directory=Path(directory), images=[]))
            group["images"].append((image, identity_key(metadata_id(data,
                ("page_id", "image_id", "page", "num", "index"), ["filename", image.name]))))

    for key, group in groups.items():
        identity, data = group["identity"], group["data"]
        images = group["images"]
        if key in owned:
            target = owned[key][0]
        elif identity["kind"] == "series":
            collection = book_key(identity)
            target_dir = series_folders.setdefault(collection,
                root / (safe_name(data["manga"]) + " [" + digest(collection) + "]"))
            target = target_dir / (safe_name(group["directory"].name) + " [" + digest(key) + "].cbz")
        else:
            title = data.get("gallery_title") or data.get("title") or group["directory"].name
            target = root / (safe_name(title) + " [" + digest(key) + "].cbz")
        check_download_path(root, target)
        existing = read_import_record(target) if target.exists() else dict(identity=identity, pages={})
        if existing["identity"] != identity:
            raise ValueError(f"Import identity conflict for {target.name}. The existing archive was not changed.")
        names, page_ids = set(), set()
        for image, page_id in images:
            if image.name in names or page_id in page_ids:
                raise ValueError(f"Ambiguous page identities in {target.name}. The existing archive was not changed.")
            if image.name in existing["pages"] and existing["pages"][image.name] != page_id:
                raise ValueError(f"Page identity conflict for {image.name} in {target.name}. "
                                 "The existing archive was not changed.")
            names.add(image.name)
            page_ids.add(page_id)
        replaced = names | {name for name, page_id in existing["pages"].items() if page_id in page_ids}
        pages = {name: page_id for name, page_id in existing["pages"].items() if name not in replaced}
        pages.update({image.name: page_id for image, page_id in images})
        record = dict(version=1, identity=identity, pages=pages)
        # Validate before changing a published book. Never include partial files.
        for image, _ in images:
            if image.stat().st_size > MAX_ENTRY_BYTES:
                raise ValueError("A downloaded image exceeds the 200 MiB page limit")
            try:
                with bounded_image(image) as decoded:
                    decoded.verify()
                # Verification can skip pixel decoding. Reopen after verify()
                # to check that the page can actually be loaded.
                with bounded_image(image) as decoded:
                    decoded.load()
            except (OSError, SyntaxError, EOFError) as error:
                raise OSError(f"Invalid downloaded image {image.name}: {error}") from error
        target.parent.mkdir(parents=True, exist_ok=True)
        check_download_path(root, target)
        temporary = None
        replaced.update(("info.json", IMPORT_RECORD))
        try:
            # Secure creation and the open handle avoid following a planted .part
            # file. Keep it beside the destination for an atomic final rename.
            with tempfile.NamedTemporaryFile(mode="w+b", dir=target.parent, prefix=".library-",
                                             suffix=".cbz.part", delete=False) as stream:
                temporary = Path(stream.name)
                with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_STORED) as output:
                    if target.exists():
                        with zipfile.ZipFile(target) as old:
                            for item in old.infolist():
                                if item.filename not in replaced:
                                    with old.open(item) as source, output.open(item, "w") as destination:
                                        shutil.copyfileobj(source, destination)
                    for image, _ in images:
                        output.write(image, image.name)
                    output.writestr("info.json", json.dumps(data, ensure_ascii=False, default=str))
                    output.writestr(IMPORT_RECORD, identity_key(record))
            check_download_path(root, target)
            temporary.replace(target)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        outputs.add(str(target))
        owned[key] = (target, record)
        if checkpoint:
            checkpoint(sorted(outputs))
        # Leave failed/partial jobs intact. Remove only images now in a closed CBZ.
        for image, _ in images:
            image.unlink()
            Path(str(image) + ".json").unlink(missing_ok=True)
    return sorted(outputs)


def update_job(library, identity, **changes):
    if changes.get("status") in ("completed", "failed", "cancelled"):
        changes["finished"] = time.time()
    with changing(library.queue_path, reader=download_state) as queue:
        for job in queue.get("jobs", []):
            if job["id"] == identity:
                job.update(changes)
                return dict(job)
    raise ValueError("Download job disappeared")


def notify(summary, body):
    try:
        subprocess.run(["notify-send", "-a", "Library", "-i", "folder-download", summary, body], timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        pass  # Notification delivery cannot change a completed download's result.


class DownloadLog:
    """Keep the current and previous log bounded, including during noisy jobs."""
    def __init__(self, path):
        self.path = Path(path)
        self.stream = None

    def __enter__(self):
        for path in (self.path, self.path.with_suffix(".previous.log")):
            if path.exists() and path.stat().st_size > MAX_LOG_BYTES:
                with path.open("r+b") as stream:
                    stream.seek(-MAX_LOG_BYTES, os.SEEK_END)
                    tail = stream.read(MAX_LOG_BYTES)
                    stream.seek(0)
                    stream.write(tail)
                    stream.truncate()
        self.stream = self.path.open("ab", buffering=0)
        return self

    def write(self, data):
        while data:
            room = MAX_LOG_BYTES - self.stream.tell()
            if room <= 0:
                self.stream.close()
                self.path.replace(self.path.with_suffix(".previous.log"))
                self.stream = self.path.open("wb", buffering=0)
                room = MAX_LOG_BYTES
            self.stream.write(data[:room])
            data = data[room:]

    def __exit__(self, *error):
        self.stream.close()


def exec_download(library, identity, parent_pid):
    """Keep the downloader bound to its worker, including uncatchable worker exits."""
    import ctypes
    if parent_pid is None or parent_pid <= 1:
        raise ValueError("A download must have a worker parent")
    # Install this in an exec stage, avoiding preexec_fn in threaded callers.
    libc = ctypes.CDLL(None, use_errno=True)
    libc.prctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong]
    libc.prctl.restype = ctypes.c_int
    pr_set_pdeathsig = 1
    if libc.prctl(pr_set_pdeathsig, signal.SIGKILL, 0, 0, 0) != 0:
        error = ctypes.get_errno()
        raise OSError(error, "Could not protect the downloader's worker lifetime: " + os.strerror(error))
    if os.getppid() != parent_pid:
        raise InterruptedError("Download worker stopped before the downloader started")
    job = library.job(identity)
    if job.get("cancelled"):
        return
    config = library.state / (identity + ".config.json")
    os.environ["PYTHONUNBUFFERED"] = "1"
    os.execvp("gallery-dl", ["gallery-dl", "--no-input", "--config-json", str(config), "--", job["url"]])


def stop_download(process):
    if process.returncode is not None:
        return
    try:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        deadline = time.monotonic() + DOWNLOAD_STOP_TIMEOUT
        while os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT) is None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            time.sleep(min(0.05, remaining))
    finally:
        # Retain the leader's PID until after signalling its group, even if it
        # exited on TERM. This also kills children which ignored TERM, safely.
        try:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        finally:
            process.wait()


def run_download(library, job):
    root = Path(job["root"])
    if not root.is_dir() or not os.access(root, os.W_OK):
        raise ValueError("Library folder is unavailable or read-only. Check the drive before retrying.")
    if root.stat().st_dev != job.get("device", root.stat().st_dev):
        raise ValueError("The library drive changed or was unmounted. Reconnect it, then retry.")
    # Old queue paths alone do not prove that a pre-existing archive belongs
    # to this source. Refuse unsafe legacy merges before requesting any files.
    owned_imports(root, job.get("outputs", []))
    stage = root / ".library-downloads" / job["id"]
    check_download_path(root, stage)
    stage.mkdir(parents=True, exist_ok=True, mode=0o700)
    files = 0
    for _, _, filenames in staging_folders(root, stage):
        files += sum(Path(name).suffix.lower() in IMAGES for name in filenames)
    archive = library.state / "archives" / (job["id"] + ".sqlite3")
    archive.parent.mkdir(parents=True, exist_ok=True)
    config = library.state / (job["id"] + ".config.json")
    atomic_json(config, download_config(stage, archive))
    command = [sys.executable, str(Path(__file__).resolve()), "--root", str(root),
               "--state", str(library.state), "--cache", str(library.cache),
               "--parent-pid", str(os.getpid()), "--job-id", job["id"], "download"]
    with DownloadLog(library.log_path) as log:
        log.write(f"\nDownload started {time.strftime('%Y-%m-%d %H:%M')}\n".encode())
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            previous_files, tail = None, b""
            next_check = 0
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while selector.get_map() or process.poll() is None:
                    for key, _ in selector.select(max(0, next_check - time.monotonic())):
                        chunk = os.read(key.fd, 64 * 1024)
                        if not chunk:
                            selector.unregister(key.fileobj)
                            continue
                        combined = tail + chunk
                        files += combined.count(DOWNLOAD_EVENT)
                        combined = combined.replace(DOWNLOAD_EVENT, b"")
                        keep = 0
                        for size in range(1, min(len(combined), len(DOWNLOAD_EVENT) - 1) + 1):
                            if combined.endswith(DOWNLOAD_EVENT[:size]):
                                keep = size
                        log.write(combined[:-keep] if keep else combined)
                        tail = combined[-keep:] if keep else b""
                    if time.monotonic() >= next_check:
                        current = library.job(job["id"])
                        if current.get("cancelled"):
                            return dict(status="cancelled", error="Download stopped. Retry to resume.")
                        if files != previous_files:
                            update_job(library, job["id"], files=files)
                            previous_files = files
                        next_check = time.monotonic() + 0.4
                if files != previous_files:
                    update_job(library, job["id"], files=files)
                log.write(tail)
        finally:
            stop_download(process)
            process.stdout.close()
    current = library.job(job["id"])
    if current.get("cancelled"):
        return dict(status="cancelled", error="Download stopped. Retry to resume.")
    if process.returncode:
        raise ValueError(f"gallery-dl exited with code {process.returncode}. See Download details; "
                         "configure any required login in your private gallery-dl config, then retry.")
    if not root.is_dir() or root.stat().st_dev != job.get("device", root.stat().st_dev):
        raise ValueError("The library drive became unavailable. Reconnect it, then retry.")
    def checkpoint(outputs):
        current = update_job(library, job["id"], outputs=outputs)
        if current.get("cancelled"):
            raise InterruptedError("Download stopped during import. Retry to resume.")

    try:
        outputs = import_download(stage, root, job.get("outputs", []), checkpoint, source=job["url"])
    except InterruptedError as error:
        return dict(status="cancelled", error=str(error))
    if not outputs:
        raise ValueError("No supported images were downloaded. Check Download details and the URL.")
    # Imported files have been removed individually. Remove empty directories
    # only; any remaining file stays available for inspection or explicit discard.
    for directory, _, _ in os.walk(stage, topdown=False):
        try:
            Path(directory).rmdir()
        except OSError:
            pass
    return dict(status="completed", error="", outputs=outputs)


def worker(library, inherited_fd=None):
    with worker_lock(library, inherited_fd) as lock:
        if lock is None:
            return
        # A previous worker may have died. Retain staging files for explicit retry.
        with changing(library.queue_path, reader=download_state) as queue:
            for job in queue.get("jobs", []):
                if job["status"] == "running":
                    job.update(status="failed", error="Download worker stopped. Retry to resume.")
        while True:
            with changing(library.queue_path, reader=download_state) as queue:
                job = next((item for item in queue.get("jobs", []) if item["status"] == "pending"), None)
                if job is None:
                    # Release while holding the queue lock, so an arriving job's
                    # worker cannot miss work during this worker's exit.
                    fcntl.flock(lock, fcntl.LOCK_UN)
                    return
                job["status"] = "running"
                job = dict(job)
            try:
                result = run_download(library, job)
            except (OSError, ValueError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
                result = dict(status="failed", error=str(error))
            update_job(library, job["id"], **result)
            if result["status"] == "completed":
                notify("Library download completed", f'{len(result["outputs"])} book or chapter archive(s) saved.')
            elif result["status"] == "failed":
                notify("Library download failed", result["error"])
            try:
                library.prune_history()
            except (OSError, ValueError) as error:
                print(f"Library history cleanup failed: {error}", file=sys.stderr)


def stop_worker(signum, frame):
    raise SystemExit(128 + signum)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--cache", required=True)
    parser.add_argument("--worker-lock-fd", type=int)
    parser.add_argument("--parent-pid", type=int)
    parser.add_argument("--job-id")
    parser.add_argument("mode", choices=("serve", "worker", "download"))
    args = parser.parse_args()
    os.umask(0o077)
    library = Library(args.root, args.state, args.cache)
    if args.mode == "download":
        exec_download(library, args.job_id, args.parent_pid)
        return
    if args.mode == "worker":
        signal.signal(signal.SIGTERM, stop_worker)
        worker(library, args.worker_lock_fd)
        return
    print(json.dumps({"ready": True}), flush=True)
    output_lock = threading.Lock()
    scan_lock = threading.Lock()
    scan_active = False
    scan_thread = None

    def emit(result):
        with output_lock:
            print(json.dumps(result, ensure_ascii=False), flush=True)

    def scan():
        nonlocal scan_active
        try:
            result = library.scan(lambda update: emit(dict(event="scan", scanning=True, **update)))
            # Only generated caches are removed automatically. Unfinished
            # download files require the user's explicit Discard action.
            try:
                library.maintain_cache({book["cover"] for book in result["books"]})
                library.prune_history()
            except (OSError, ValueError) as error:
                result["warnings"].append(f"Library cleanup: {error}")
            result = dict(event="scan", scanning=False, **result)
        except (OSError, ValueError, KeyError, subprocess.SubprocessError, zipfile.BadZipFile, ET.ParseError) as error:
            result = dict(event="scan", scanning=False, error=str(error))
        with scan_lock:
            scan_active = False
            emit(result)

    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            if not isinstance(request, dict):
                request = {}
                raise ValueError("Expected a JSON object for the library command")
            if request.get("op") == "scan":
                reading_state(library.progress_path)
                with scan_lock:
                    emit(dict(ok=True, reply=request.get("id"), op="scan", scanning=True))
                    if not scan_active:
                        scan_active = True
                        scan_thread = threading.Thread(target=scan, daemon=True)
                        scan_thread.start()
                continue
            result = dict(library.dispatch(request), ok=True, reply=request.get("id"), op=request.get("op"))
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError,
                zipfile.BadZipFile, ET.ParseError) as error:
            result = dict(ok=False, reply=request.get("id"), op=request.get("op"), error=str(error))
        emit(result)
    if scan_thread is not None:
        scan_thread.join()


if __name__ == "__main__":
    main()
