"""Synthetic archive, import, and worker regression tests. No personal URLs or content."""
import importlib.util
from contextlib import contextmanager
import ctypes
import fcntl
import io
import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import struct
import sys
import tarfile
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import zipfile

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("library", REPO / "scripts/library.py")
library = importlib.util.module_from_spec(spec)
spec.loader.exec_module(library)


def image_bytes(color="#8aafbd", image_format="PNG"):
    stream = io.BytesIO()
    Image.new("RGB", (100, 160), color).save(stream, image_format)
    return stream.getvalue()


def oversized_bmp(width, height):
    # Only a header and one pixel: the size guard must run before pixel decoding.
    header = b"BM" + struct.pack("<IHHI", 58, 0, 0, 54)
    header += struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, 4, 0, 0, 0, 0)
    return header + b"\x1e\x14\x0a\x00"


def archive(path, metadata=None, xml=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as output:
        for name in ("nested/10.png", "nested/2.png", "nested/1.png"):
            output.writestr(name, image_bytes())
        output.writestr("__MACOSX/ignored.png", b"not an image")
        if metadata:
            output.writestr("info.json", json.dumps(metadata))
        if xml:
            output.writestr("ComicInfo.xml", xml)


def download_image(path, data, color="#8aafbd"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(image_bytes(color))
    Path(str(path) + ".json").write_text(json.dumps(data))
    return path


def queued_job(root, identity="synthetic", status="pending", **fields):
    job = dict(id=identity, status=status, root=str(root),
               url="https://reader.example.test/" + identity, outputs=[], files=0, error="")
    job.update(fields)
    return job


@contextmanager
def archive_process(program):
    """Run a controlled archive-tool stand-in and retain its process for cleanup checks."""
    real_popen = subprocess.Popen
    processes = []

    def launch(command, **kwargs):
        assert command[0] == "bsdtar"
        process = real_popen([sys.executable, "-u", "-c", program], **kwargs)
        processes.append(process)
        return process

    try:
        with patch.object(library.subprocess, "Popen", side_effect=launch):
            yield processes
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.wait()


def wait_for_pid(path):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            return int(path.read_text())
        except (FileNotFoundError, ValueError):
            time.sleep(0.02)
    raise AssertionError("Synthetic process did not start")


@contextmanager
def process_handle(pid):
    """Pin a synthetic process's identity so cleanup cannot signal a reused PID."""
    descriptor = os.pidfd_open(pid)
    try:
        yield descriptor
    finally:
        try:
            signal.pidfd_send_signal(descriptor, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.close(descriptor)


class LibraryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="qs-library-test-")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.root = self.base / "books"
        self.root.mkdir()
        self.library = library.Library(self.root, self.base / "state", self.base / "cache")
        self.chapter = self.root / "Example series" / "c002.cbz"
        archive(self.chapter, dict(tags=["tag:quiet", "uncensored"], language="English",
                                   artist=["Example artist"], characters=["Example character"]))

    def test_indexes_series_standalones_and_metadata_with_numeric_page_order(self):
        archive(self.root / "Example series" / "c010.cbz", xml="""<ComicInfo>
<Writer>Second artist</Writer><LanguageISO>ja</LanguageISO><Tags>parody:example, tag:quiet</Tags>
</ComicInfo>""")
        archive(self.root / "Standalone #100%.cbz", dict(title="Standalone title"))
        (self.root / "broken.cbz").write_text("not an archive")
        result = self.library.scan()
        self.assertEqual(len(result["books"]), 2)
        self.assertEqual(len(result["warnings"]), 1)
        series = next(book for book in result["books"] if len(book["chapters"]) == 2)
        self.assertEqual([c["name"] for c in series["chapters"]], ["c002", "c010"])
        self.assertEqual(series["meta"]["languages"], ["english", "ja"])
        self.assertEqual(series["meta"]["parodies"], ["example"])
        self.assertEqual(series["meta"]["censorship"], ["uncensored"])
        self.assertTrue(Path(series["cover"]).is_file())
        self.assertEqual(library.page_names(library.members(self.chapter)),
                         ["nested/1.png", "nested/2.png", "nested/10.png"])

    def test_resume_last_page_does_not_mark_complete_and_explicit_completion_advances(self):
        archive(self.root / "Example series" / "c010.cbz")
        self.library.save_progress(str(self.chapter), 2)
        series = self.library.scan()["books"][0]
        self.assertFalse(series["chapters"][0]["done"])
        self.assertEqual(series["resume"], 0)
        self.assertEqual(self.library.open_archive(str(self.chapter))["page"], 2)
        self.library.save_progress(str(self.chapter), 2, True)
        self.library.save_progress(str(self.chapter), 2)
        series = self.library.scan()["books"][0]
        self.assertEqual(series["resume"], 1)
        self.assertTrue(series["chapters"][0]["done"])
        self.assertEqual(self.library.open_archive(str(self.chapter))["page"], 0)
        self.library.mark([str(self.chapter)], False)
        self.assertFalse(self.library.scan()["books"][0]["chapters"][0]["done"])

    def test_auto_turn_delay_is_persisted_and_rejects_invalid_values(self):
        for seconds in (1, 25, 3600):
            self.library.dispatch(dict(op="setting", key="autoTurnSeconds", value=seconds))
            self.assertEqual(self.library.scan()["settings"]["autoTurnSeconds"], seconds)
        original = self.library.progress_path.read_bytes()
        for seconds in (0, -1, 3601, True, "10", 1.5, None):
            with self.subTest(seconds=seconds):
                with self.assertRaises(ValueError):
                    self.library.dispatch(dict(op="setting", key="autoTurnSeconds", value=seconds))
                self.assertEqual(self.library.progress_path.read_bytes(), original)

    def test_flat_extraction_does_not_follow_archive_paths(self):
        path = self.root / "Traversal.cbz"
        with zipfile.ZipFile(path, "w") as output:
            output.writestr("../../escape.png", image_bytes())
        result = self.library.open_archive(str(path))
        self.assertTrue(all(Path(page).is_relative_to(self.base / "cache" / "pages") for page in result["pages"]))
        self.assertFalse((self.base / "escape.png").exists())
        self.assertTrue(all(Path(page).is_file() for page in result["pages"]))

    @unittest.skipUnless(shutil.which("bsdtar"), "bsdtar is required")
    def test_non_zip_libarchive_path_uses_literal_member_names(self):
        path = self.root / "Libarchive fixture.cbr"
        with tarfile.open(path, "w") as output:
            for name in ["pages/2 [test].png", "pages/1.png"]:
                content = image_bytes()
                entry = tarfile.TarInfo(name)
                entry.size = len(content)
                output.addfile(entry, io.BytesIO(content))
        result = self.library.open_archive(str(path))
        self.assertEqual(len(result["pages"]), 2)
        self.assertTrue(all(Path(page).read_bytes() == image_bytes() for page in result["pages"]))
        Path(result["pages"][0]).unlink()
        self.assertEqual(self.library.open_archive(str(path)), result)
        self.assertTrue(all(Path(page).read_bytes() == image_bytes() for page in result["pages"]))

    @unittest.skipUnless(shutil.which("bsdtar"), "libarchive is required")
    def test_cbr_extraction_reads_all_pages_in_one_process(self):
        path = self.root / "Single pass.cbr"
        with tarfile.open(path, "w") as output:
            for name in ("nested/10.png", "nested/2.png", "../../1.png"):
                content = image_bytes()
                entry = tarfile.TarInfo(name)
                entry.size = len(content)
                output.addfile(entry, io.BytesIO(content))
        self.library.details(path)
        with patch.object(library.subprocess, "Popen", wraps=subprocess.Popen) as launch:
            opened = self.library.open_archive(str(path))
        self.assertEqual(launch.call_count, 1)
        self.assertTrue(any(str(arg).endswith("library_archive.py") for arg in launch.call_args.args[0]))
        self.assertEqual(len(opened["pages"]), 3)
        self.assertTrue(all(Path(page).read_bytes() == image_bytes() for page in opened["pages"]))
        self.assertFalse((self.base / "1.png").exists())

    def test_background_scan_allows_progress_and_status_before_covers_finish(self):
        helper = self.base / "slow-cover-helper.py"
        helper.write_text('''import sys, time
sys.path.insert(0, %r)
import library
original = library.Library.cover
def slow_cover(self, *args, **kwargs):
    if kwargs.get("generate", True):
        time.sleep(0.3)
    return original(self, *args, **kwargs)
library.Library.cover = slow_cover
library.main()
''' % str(REPO / "scripts"))
        requests = [dict(id=1, op="scan"), dict(id=2, op="status"),
                    dict(id=3, op="progress", file=str(self.chapter), page=1)]
        result = subprocess.run([sys.executable, "-B", str(helper), "--root", str(self.root),
            "--state", str(self.library.state), "--cache", str(self.library.cache), "serve"],
            input="".join(json.dumps(item) + "\n" for item in requests),
            capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        final = next(item for item in replies if item.get("event") == "scan" and not item["scanning"])
        partial = next(item for item in replies if item.get("event") == "scan" and item["scanning"])
        for identity in (2, 3):
            reply = next(item for item in replies if item.get("reply") == identity)
            self.assertTrue(reply["ok"])
            self.assertLess(replies.index(reply), replies.index(final))
        self.assertEqual(partial["books"][0]["cover"], "")
        self.assertTrue(Path(final["books"][0]["cover"]).is_file())
        self.assertEqual(final["books"][0]["chapters"][0]["page"], 1)

    def test_cache_maintenance_bounds_unused_files_and_protects_current_covers(self):
        covers, metadata = self.library.cache / "covers", self.library.cache / "metadata"
        covers.mkdir(parents=True)
        metadata.mkdir()
        current = covers / "current.jpg"
        recent = covers / "recent.jpg"
        older = covers / "older.jpg"
        stale = metadata / "stale.json"
        for path in (current, recent, older, stale):
            path.write_bytes(b"x" * 80)
        now = time.time()
        os.utime(older, (now - 10, now - 10))
        os.utime(stale, (now - 91 * 86400, now - 91 * 86400))
        outside = self.base / "outside.jpg"
        outside.write_bytes(b"keep")
        (covers / "link.jpg").symlink_to(outside)
        with patch.object(library, "COVER_CACHE_BYTES", 100):
            self.library.maintain_cache({str(current)})
        self.assertTrue(current.exists())
        self.assertTrue(recent.exists())
        self.assertFalse(older.exists())
        self.assertFalse(stale.exists())
        self.assertEqual(outside.read_bytes(), b"keep")
        self.assertTrue((covers / "link.jpg").is_symlink())

    def test_history_cleanup_keeps_unfinished_jobs_and_saved_books(self):
        jobs = [queued_job(self.root, f"completed-{index}", "completed", finished=time.time() + index)
                for index in range(5)]
        jobs += [queued_job(self.root, "failed", "failed"), queued_job(self.root, "cancelled", "cancelled"),
                 queued_job(self.root, "pending", "pending"), queued_job(self.root, "running", "running"),
                 queued_job(self.root, "legacy", "completed"),
                 queued_job(self.root, "expired", "completed", finished=time.time() - 91 * 86400)]
        library.atomic_json(self.library.queue_path, dict(jobs=jobs))
        for job in jobs:
            ledger = self.library.state / "archives" / (job["id"] + ".sqlite3")
            ledger.parent.mkdir(exist_ok=True)
            ledger.write_bytes(b"retained retry ledger")
        with patch.object(library, "HISTORY_LIMIT", 2):
            self.library.prune_history()
        saved = library.download_state(self.library.queue_path)["jobs"]
        self.assertEqual({job["id"] for job in saved},
                         {"completed-3", "completed-4", "failed", "cancelled", "pending", "running"})
        for job in saved:
            self.assertTrue((self.library.state / "archives" / (job["id"] + ".sqlite3")).exists())
        self.assertFalse((self.library.state / "archives" / "completed-0.sqlite3").exists())
        self.assertTrue(self.chapter.exists())

    def test_discard_clears_only_selected_working_files_and_keeps_books_and_progress(self):
        self.library.save_progress(str(self.chapter), 1)
        job = queued_job(self.root, "failed", "failed", outputs=[str(self.chapter)])
        other = queued_job(self.root, "other", "cancelled")
        library.atomic_json(self.library.queue_path, dict(jobs=[job, other]))
        stage = self.root / ".library-downloads" / "failed"
        stage.mkdir(parents=True)
        (stage / "page.part").write_bytes(b"unfinished")
        outside = self.base / "outside.txt"
        outside.write_bytes(b"keep")
        (stage / "link").symlink_to(outside)
        untouched = self.root / ".library-downloads" / "other"
        untouched.mkdir()
        (untouched / "page.part").write_bytes(b"keep retry data")
        self.library.discard("failed")
        self.assertFalse(stage.exists())
        self.assertTrue(self.chapter.exists())
        self.assertEqual(outside.read_bytes(), b"keep")
        self.assertEqual((untouched / "page.part").read_bytes(), b"keep retry data")
        self.assertEqual(library.reading_state(self.library.progress_path)["progress"][str(self.chapter)]["page"], 1)
        self.assertTrue(self.library.job("failed")["discarded"])
        library.update_job(self.library, "other", status="pending")
        with self.assertRaisesRegex(ValueError, "Cancel"):
            self.library.discard("other")
        library.update_job(self.library, "other", status="cancelled", device=self.root.stat().st_dev + 1)
        with self.assertRaisesRegex(ValueError, "drive"):
            self.library.discard("other")
        self.assertEqual((untouched / "page.part").read_bytes(), b"keep retry data")

    def test_download_log_rotates_during_a_single_job(self):
        with patch.object(library, "MAX_LOG_BYTES", 100):
            with library.DownloadLog(self.base / "test.log") as log:
                log.write(b"a" * 180)
                log.write(b"b" * 250)
        self.assertEqual((self.base / "test.log").read_bytes(), b"b" * 30)
        self.assertEqual((self.base / "test.previous.log").read_bytes(), b"b" * 100)
        (self.base / "test.log").write_bytes(b"old" * 100)
        (self.base / "test.previous.log").write_bytes(b"history" * 100)
        with patch.object(library, "MAX_LOG_BYTES", 100), library.DownloadLog(self.base / "test.log"):
            pass
        self.assertEqual((self.base / "test.log").stat().st_size, 100)
        self.assertEqual((self.base / "test.previous.log").stat().st_size, 100)

    def test_download_progress_uses_split_completion_events_without_rescanning_staging(self):
        job = queued_job(self.root, status="running")
        library.atomic_json(self.library.queue_path, dict(jobs=[job]))
        stage = self.root / ".library-downloads" / job["id"] / "gallery"
        program = '''import os, sys, time, json
from pathlib import Path
stage = Path(%r)
stage.mkdir(parents=True, exist_ok=True)
for page in (1, 2):
    image = stage / (str(page) + ".png")
    image.write_bytes(%r)
    Path(str(image) + ".json").write_text(json.dumps(dict(title="Gallery", gallery_id=7, page=page)))
    sys.stdout.buffer.write(b"log line\\n" * 1000)
    sys.stdout.buffer.write(%r[:8])
    sys.stdout.flush()
    time.sleep(0.03)
    sys.stdout.buffer.write(%r[8:])
    sys.stdout.flush()
''' % (str(stage), image_bytes(), library.DOWNLOAD_EVENT, library.DOWNLOAD_EVENT)
        real_popen = subprocess.Popen
        def launch(command, **kwargs):
            return real_popen([sys.executable, "-c", program], **kwargs)
        with patch.object(library.subprocess, "Popen", side_effect=launch), \
                patch.object(Path, "rglob", side_effect=AssertionError("Recursive progress polling")), \
                patch.object(library, "MAX_LOG_BYTES", 1000):
            result = library.run_download(self.library, job)
        self.assertEqual(result["status"], "completed")
        self.assertEqual(self.library.job(job["id"])["files"], 2)
        self.assertEqual(len(result["outputs"]), 1)
        for path in (self.library.log_path, self.library.log_path.with_suffix(".previous.log")):
            self.assertLessEqual(path.stat().st_size, 1000)
            self.assertNotIn(b"QS_LIBRARY_IMAGE", path.read_bytes())

    @unittest.skipUnless(shutil.which("bsdtar"), "bsdtar is required")
    def test_zip_and_libarchive_entry_limits_preserve_cache_and_allow_exact_limit(self):
        content = image_bytes()
        for suffix in (".cbz", ".cbr"):
            with self.subTest(suffix=suffix):
                path = self.root / ("Entry limit" + suffix)
                if suffix == ".cbz":
                    with zipfile.ZipFile(path, "w") as output:
                        output.writestr("001.png", content)
                else:
                    with tarfile.open(path, "w") as output:
                        entry = tarfile.TarInfo("001.png")
                        entry.size = len(content)
                        output.addfile(entry, io.BytesIO(content))
                with patch.object(library, "MAX_ENTRY_BYTES", len(content) - 1):
                    with self.assertRaisesRegex(ValueError, "page limit"):
                        self.library.open_archive(str(path))
                self.assertEqual(list((self.library.cache / "pages").iterdir()), [])
                with patch.object(library, "MAX_ENTRY_BYTES", len(content)):
                    result = self.library.open_archive(str(path))
                self.assertEqual(Path(result["pages"][0]).read_bytes(), content)
                shutil.rmtree(self.library.cache / "pages")

    @unittest.skipUnless(shutil.which("bsdtar"), "bsdtar is required")
    def test_zip_and_libarchive_chapter_limits_do_not_publish_partial_cache(self):
        content = image_bytes()
        for suffix in (".cbz", ".cbr"):
            with self.subTest(suffix=suffix):
                path = self.root / ("Chapter limit" + suffix)
                if suffix == ".cbz":
                    with zipfile.ZipFile(path, "w") as output:
                        for name in ("001.png", "002.png"):
                            output.writestr(name, content)
                else:
                    with tarfile.open(path, "w") as output:
                        for name in ("001.png", "002.png"):
                            entry = tarfile.TarInfo(name)
                            entry.size = len(content)
                            output.addfile(entry, io.BytesIO(content))
                with patch.object(library, "MAX_CHAPTER_BYTES", 2 * len(content) - 1):
                    with self.assertRaisesRegex(ValueError, "cache limit"):
                        self.library.open_archive(str(path))
                self.assertEqual(list((self.library.cache / "pages").iterdir()), [])
                with patch.object(library, "MAX_CHAPTER_BYTES", 2 * len(content)):
                    self.assertEqual(len(self.library.open_archive(str(path))["pages"]), 2)
                shutil.rmtree(self.library.cache / "pages")

    def test_archive_output_limits_stop_and_reap_the_tool(self):
        path = self.base / "fixture.cbr"
        path.write_bytes(b"archive tool stand-in")
        for kind in ("entry", "listing", "diagnostics"):
            with self.subTest(kind=kind):
                stream = "stderr" if kind == "diagnostics" else "stdout"
                program = (f"import sys,time; sys.{stream}.buffer.write(b'x' * (1024 * 1024)); "
                           f"sys.{stream}.flush(); time.sleep(2)")
                message = {"entry": "page limit", "listing": "listing exceeds",
                           "diagnostics": "diagnostics exceed"}[kind]
                with archive_process(program) as processes, \
                        patch.object(library, "MAX_ENTRY_BYTES", 1024), \
                        patch.object(library, "MAX_LISTING_BYTES", 1024):
                    with self.assertRaisesRegex(ValueError, message):
                        if kind == "listing":
                            library.members(path)
                        else:
                            library.member_bytes(path, "001.png")
                    self.assertLess(processes[0].returncode, 0)
                    self.assertTrue(processes[0].stdout.closed)
                    self.assertTrue(processes[0].stderr.closed)

    def test_archive_tool_errors_and_deadlines_do_not_leave_a_child_running(self):
        path = self.base / "fixture.cbr"
        path.write_bytes(b"archive tool stand-in")
        with archive_process("import sys; sys.stderr.write('Unreadable fixture'); sys.exit(3)") as processes:
            with self.assertRaisesRegex(ValueError, "Unreadable fixture"):
                library.member_bytes(path, "001.png")
            self.assertEqual(processes[0].returncode, 3)
        for program in ("import time; time.sleep(2)",
                        "import os,time; os.close(1); os.close(2); time.sleep(2)"):
            with self.subTest(program=program), archive_process(program) as processes:
                with self.assertRaises(subprocess.TimeoutExpired):
                    library.archive_output(["bsdtar"], 1024, 0.1, "Output too large")
                self.assertLess(processes[0].returncode, 0)
                self.assertTrue(processes[0].stdout.closed)
                self.assertTrue(processes[0].stderr.closed)

    def test_oversized_embedded_and_local_covers_warn_without_stopping_scan(self):
        for kind in ("embedded", "local"):
            for width, height in ((16000, 10000), (200000, 200000)):
                name = f"Oversized {kind} {width}"
                content = oversized_bmp(width, height)
                if kind == "embedded":
                    with zipfile.ZipFile(self.root / (name + ".cbz"), "w") as output:
                        output.writestr("001.bmp", content)
                else:
                    folder = self.root / name
                    archive(folder / "001.cbz")
                    (folder / "cover.bmp").write_bytes(content)
        result = self.library.scan()
        self.assertEqual(len(result["books"]), 5)
        self.assertEqual(len(result["warnings"]), 4)
        self.assertTrue(all("safe pixel limit" in warning for warning in result["warnings"]))
        healthy = next(book for book in result["books"] if book["name"] == "Example series")
        self.assertTrue(Path(healthy["cover"]).is_file())

    def test_oversized_download_images_preserve_existing_archives_and_staging(self):
        stage = self.root / ".library-downloads" / "fixture"
        data = dict(title="Gallery", gallery_id=7, page=1)
        download_image(stage / "gallery" / "001.png", data)
        outputs = library.import_download(stage, self.root, [])
        before = Path(outputs[0]).read_bytes()
        for width, height in ((16000, 10000), (200000, 200000)):
            with self.subTest(width=width):
                image = stage / "gallery" / "002.bmp"
                image.write_bytes(oversized_bmp(width, height))
                Path(str(image) + ".json").write_text(json.dumps(dict(data, page=2)))
                with self.assertRaisesRegex(ValueError, "safe pixel limit"):
                    library.import_download(stage, self.root, outputs)
                self.assertEqual(Path(outputs[0]).read_bytes(), before)
                self.assertTrue(image.is_file())
                self.assertEqual(list(self.root.glob(".*.part")), [])

    def test_download_byte_limit_does_not_replace_an_existing_archive(self):
        stage = self.root / ".library-downloads" / "fixture"
        data = dict(title="Gallery", gallery_id=7, page=1)
        download_image(stage / "gallery" / "001.png", data)
        outputs = library.import_download(stage, self.root, [])
        before = Path(outputs[0]).read_bytes()
        image = download_image(stage / "gallery" / "002.png", dict(data, page=2))
        with patch.object(library, "MAX_ENTRY_BYTES", image.stat().st_size - 1):
            with self.assertRaisesRegex(ValueError, "page limit"):
                library.import_download(stage, self.root, outputs)
        self.assertEqual(Path(outputs[0]).read_bytes(), before)
        self.assertTrue(image.is_file())

    def test_helper_accepts_another_command_after_scanning_an_oversized_cover(self):
        with zipfile.ZipFile(self.root / "Oversized.cbz", "w") as output:
            output.writestr("001.bmp", oversized_bmp(200000, 200000))
        requests = [dict(id=1, op="scan"), dict(id=2, op="status")]
        result = subprocess.run([sys.executable, "-B", str(REPO / "scripts/library.py"),
            "--root", str(self.root), "--state", str(self.library.state),
            "--cache", str(self.library.cache), "serve"],
            input="".join(json.dumps(request) + "\n" for request in requests),
            capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertTrue(replies[0]["ready"])
        scan = next(reply for reply in replies if reply.get("reply") == 1)
        status = next(reply for reply in replies if reply.get("reply") == 2)
        finished = next(reply for reply in replies if reply.get("event") == "scan" and not reply["scanning"])
        self.assertTrue(scan["ok"])
        self.assertTrue(scan["scanning"])
        self.assertTrue(status["ok"])
        self.assertIn("safe pixel limit", finished["warnings"][0])
        self.assertEqual(result.stderr, "")

    def test_open_mark_and_trash_reject_items_outside_library_and_symlinks(self):
        outside = self.base / "outside.cbz"
        archive(outside)
        link = self.root / "link.cbz"
        link.symlink_to(outside)
        for path in (outside, link, self.root):
            with self.assertRaises(ValueError):
                self.library.open_archive(str(path))
            with self.assertRaises(ValueError):
                self.library.trash(str(path))
        self.assertEqual(len(self.library.scan()["books"]), 1)

    def test_corrupt_reading_state_is_preserved(self):
        self.library.state.mkdir()
        self.library.progress_path.write_text("{")
        with self.assertRaises(ValueError):
            self.library.save_progress(str(self.chapter), 0)
        self.assertEqual(self.library.progress_path.read_text(), "{")
        self.library.progress_path.write_text('{"progress":[]}')
        with self.assertRaises(ValueError):
            self.library.save_progress(str(self.chapter), 0)
        self.assertEqual(self.library.progress_path.read_text(), '{"progress":[]}')

    def test_invalid_nested_reading_state_is_rejected_without_writes_or_trash(self):
        invalid_states = [
            {"progress": {str(self.chapter): entry}} for entry in
            (None, [], "invalid", {"page": "1"}, {"page": -1}, {"page": True},
             {"done": 1}, {"read": "yesterday"}, {"read": -1}, {"read": float("inf")})
        ] + [{"settings": settings} for settings in
             ({"rtl": "false"}, {"fit": []}, {"fit": "invalid"}, {"sort": None},
              {"autoTurnSeconds": 0}, {"autoTurnSeconds": 3601},
              {"autoTurnSeconds": True}, {"autoTurnSeconds": "10"})]
        operations = [self.library.scan, lambda: self.library.open_archive(str(self.chapter)),
                      lambda: self.library.save_progress(str(self.chapter), 1),
                      lambda: self.library.mark([str(self.chapter)], True),
                      lambda: self.library.dispatch(dict(op="setting", key="rtl", value=False)),
                      lambda: self.library.trash(str(self.chapter))]
        self.library.state.mkdir()
        with patch.object(library.subprocess, "run") as trash:
            for state in invalid_states:
                original = json.dumps(state)
                self.library.progress_path.write_text(original)
                for operation in operations:
                    with self.subTest(state=state, operation=operation):
                        with self.assertRaisesRegex(ValueError, "reading.json"):
                            operation()
                        self.assertEqual(self.library.progress_path.read_text(), original)
            trash.assert_not_called()

    def test_reading_state_is_validated_after_acquiring_the_write_lock(self):
        self.library.save_progress(str(self.chapter), 1)
        original = json.dumps({"progress": {str(self.chapter): "invalid"}})
        real_flock = library.fcntl.flock

        def corrupt_before_lock(descriptor, operation):
            self.library.progress_path.write_text(original)
            return real_flock(descriptor, operation)

        with patch.object(library.fcntl, "flock", side_effect=corrupt_before_lock):
            with self.assertRaisesRegex(ValueError, "reading.json"):
                self.library.save_progress(str(self.chapter), 2)
        self.assertEqual(self.library.progress_path.read_text(), original)

    def test_invalid_download_state_is_rejected_before_queue_changes_or_trash(self):
        job = dict(id="synthetic", status="pending", root=str(self.root),
                   url="https://reader.example.test/gallery", outputs=[], files=0, error="")
        invalid = [{"jobs": value} for value in (None, {}, "invalid", [None], ["invalid"], [{}])]
        invalid += [{"jobs": [dict(job, **change)]} for change in
                    ({"id": "../../escape"}, {"status": []}, {"status": "invalid"},
                     {"root": None}, {"root": "relative"}, {"url": []}, {"url": "file:///tmp/x"},
                     {"outputs": "invalid"}, {"outputs": [None]}, {"outputs": ["relative.cbz"]},
                     {"files": -1}, {"files": True}, {"cancelled": "false"},
                     {"device": "invalid"}, {"error": {}})]
        invalid.append({"jobs": [job, dict(job)]})
        operations = [self.library.status, lambda: self.library.cancel("synthetic"),
                      lambda: self.library.add("https://reader.example.test/new"),
                      lambda: self.library.trash(str(self.chapter))]
        with patch.object(library.shutil, "which", return_value="/bin/gallery-dl"), \
                patch.object(self.library, "start_worker") as start, \
                patch.object(library.subprocess, "run") as trash:
            for value in invalid:
                library.atomic_json(self.library.queue_path, value)
                original = self.library.queue_path.read_bytes()
                for operation in operations:
                    with self.subTest(value=value, operation=operation):
                        with self.assertRaisesRegex(ValueError, "downloads.json"):
                            operation()
                        self.assertEqual(self.library.queue_path.read_bytes(), original)
            start.assert_not_called()
            trash.assert_not_called()

    def test_malformed_download_metadata_preserves_images_and_published_archives(self):
        stage = self.root / ".library-downloads" / "fixture"
        data = dict(title="Gallery", gallery_id=7, page=1)
        download_image(stage / "gallery" / "001.png", data)
        outputs = library.import_download(stage, self.root, [])
        original = Path(outputs[0]).read_bytes()
        image = download_image(stage / "gallery" / "002.png", dict(data, page=2))
        note = Path(str(image) + ".json")
        for contents in ("[]", "null", '"invalid"', "{", "[" * 1100 + "]" * 1100):
            note.write_text(contents)
            with self.subTest(contents=contents[:30]):
                with self.assertRaisesRegex(ValueError, "002.png.json"):
                    library.import_download(stage, self.root, outputs)
                self.assertEqual(Path(outputs[0]).read_bytes(), original)
                self.assertTrue(image.is_file())
                self.assertEqual(note.read_text(), contents)
        note.write_text(json.dumps(dict(data, page=2)))
        self.assertEqual(library.import_download(stage, self.root, outputs), outputs)
        self.assertFalse(image.exists())

    def test_helper_survives_invalid_nested_state_and_accepts_an_independent_command(self):
        cases = [
            (self.library.progress_path, {"progress": {str(self.chapter): "invalid"}},
             [dict(id=1, op="scan"), dict(id=2, op="status")]),
            (self.library.queue_path, {"jobs": [None]},
             [dict(id=1, op="status"), dict(id=2, op="scan")]),
        ]
        for path, state, requests in cases:
            with self.subTest(path=path):
                library.atomic_json(path, state)
                original = path.read_bytes()
                result = subprocess.run([sys.executable, "-B", str(REPO / "scripts/library.py"),
                    "--root", str(self.root), "--state", str(self.library.state),
                    "--cache", str(self.library.cache), "serve"],
                    input="".join(json.dumps(request) + "\n" for request in requests),
                    capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                replies = [json.loads(line) for line in result.stdout.splitlines()]
                self.assertFalse(replies[1]["ok"])
                self.assertIn(path.name, replies[1]["error"])
                self.assertTrue(replies[2]["ok"])
                self.assertEqual(replies[2]["reply"], 2)
                self.assertEqual(result.stderr, "")
                self.assertEqual(path.read_bytes(), original)
                path.unlink()

    def test_invalid_cached_metadata_is_rebuilt_without_hiding_books(self):
        details = self.library.details(self.chapter)
        note = self.library.cache / "metadata" / (details["key"] + ".json")
        original = self.chapter.read_bytes()
        for value in ([], {}, dict(details, pages=[]), dict(details, pages=0),
                      dict(details, key="wrong-archive"),
                      dict(details, meta=None), dict(details, meta=dict(details["meta"], tags="quiet"))):
            with self.subTest(value=value):
                library.atomic_json(note, value)
                result = self.library.scan()
                self.assertEqual(len(result["books"]), 1)
                self.assertEqual(result["warnings"], [])
                self.assertEqual(library.load_json(note, None), details)
                self.assertEqual(len(self.library.open_archive(str(self.chapter))["pages"]), 3)
                self.assertEqual(self.chapter.read_bytes(), original)
        for contents in (b"{", b"\xff"):
            note.write_bytes(contents)
            self.assertEqual(self.library.details(self.chapter), details)
            self.assertEqual(library.load_json(note, None), details)

    def test_invalid_cached_page_lists_are_rebuilt(self):
        opened = self.library.open_archive(str(self.chapter))
        listing = Path(opened["pages"][0]).parent / "pages.json"
        outside = self.base / "outside.png"
        outside.write_bytes(b"keep this file")
        for value in ({}, [], [None] * 3, [str(outside)] * 3,
                      [opened["pages"][0]] * 3, list(reversed(opened["pages"]))):
            with self.subTest(value=value):
                library.atomic_json(listing, value)
                self.assertEqual(self.library.open_archive(str(self.chapter)), opened)
                self.assertEqual(library.load_json(listing, None), opened["pages"])
                self.assertEqual(outside.read_bytes(), b"keep this file")
        for contents in (b"{", b"\xff", None):
            if contents is None:
                listing.unlink()
            else:
                listing.write_bytes(contents)
            self.assertEqual(self.library.open_archive(str(self.chapter)), opened)
            self.assertEqual(library.load_json(listing, None), opened["pages"])

    def test_missing_or_empty_cached_pages_are_restored_without_losing_progress(self):
        self.library.save_progress(str(self.chapter), 1)
        original = self.chapter.read_bytes()
        opened = self.library.open_archive(str(self.chapter))
        page = Path(opened["pages"][1])
        outside = self.base / "outside.png"
        outside.write_bytes(b"keep this file")
        for damage in ("missing", "empty", "folder", "symlink"):
            with self.subTest(damage=damage):
                if page.is_dir() and not page.is_symlink():
                    page.rmdir()
                else:
                    page.unlink(missing_ok=True)
                if damage == "empty":
                    page.touch()
                elif damage == "folder":
                    page.mkdir()
                elif damage == "symlink":
                    page.symlink_to(outside)
                self.assertEqual(self.library.open_archive(str(self.chapter)), opened)
                self.assertEqual(page.read_bytes(), image_bytes())
                self.assertFalse(page.is_symlink())
                self.assertEqual(self.chapter.read_bytes(), original)
                self.assertEqual(library.reading_state(self.library.progress_path)["progress"][str(self.chapter)]["page"], 1)
        self.assertEqual(outside.read_bytes(), b"keep this file")

    def test_valid_caches_do_not_reopen_archives(self):
        details = self.library.details(self.chapter)
        opened = self.library.open_archive(str(self.chapter))
        with patch.object(library, "members", side_effect=AssertionError("Rebuilt valid metadata")), \
                patch.object(library.zipfile, "ZipFile", side_effect=AssertionError("Re-extracted valid pages")):
            self.assertEqual(self.library.details(self.chapter), details)
            self.assertEqual(self.library.open_archive(str(self.chapter)), opened)

    def test_opening_corrects_a_cached_page_count_which_disagrees_with_the_archive(self):
        details = self.library.details(self.chapter)
        opened = self.library.open_archive(str(self.chapter))
        note = self.library.cache / "metadata" / (details["key"] + ".json")
        library.atomic_json(note, dict(details, pages=4))
        self.assertEqual(self.library.open_archive(str(self.chapter)), opened)
        self.assertEqual(library.load_json(note, None), details)
        with patch.object(library.zipfile, "ZipFile", side_effect=AssertionError("Re-extracted repaired pages")):
            self.assertEqual(self.library.open_archive(str(self.chapter)), opened)

    def test_failed_metadata_rebuild_reports_the_archive_error_and_preserves_old_cache(self):
        details = self.library.details(self.chapter)
        note = self.library.cache / "metadata" / (details["key"] + ".json")
        note.write_text("{")
        with patch.object(library, "members", side_effect=ValueError("Unreadable source archive")):
            with self.assertRaisesRegex(ValueError, "Unreadable source archive"):
                self.library.details(self.chapter)
        self.assertEqual(note.read_text(), "{")
        self.assertEqual(self.library.details(self.chapter), details)

    def test_failed_page_rebuild_keeps_old_cache_and_allows_retry(self):
        opened = self.library.open_archive(str(self.chapter))
        destination = Path(opened["pages"][0]).parent
        Path(opened["pages"][0]).unlink()
        original = {path.name: path.read_bytes() for path in destination.iterdir()}
        for constant, limit, message in (("MAX_ENTRY_BYTES", 1, "page limit"),
                                         ("MAX_CHAPTER_BYTES", len(image_bytes()), "cache limit")):
            with self.subTest(constant=constant), patch.object(library, constant, limit):
                with self.assertRaisesRegex(ValueError, message):
                    self.library.open_archive(str(self.chapter))
                self.assertEqual({path.name: path.read_bytes() for path in destination.iterdir()}, original)
                self.assertEqual(list(destination.parent.iterdir()), [destination])
        real_rename = Path.rename

        def fail_publish(source, target):
            if source.name == "new" and target == destination:
                raise OSError("Synthetic publication failure")
            return real_rename(source, target)

        with patch.object(Path, "rename", fail_publish):
            with self.assertRaisesRegex(OSError, "Synthetic publication failure"):
                self.library.open_archive(str(self.chapter))
        self.assertEqual({path.name: path.read_bytes() for path in destination.iterdir()}, original)
        self.assertEqual(list(destination.parent.iterdir()), [destination])
        self.assertEqual(self.library.open_archive(str(self.chapter)), opened)
        self.assertTrue(all(Path(page).read_bytes() == image_bytes() for page in opened["pages"]))

    def test_cache_repairs_do_not_follow_links_to_other_files_or_folders(self):
        opened = self.library.open_archive(str(self.chapter))
        destination = Path(opened["pages"][0]).parent
        outside = self.base / "outside-cache"
        destination.rename(outside)
        original = {path.name: path.read_bytes() for path in outside.iterdir()}
        destination.symlink_to(outside, target_is_directory=True)
        self.assertEqual(self.library.open_archive(str(self.chapter)), opened)
        self.assertFalse(destination.is_symlink())
        self.assertEqual({path.name: path.read_bytes() for path in outside.iterdir()}, original)
        listing = destination / "pages.json"
        listing.unlink()
        outside_json = self.base / "outside.json"
        outside_json.write_text("keep this file")
        listing.symlink_to(outside_json)
        self.assertEqual(self.library.open_archive(str(self.chapter)), opened)
        self.assertFalse(listing.is_symlink())
        self.assertEqual(outside_json.read_text(), "keep this file")

    def test_two_helpers_share_one_page_cache_rebuild(self):
        opened = self.library.open_archive(str(self.chapter))
        Path(opened["pages"][0]).unlink()
        second = library.Library(self.root, self.library.state, self.library.cache)
        extracting, waiting, release = threading.Event(), threading.Event(), threading.Event()
        real_copy, real_flock = library.shutil.copyfileobj, library.fcntl.flock
        results, failures, copies = [], [], []

        def copy(source, target):
            copies.append(target.name)
            if len(copies) == 1:
                extracting.set()
                if not release.wait(3):
                    raise AssertionError("Second helper did not reach the cache lock")
            return real_copy(source, target)

        def flock(descriptor, operation):
            if threading.current_thread().name == "second-helper":
                waiting.set()
            return real_flock(descriptor, operation)

        def open_book(backend):
            try:
                results.append(backend.open_archive(str(self.chapter)))
            except Exception as error:
                failures.append(error)

        first_thread = threading.Thread(target=open_book, args=(self.library,), name="first-helper", daemon=True)
        second_thread = threading.Thread(target=open_book, args=(second,), name="second-helper", daemon=True)
        with patch.object(library.shutil, "copyfileobj", side_effect=copy), \
                patch.object(library.fcntl, "flock", side_effect=flock):
            try:
                first_thread.start()
                self.assertTrue(extracting.wait(3), "First helper did not start extracting")
                second_thread.start()
                self.assertTrue(waiting.wait(3), "Second helper did not reach the cache lock")
            finally:
                release.set()
                first_thread.join(5)
                if second_thread.ident is not None:
                    second_thread.join(5)
        self.assertFalse(first_thread.is_alive())
        self.assertFalse(second_thread.is_alive())
        self.assertEqual(failures, [])
        self.assertEqual(results, [opened, opened])
        self.assertEqual(len(copies), 3)
        self.assertTrue(all(Path(page).read_bytes() == image_bytes() for page in opened["pages"]))

    def test_sparse_reading_state_preserves_unknown_fields_and_clamps_stale_pages(self):
        state = dict(progress={str(self.chapter): dict(page=9999)},
                     settings=dict(rtl=False, fit="width", sort="name", extra="keep"), extra="keep")
        library.atomic_json(self.library.progress_path, state)
        self.assertEqual(self.library.open_archive(str(self.chapter))["page"], 2)
        self.assertEqual(self.library.scan()["books"][0]["chapters"][0]["page"], 2)
        self.library.save_progress(str(self.chapter), 1)
        saved = library.reading_state(self.library.progress_path)
        self.assertEqual(saved["settings"], state["settings"])
        self.assertEqual(saved["extra"], "keep")
        self.assertFalse(saved["progress"][str(self.chapter)]["done"])

    def test_nested_tag_dictionaries_are_available_as_filters(self):
        result = library.metadata(dict(tags={"general": ["quiet"], "artist": ["example artist"]}))
        self.assertIn("quiet", result["tags"])
        self.assertIn("example artist", result["tags"])
        nested = "quiet"
        for _ in range(800):
            nested = {"general": [nested]}
        self.assertEqual(library.metadata(dict(tags=nested))["tags"], ["quiet"])

    def test_status_recovers_abandoned_pending_and_running_jobs(self):
        library.atomic_json(self.library.queue_path, {"jobs": [
            queued_job(self.root, status, status)
            for status in ("pending", "running", "completed", "cancelled")
        ]})
        result = self.library.status()
        self.assertEqual([job["status"] for job in result["jobs"]],
                         ["failed", "failed", "completed", "cancelled"])
        self.assertTrue(all("worker stopped" in job["error"] for job in result["jobs"][:2]))

    def test_retry_of_an_abandoned_pending_url_does_not_require_a_prior_status_request(self):
        url = "https://reader.example.test/series"
        with patch.object(library.shutil, "which", return_value="/bin/gallery-dl"), \
                patch.object(self.library, "start_worker") as start:
            self.library.add(url)
            result = self.library.add(url)
        self.assertEqual(start.call_count, 2)
        self.assertEqual(len(result["jobs"]), 1)
        self.assertEqual(result["jobs"][0]["status"], "pending")

    def test_status_keeps_jobs_owned_by_a_live_worker_and_add_does_not_spawn_another(self):
        library.atomic_json(self.library.queue_path, {"jobs": [
            queued_job(self.root, "running", "running"),
            queued_job(self.root, "pending", "pending"),
        ]})
        with (self.library.state / "worker.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch.object(library.shutil, "which", return_value="/bin/gallery-dl"), \
                    patch.object(self.library, "start_worker") as start:
                result = self.library.add("https://reader.example.test/new")
            start.assert_not_called()
            self.assertEqual([job["status"] for job in result["jobs"]], ["running", "pending", "pending"])

    def test_worker_lock_is_inherited_before_the_worker_finishes_starting(self):
        real_popen = subprocess.Popen
        processes = []

        def slow_worker(command, **kwargs):
            process = real_popen([sys.executable, "-c", "import time; time.sleep(2)"], **kwargs)
            processes.append(process)
            return process

        try:
            with patch.object(library.shutil, "which", return_value="/bin/gallery-dl"), \
                    patch.object(library.subprocess, "Popen", side_effect=slow_worker):
                self.library.add("https://reader.example.test/series")
            self.assertEqual(self.library.status()["jobs"][0]["status"], "pending")
            with (self.library.state / "worker.lock").open("a") as lock:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            processes[0].terminate()
            processes[0].wait(timeout=5)
            self.assertEqual(self.library.status()["jobs"][0]["status"], "failed")
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.wait()

    def test_add_starts_a_replacement_when_the_previous_worker_finishes_before_enqueue(self):
        library.atomic_json(self.library.queue_path, {"jobs": []})
        reached_queue = threading.Event()
        real_changing = library.changing
        failures, results = [], []

        @contextmanager
        def changing(path, **kwargs):
            if path == self.library.queue_path:
                reached_queue.set()
            with real_changing(path, **kwargs) as value:
                yield value

        def enqueue():
            try:
                results.append(self.library.add("https://reader.example.test/new"))
            except Exception as error:
                failures.append(error)

        with (self.library.state / "worker.lock").open("a") as worker_lock, \
                self.library.queue_path.with_suffix(".lock").open("a") as queue_lock:
            fcntl.flock(worker_lock, fcntl.LOCK_EX)
            fcntl.flock(queue_lock, fcntl.LOCK_EX)
            thread = threading.Thread(target=enqueue, daemon=True)
            try:
                with patch.object(library.shutil, "which", return_value="/bin/gallery-dl"), \
                        patch.object(self.library, "start_worker") as start, \
                        patch.object(library, "changing", side_effect=changing):
                    thread.start()
                    self.assertTrue(reached_queue.wait(2), "add did not reach the queue lock")
                    fcntl.flock(worker_lock, fcntl.LOCK_UN)
                    fcntl.flock(queue_lock, fcntl.LOCK_UN)
                    thread.join(3)
                    self.assertFalse(thread.is_alive())
                    self.assertEqual(failures, [])
                    start.assert_called_once()
                    self.assertEqual(results[0]["jobs"][0]["status"], "pending")
            finally:
                fcntl.flock(worker_lock, fcntl.LOCK_UN)
                fcntl.flock(queue_lock, fcntl.LOCK_UN)
                thread.join(3)

    def test_downloader_does_not_exec_without_parent_death_protection(self):
        for mode in ("prctl-error", "parent-gone"):
            with self.subTest(mode=mode), patch.object(ctypes, "CDLL") as load_libc, \
                    patch.object(ctypes, "get_errno", return_value=1), \
                    patch.object(library.os, "getppid", return_value=1), \
                    patch.object(library.os, "execvp") as execute:
                load_libc.return_value.prctl.return_value = -1 if mode == "prctl-error" else 0
                with self.assertRaises(OSError):
                    library.exec_download(self.library, "synthetic", 1234)
                execute.assert_not_called()

    def test_cancel_and_queue_errors_kill_a_downloader_which_ignores_term(self):
        real_popen, real_document = subprocess.Popen, library.document
        for mode in ("cancel", "error", "missing"):
            with self.subTest(mode=mode):
                marker = self.base / (mode + ".pid")
                program = ("import os,signal,time\nfrom pathlib import Path\n"
                           "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
                           f"Path({str(marker)!r}).write_text(str(os.getpid()))\n"
                           "time.sleep(30)\n")
                processes = []

                def launch(command, **kwargs):
                    process = real_popen([sys.executable, "-c", program], **kwargs)
                    processes.append(process)
                    return process

                def queue_status(path):
                    if path == self.library.queue_path:
                        wait_for_pid(marker)
                        if mode == "error":
                            raise ValueError("Synthetic queue failure")
                        if mode == "missing":
                            return {"jobs": []}
                        return {"jobs": [queued_job(self.root, status="running", cancelled=True)]}
                    return real_document(path)

                job = dict(id="synthetic", root=str(self.root), url="https://reader.example.test/gallery", outputs=[])
                staged = download_image(self.root / ".library-downloads" / "synthetic" / "001.png", {})
                try:
                    with patch.object(library.subprocess, "Popen", side_effect=launch), \
                            patch.object(library, "document", side_effect=queue_status), \
                            patch.object(library, "DOWNLOAD_STOP_TIMEOUT", 0.1):
                        if mode in ("error", "missing"):
                            message = "Synthetic queue failure" if mode == "error" else "job disappeared"
                            with self.assertRaisesRegex(ValueError, message):
                                library.run_download(self.library, job)
                        else:
                            self.assertEqual(library.run_download(self.library, job)["status"], "cancelled")
                    self.assertEqual(processes[0].returncode, -signal.SIGKILL)
                    self.assertTrue(staged.exists())
                    self.assertEqual(list(self.root.glob("*.cbz")), [])
                finally:
                    for process in processes:
                        if process.poll() is None:
                            process.kill()
                            process.wait()

    def test_cleanup_kills_descendants_even_when_the_leader_exits_on_term(self):
        marker = self.base / "descendant.pid"
        program = ("import os,signal,time\nfrom pathlib import Path\n"
                   "child = os.fork()\nif child == 0:\n"
                   "    signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
                   f"    Path({str(marker)!r}).write_text(str(os.getpid()))\n"
                   "time.sleep(30)\n")
        process = subprocess.Popen([sys.executable, "-c", program], start_new_session=True,
                                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            with process_handle(wait_for_pid(marker)) as descendant:
                with patch.object(library, "DOWNLOAD_STOP_TIMEOUT", 0.1):
                    library.stop_download(process)
                self.assertEqual(process.returncode, -signal.SIGTERM)
                self.assertTrue(select.select([descendant], [], [], 3)[0], "descendant survived cleanup")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    def test_import_rejects_a_destination_symlink_outside_library(self):
        stage = self.root / ".library-downloads" / "fixture" / "gallery"
        stage.mkdir(parents=True)
        (stage / "1.png").write_bytes(image_bytes())
        identity = library.import_identity({}, Path("gallery"), str(stage.parent.absolute()))
        target = self.root / ("gallery [" + library.digest(library.identity_key(identity)) + "].cbz")
        outside = self.base / "outside.cbz"
        archive(outside)
        before = outside.read_bytes()
        target.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "outside"):
            library.import_download(stage.parent, self.root, [])
        self.assertEqual(outside.read_bytes(), before)

    def test_import_does_not_follow_or_remove_a_planted_temporary_symlink(self):
        stage = self.root / ".library-downloads" / "fixture"
        data = dict(title="Gallery", gallery_id=7, page=1)
        download_image(stage / "gallery" / "001.png", data)
        outputs = library.import_download(stage, self.root, [])
        outside = self.base / "outside.txt"
        outside.write_bytes(b"keep this file")
        planted = Path(outputs[0]).with_suffix(".cbz.part")
        planted.symlink_to(outside)
        download_image(stage / "gallery" / "002.png", dict(data, page=2))
        self.assertEqual(library.import_download(stage, self.root, outputs), outputs)
        self.assertEqual(outside.read_bytes(), b"keep this file")
        self.assertTrue(planted.is_symlink())
        self.assertEqual(len(library.read_import_record(outputs[0])["pages"]), 2)

    def test_failed_archive_write_preserves_the_book_and_cleans_its_own_temporary_file(self):
        stage = self.root / ".library-downloads" / "fixture"
        data = dict(title="Gallery", gallery_id=7, page=1)
        download_image(stage / "gallery" / "001.png", data)
        outputs = library.import_download(stage, self.root, [])
        before = Path(outputs[0]).read_bytes()
        image = download_image(stage / "gallery" / "002.png", dict(data, page=2))
        planted = Path(outputs[0]).with_suffix(".cbz.part")
        planted.write_bytes(b"pre-existing partial file")
        with patch.object(library.zipfile.ZipFile, "write", side_effect=OSError("synthetic write failure")):
            with self.assertRaisesRegex(OSError, "synthetic write failure"):
                library.import_download(stage, self.root, outputs)
        self.assertEqual(Path(outputs[0]).read_bytes(), before)
        self.assertTrue(image.exists())
        self.assertEqual(planted.read_bytes(), b"pre-existing partial file")
        self.assertEqual(list(self.root.glob(".*.part")), [])

    def test_import_rejects_links_special_files_and_external_staging_folders(self):
        outside = self.base / "outside"
        image = download_image(outside / "001.png", dict(title="Outside"))
        before = image.read_bytes()
        for kind in ("external", "parent", "job", "nested", "image", "metadata", "hardlink", "fifo"):
            with self.subTest(kind=kind):
                root = self.root / kind
                root.mkdir()
                work = root / ".library-downloads"
                stage = work / "fixture"
                if kind == "external":
                    stage = outside
                elif kind == "parent":
                    work.symlink_to(outside, target_is_directory=True)
                elif kind == "job":
                    work.mkdir()
                    stage.symlink_to(outside, target_is_directory=True)
                else:
                    stage.mkdir(parents=True)
                    if kind == "nested":
                        (stage / "gallery").symlink_to(outside, target_is_directory=True)
                    elif kind == "image":
                        (stage / "001.png").symlink_to(image)
                    elif kind == "hardlink":
                        os.link(image, stage / "001.png")
                    elif kind == "fifo":
                        os.mkfifo(stage / "001.png")
                    else:
                        (stage / "001.png").write_bytes(image_bytes())
                        (stage / "001.png.json").symlink_to(outside / "001.png.json")
                with self.assertRaisesRegex(ValueError, "outside|symbolic link|hard link|regular file"):
                    library.import_download(stage, root, [])
                self.assertEqual(image.read_bytes(), before)
                self.assertEqual(list(root.glob("*.cbz")), [])

    def test_unsafe_staging_is_rejected_before_starting_gallery_dl(self):
        outside = self.base / "outside"
        image = download_image(outside / "001.png", dict(title="Outside"))
        before = image.read_bytes()
        for kind in ("parent", "job", "nested", "image", "metadata", "partial", "hardlink", "fifo"):
            with self.subTest(kind=kind):
                root = self.root / kind
                root.mkdir()
                work = root / ".library-downloads"
                stage = work / "fixture"
                if kind == "parent":
                    work.symlink_to(outside, target_is_directory=True)
                elif kind == "job":
                    work.mkdir()
                    stage.symlink_to(outside, target_is_directory=True)
                else:
                    stage.mkdir(parents=True)
                    filename = {"nested": "gallery", "image": "001.png",
                                "metadata": "001.png.json", "partial": "001.png.part",
                                "hardlink": "001.png.part", "fifo": "001.png"}[kind]
                    if kind == "hardlink":
                        os.link(image, stage / filename)
                    elif kind == "fifo":
                        os.mkfifo(stage / filename)
                    else:
                        (stage / filename).symlink_to(outside if kind == "nested" else image)
                with patch.object(library.subprocess, "Popen", side_effect=AssertionError("Unexpected download")) as process:
                    with self.assertRaisesRegex(ValueError, "outside|symbolic link|hard link|regular file"):
                        library.run_download(self.library, dict(root=str(root), id="fixture", outputs=[],
                            url="https://reader.example.test/gallery"))
                process.assert_not_called()
                self.assertEqual(image.read_bytes(), before)

    def test_import_allows_a_configured_library_root_that_is_a_symlink(self):
        root = self.base / "linked-books"
        root.symlink_to(self.root, target_is_directory=True)
        stage = root / ".library-downloads" / "fixture"
        download_image(stage / "gallery" / "001.png", dict(title="Gallery", gallery_id=7, page=1))
        outputs = library.import_download(stage, root, [])
        download_image(stage / "gallery" / "002.png", dict(title="Gallery", gallery_id=7, page=2))
        self.assertEqual(library.import_download(stage, root, outputs), outputs)
        self.assertEqual(len(library.read_import_record(outputs[0])["pages"]), 2)

    def test_retry_rejects_a_series_folder_replaced_by_a_symlink_within_the_library(self):
        stage = self.root / ".library-downloads" / "fixture"
        data = dict(manga="Series", manga_id=7, chapter=1, page=1)
        download_image(stage / "c001" / "001.png", data)
        outputs = library.import_download(stage, self.root, [])
        folder = Path(outputs[0]).parent
        relocated = self.root / "Relocated"
        folder.rename(relocated)
        folder.symlink_to(relocated, target_is_directory=True)
        before = Path(outputs[0]).read_bytes()
        image = download_image(stage / "c001" / "002.png", dict(data, page=2))
        with self.assertRaisesRegex(ValueError, "symbolic link"):
            library.import_download(stage, self.root, outputs)
        self.assertEqual(Path(outputs[0]).read_bytes(), before)
        self.assertTrue(image.exists())

    def test_failed_trash_preserves_progress_and_reports_error(self):
        self.library.save_progress(str(self.chapter), 1)
        with patch.object(library.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "read-only")):
            with self.assertRaisesRegex(ValueError, "read-only"):
                self.library.trash(str(self.chapter))
        self.assertEqual(self.library.open_archive(str(self.chapter))["page"], 1)

    def test_successful_trash_clears_only_selected_progress_and_own_download_records(self):
        other = self.root / "Other book.cbz"
        archive(other)
        self.library.save_progress(str(self.chapter), 1)
        self.library.save_progress(str(other), 2)
        library.atomic_json(self.library.queue_path, {"jobs": [
            queued_job(self.root, status="completed", outputs=[str(self.chapter)]),
        ]})
        own_record = self.library.state / "archives" / "synthetic.sqlite3"
        own_record.parent.mkdir()
        own_record.write_text("synthetic download record")
        def trash(command, **kwargs):
            self.assertEqual(command, ["gio", "trash", "--", str(self.chapter)])
            self.chapter.rename(self.base / "trashed.cbz")
            return subprocess.CompletedProcess(command, 0, "", "")
        with patch.object(library.subprocess, "run", side_effect=trash):
            self.library.trash(str(self.chapter))
        marks = library.document(self.library.progress_path)["progress"]
        self.assertNotIn(str(self.chapter), marks)
        self.assertEqual(marks[str(other)]["page"], 2)
        self.assertFalse(own_record.exists())

    def test_trash_blocks_a_known_active_download_without_moving_files(self):
        library.atomic_json(self.library.queue_path, {"jobs": [
            queued_job(self.root, status="running", outputs=[str(self.chapter)]),
        ]})
        with self.assertRaisesRegex(ValueError, "Cancel"):
            self.library.trash(str(self.chapter))
        self.assertTrue(self.chapter.is_file())

    def test_import_groups_manga_and_fallback_galleries_and_merges_new_pages(self):
        stage = self.root / ".library-downloads" / "fixture"
        chapter = stage / "synthetic" / "Series" / "c0002 Title"
        gallery = stage / "synthetic" / "Gallery"
        for directory, data in [(chapter, dict(category="synthetic", manga="Series", chapter=2)),
                                (gallery, dict(category="synthetic", title="Gallery title", tags=["quiet"]))]:
            directory.mkdir(parents=True)
            (directory / "001.png").write_bytes(image_bytes())
            (directory / "001.png.json").write_text(json.dumps(data))
        outputs = library.import_download(stage, self.root, [])
        self.assertEqual(len(outputs), 2)
        self.assertTrue(all(Path(path).is_file() for path in outputs))
        self.assertFalse((chapter / "001.png").exists())
        (chapter / "002.png").write_bytes(image_bytes())
        (chapter / "002.png.json").write_text(json.dumps(dict(category="synthetic", manga="Series", chapter=2)))
        self.assertEqual(library.import_download(stage, self.root, outputs), outputs)
        series = next(book for book in self.library.scan()["books"] if book["name"].startswith("Series"))
        self.assertEqual(series["chapters"][0]["pages"], 2)
        gallery_book = next(book for book in self.library.scan()["books"] if book["name"] == "Gallery title")
        self.assertEqual(gallery_book["meta"]["tags"], ["quiet"])

    def test_long_unicode_gallery_titles_import_with_complete_characters_and_identity_suffixes(self):
        stage = self.root / ".library-downloads" / "fixture"
        cases = [("A" * 200, "A" * 150), ("漫" * 200, "漫" * 50),
                 ("🌙" * 200, "🌙" * 37), ("é" * 200, "é" * 75),
                 ("A" + "漫" * 200, "A" + "漫" * 49)]
        for index, (title, prefix) in enumerate(cases):
            with self.subTest(title=title[:10]):
                image = download_image(stage / "gallery" / "001.png",
                    dict(title=title, gallery_id=index, page=1))
                outputs = library.import_download(stage, self.root, [])
                self.assertEqual(len(outputs), 1)
                target = Path(outputs[0])
                self.assertTrue(target.name.startswith(prefix + " ["), target.name)
                self.assertRegex(target.name, r" \[[0-9a-f]{20}\]\.cbz$")
                self.assertLessEqual(len(os.fsencode(target.name)), os.pathconf(self.root, "PC_NAME_MAX"))
                with zipfile.ZipFile(target) as result:
                    self.assertEqual(json.loads(result.read("info.json"))["title"], title)
                    self.assertEqual(result.read("001.png"), image_bytes())
                self.assertFalse(image.exists())
        self.assertEqual(len(list(self.root.glob("*.cbz"))), len(cases))

    def test_long_unicode_series_and_chapter_names_fit_the_filesystem_limit(self):
        stage = self.root / ".library-downloads" / "fixture"
        # This staging folder fits a 255-byte component; the import suffix would
        # exceed that limit without shortening the chapter name in bytes.
        directory = stage / ("章" * 85)
        download_image(directory / "001.png", dict(manga="漫" * 200, manga_id=7, chapter=1, page=1))
        outputs = library.import_download(stage, self.root, [])
        self.assertEqual(len(outputs), 1)
        target = Path(outputs[0])
        self.assertTrue(target.parent.name.startswith("漫" * 50 + " ["), target.parent.name)
        self.assertTrue(target.name.startswith("章" * 50 + " ["), target.name)
        self.assertRegex(target.parent.name, r" \[[0-9a-f]{20}\]$")
        self.assertRegex(target.name, r" \[[0-9a-f]{20}\]\.cbz$")
        for part in (target.parent.name, target.name):
            self.assertLessEqual(len(os.fsencode(part)), os.pathconf(self.root, "PC_NAME_MAX"))
        self.assertEqual(len(self.library.open_archive(str(target))["pages"]), 1)

    def test_retry_keeps_existing_unicode_paths_longer_than_the_new_title_limit(self):
        stage = self.root / ".library-downloads" / "fixture"
        source = "https://reader.example.test/gallery"
        data = dict(title="漫" * 70, gallery_id=7, page=1)
        download_image(stage / "gallery" / "001.png", data, "blue")
        outputs = library.import_download(stage, self.root, [], source=source)
        target = Path(outputs[0])
        suffix = target.name[target.name.index(" ["):]
        legacy = target.with_name(data["title"] + suffix)
        target.rename(legacy)
        before = legacy.read_bytes()
        image = download_image(stage / "gallery" / "002.png", dict(data, page=2), "red")
        retried = library.import_download(stage, self.root, [str(legacy)], source=source)
        self.assertEqual(retried, [str(legacy)])
        self.assertNotEqual(legacy.read_bytes(), before)
        with zipfile.ZipFile(legacy) as result:
            self.assertEqual(result.read("001.png"), image_bytes("blue"))
            self.assertEqual(result.read("002.png"), image_bytes("red"))
        self.assertFalse(image.exists())

    def test_same_titles_and_page_names_from_different_sources_stay_separate(self):
        for index, fields in enumerate(({}, {"gallery_id": 7})):
            with self.subTest(fields=fields):
                first = self.root / ".library-downloads" / f"first-{index}" / "synthetic" / "gallery"
                second = self.root / ".library-downloads" / f"second-{index}" / "synthetic" / "gallery"
                data = dict(title="Same title", category="synthetic", page=1, **fields)
                download_image(first / "001.png", data, "blue")
                download_image(second / "001.png", data, "red")
                original = library.import_download(first.parent.parent, self.root, [],
                    source="https://reader.example.test/first")
                before = Path(original[0]).read_bytes()
                other = library.import_download(second.parent.parent, self.root, [],
                    source="https://reader.example.test/second")
                self.assertNotEqual(original, other)
                self.assertEqual(Path(original[0]).read_bytes(), before)
                with zipfile.ZipFile(other[0]) as result:
                    self.assertEqual(result.read("001.png"), image_bytes("red"))

    def test_one_source_can_contain_distinct_galleries_in_the_same_directory(self):
        stage = self.root / ".library-downloads" / "fixture"
        gallery = stage / "synthetic" / "gallery"
        for gallery_id, filename, color in [(1, "001.png", "blue"), (2, "002.png", "red")]:
            download_image(gallery / filename,
                dict(title="Same title", category="synthetic", gallery_id=gallery_id, page=1), color)
        outputs = library.import_download(stage, self.root, [], source="https://reader.example.test/collection")
        self.assertEqual(len(outputs), 2)
        records = [library.read_import_record(path) for path in outputs]
        self.assertEqual({record["identity"]["book"][1] for record in records}, {1, 2})
        self.assertTrue(all(len(record["pages"]) == 1 for record in records))

    def test_identically_named_series_with_different_ids_have_separate_folders(self):
        stage = self.root / ".library-downloads" / "fixture"
        for series_id in (1, 2):
            download_image(stage / "synthetic" / "same series" / f"00{series_id}.png",
                dict(category="synthetic", manga="Same series", manga_id=series_id,
                     chapter=1, chapter_id=series_id * 100, page=1))
        outputs = library.import_download(stage, self.root, [], source="https://reader.example.test/collection")
        self.assertEqual(len(outputs), 2)
        self.assertEqual(len({Path(path).parent for path in outputs}), 2)

    def test_chapter_variants_stay_separate_within_one_series(self):
        stage = self.root / ".library-downloads" / "fixture"
        for language in ("en", "ja"):
            download_image(stage / language / "001.png",
                dict(category="synthetic", manga="Series", manga_id=7,
                     chapter=1, chapter_id=100, lang=language, page=1))
        outputs = library.import_download(stage, self.root, [], source="https://reader.example.test/series")
        self.assertEqual(len(outputs), 2)
        self.assertEqual(len({Path(path).parent for path in outputs}), 1)

    def test_retry_preserves_identity_when_title_or_page_filename_changes(self):
        stage = self.root / ".library-downloads" / "fixture"
        gallery = stage / "synthetic" / "gallery"
        source = "https://reader.example.test/gallery"
        download_image(gallery / "001.png", dict(title="Old title", gallery_id=7, page=1), "blue")
        outputs = library.import_download(stage, self.root, [], source=source)
        download_image(gallery / "002.png", dict(title="New title", gallery_id=7, page=1), "red")
        self.assertEqual(library.import_download(stage, self.root, outputs, source=source), outputs)
        with zipfile.ZipFile(outputs[0]) as result:
            self.assertEqual(library.page_names(result.namelist()), ["002.png"])
            self.assertEqual(result.read("002.png"), image_bytes("red"))
        download_image(gallery / "003.png", dict(title="New title", gallery_id=7, page=2))
        self.assertEqual(library.import_download(stage, self.root, outputs, source=source), outputs)
        self.assertEqual(len(library.read_import_record(outputs[0])["pages"]), 2)

    def test_new_chapters_keep_the_series_folder_after_a_title_change(self):
        stage = self.root / ".library-downloads" / "fixture"
        source = "https://reader.example.test/series"
        download_image(stage / "old" / "c001" / "001.png",
            dict(category="synthetic", manga="Old title", manga_id=7, chapter=1, page=1))
        first = library.import_download(stage, self.root, [], source=source)
        download_image(stage / "new" / "c002" / "001.png",
            dict(category="synthetic", manga="New title", manga_id=7, chapter=2, page=1))
        outputs = library.import_download(stage, self.root, first, source=source)
        self.assertEqual(len(outputs), 2)
        self.assertEqual({Path(path).parent for path in outputs}, {Path(first[0]).parent})

    def test_same_filename_cannot_replace_a_different_identified_page(self):
        stage = self.root / ".library-downloads" / "fixture"
        gallery = stage / "synthetic" / "gallery"
        source = "https://reader.example.test/gallery"
        download_image(gallery / "001.png", dict(title="Gallery", gallery_id=7, page=1))
        outputs = library.import_download(stage, self.root, [], source=source)
        before = Path(outputs[0]).read_bytes()
        image = download_image(gallery / "001.png", dict(title="Gallery", gallery_id=7, page=2), "red")
        with self.assertRaisesRegex(ValueError, "Page identity conflict"):
            library.import_download(stage, self.root, outputs, source=source)
        self.assertEqual(Path(outputs[0]).read_bytes(), before)
        self.assertTrue(image.exists())

    def test_mismatched_archive_ownership_is_rejected_before_replacing_it(self):
        stage = self.root / ".library-downloads" / "fixture"
        gallery = stage / "synthetic" / "gallery"
        source = "https://reader.example.test/gallery"
        download_image(gallery / "001.png", dict(title="Gallery", gallery_id=7, page=1))
        first = library.import_download(stage, self.root, [], source=source)
        download_image(gallery / "001.png", dict(title="Gallery", gallery_id=8, page=1), "red")
        second = library.import_download(stage, self.root, [], source=source)
        shutil.copyfile(second[0], first[0])
        before = Path(first[0]).read_bytes()
        image = download_image(gallery / "002.png", dict(title="Gallery", gallery_id=7, page=2))
        with self.assertRaisesRegex(ValueError, "Import identity conflict"):
            library.import_download(stage, self.root, [], source=source)
        self.assertEqual(Path(first[0]).read_bytes(), before)
        self.assertTrue(image.exists())

    def test_untracked_existing_downloads_are_not_automatically_adopted(self):
        stage = self.root / ".library-downloads" / "fixture"
        image = download_image(stage / "gallery" / "001.png", dict(title="Gallery", gallery_id=7))
        old = self.root / "Old download.cbz"
        archive(old)
        before = old.read_bytes()
        with self.assertRaisesRegex(ValueError, "no valid Library import identity"):
            library.import_download(stage, self.root, [str(old)], source="https://reader.example.test/gallery")
        self.assertEqual(old.read_bytes(), before)
        self.assertTrue(image.exists())
        with patch.object(library.subprocess, "Popen") as process:
            with self.assertRaisesRegex(ValueError, "no valid Library import identity"):
                library.run_download(self.library, dict(root=str(self.root), outputs=[str(old)]))
        process.assert_not_called()

    def test_invalid_download_images_never_replace_a_published_archive(self):
        stage = self.root / ".library-downloads" / "fixture" / "gallery"
        stage.mkdir(parents=True)
        (stage / "1.png").write_bytes(b"invalid image")
        with self.assertRaises(OSError):
            library.import_download(stage.parent, self.root, [])
        self.assertTrue((stage / "1.png").exists())
        self.assertEqual(list(self.root.glob("*.cbz")), [])

    def test_truncated_jpeg_rejects_fresh_imports_and_merges_and_can_be_retried(self):
        valid = image_bytes(image_format="JPEG")
        damaged = valid[:-2]  # Missing JPEG end marker: verify() accepts it, decoding fails.
        for mode in ("fresh", "merge"):
            with self.subTest(mode=mode):
                stage = self.root / ".library-downloads" / mode
                data = dict(title="Gallery", gallery_id=7, page=1)
                outputs = []
                before = None
                if mode == "merge":
                    download_image(stage / "gallery" / "001.png", data)
                    outputs = library.import_download(stage, self.root, [])
                    before = Path(outputs[0]).read_bytes()
                image = download_image(stage / "gallery" / "002.jpg", dict(data, page=2))
                image.write_bytes(damaged)
                sidecar = Path(str(image) + ".json")
                sidecar_before = sidecar.read_bytes()
                checkpoints = []
                with self.assertRaises(OSError):
                    library.import_download(stage, self.root, outputs, checkpoints.append)
                self.assertEqual(checkpoints, [])
                self.assertEqual(image.read_bytes(), damaged)
                self.assertEqual(sidecar.read_bytes(), sidecar_before)
                self.assertEqual(list(self.root.glob(".*.part")), [])
                if outputs:
                    self.assertEqual(Path(outputs[0]).read_bytes(), before)
                else:
                    self.assertEqual(list(self.root.glob("*.cbz")), [])
                image.write_bytes(valid)
                retried = library.import_download(stage, self.root, outputs)
                self.assertEqual(len(retried), 1)
                if outputs:
                    self.assertEqual(retried, outputs)
                with zipfile.ZipFile(retried[0]) as result:
                    self.assertEqual(result.read("002.jpg"), valid)
                    self.assertEqual(len(library.page_names(result.namelist())), 2 if outputs else 1)
                self.assertFalse(image.exists())
                self.assertFalse(sidecar.exists())

    def test_download_validation_keeps_png_checksum_checks(self):
        stage = self.root / ".library-downloads" / "fixture"
        image = download_image(stage / "gallery" / "001.png", dict(title="Gallery", gallery_id=7))
        damaged = bytearray(image.read_bytes())
        data_start = damaged.index(b"IDAT")
        data_length = struct.unpack(">I", damaged[data_start - 4:data_start])[0]
        checksum_start = data_start + 4 + data_length
        damaged[checksum_start] ^= 1
        image.write_bytes(damaged)
        with self.assertRaises(OSError):
            library.import_download(stage, self.root, [])
        self.assertEqual(image.read_bytes(), bytes(damaged))
        self.assertEqual(list(self.root.glob("*.cbz")), [])

    def test_import_checkpoints_published_books_before_removing_staging_files(self):
        stage = self.root / ".library-downloads" / "fixture" / "gallery"
        stage.mkdir(parents=True)
        image = stage / "1.png"
        image.write_bytes(image_bytes())
        published = []
        def interrupted(outputs):
            published.extend(outputs)
            self.assertTrue(all(Path(path).is_file() for path in outputs))
            self.assertTrue(image.is_file())
            raise InterruptedError("synthetic interruption")
        with self.assertRaises(InterruptedError):
            library.import_download(stage.parent, self.root, [], interrupted)
        self.assertEqual(len(published), 1)
        self.assertTrue(image.is_file())
        self.assertEqual(library.import_download(stage.parent, self.root, published), published)

    def test_queue_deduplicates_and_retries_without_changing_other_jobs(self):
        with patch.object(library.shutil, "which", return_value="/bin/gallery-dl"), \
                patch.object(self.library, "start_worker"), library.worker_lock(self.library):
            self.library.add("https://reader.example.test/series")
            with self.assertRaisesRegex(ValueError, "already"):
                self.library.add("https://reader.example.test/series")
            job = self.library.status()["jobs"][0]
            self.library.cancel(job["id"])
            self.assertEqual(self.library.status()["jobs"][0]["status"], "cancelled")
            self.library.add("https://reader.example.test/series")
            self.assertEqual(len(self.library.status()["jobs"]), 1)
            self.assertEqual(self.library.status()["jobs"][0]["status"], "pending")
        for url in ("file:///tmp/example", "https://user:password@example.test", "invalid"):
            with self.assertRaises(ValueError):
                self.library.add(url)


@unittest.skipUnless(shutil.which("gallery-dl"), "gallery-dl is required for extractor integration")
class GalleryIntegrationTests(unittest.TestCase):
    def setUp(self):
        LibraryTests.setUp(self)
        modules = self.base / "extractors"
        modules.mkdir()
        # A valid ASCII-only BMP lets gallery-dl's text downloader exercise its
        # real file, metadata and archive handling without any network requests.
        bmp = b"BM" + struct.pack("<IHHI", 58, 0, 0, 54)
        bmp += struct.pack("<IiiHHIIiiII", 40, 1, 1, 1, 24, 0, 4, 0, 0, 0, 0)
        bmp += b"\x1e\x14\x0a\x00"
        (modules / "synthetic.py").write_text(r'''
from gallery_dl.extractor.common import Extractor, Message
from pathlib import Path
import os, time
class SyntheticExtractor(Extractor):
    category = "synthetic"
    subcategory = "gallery"
    pattern = r"https://reader\.example\.test/(series|gallery|mixed|slow|fail|huge|truncated)"
    directory_fmt = ("{category}", "{title}")
    filename_fmt = "{page:>03}.{extension}"
    archive_fmt = "{title}_{page}"
    def items(self):
        mode = self.groups[0]
        if mode == "slow":
            Path(%r).write_text(str(os.getpid()))
            time.sleep(30)
        chapters = [2, 10] if mode == "series" else [None]
        for chapter in chapters:
            data = {"title": "Chapter " + str(chapter) if chapter else "Example gallery",
                    "tags": ["quiet"], "language": "English", "extension": "bmp"}
            if chapter:
                data.update(manga="Example manga", chapter=chapter)
            yield Message.Directory, "", data
            payload = %r
            if mode == "huge":
                payload = payload[:18] + "\x00\x00\x01\x00" * 2 + payload[26:]
            elif mode == "truncated":
                payload = payload[:-2]
            for page in [1, 2]:
                yield Message.Url, "text:" + payload, dict(data, page=page)
            if mode == "mixed":
                yield Message.Url, "text:video", dict(data, page=3, extension="mp4")
            if mode == "fail":
                raise RuntimeError("Synthetic failure after images")
''' % (str(self.base / "downloader.pid"), bmp.decode("ascii")))
        tools = self.base / "bin"
        tools.mkdir()
        real = shutil.which("gallery-dl")
        wrapper = tools / "gallery-dl"
        wrapper.write_text(f"#!{sys.executable}\nimport os,sys\n"
                          f"os.execv({real!r}, [{real!r}, '--config-ignore', '-X', {str(modules)!r}, *sys.argv[1:]])\n")
        wrapper.chmod(0o755)
        self.environment = patch.dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"])
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def run_job(self, mode):
        with patch.object(self.library, "start_worker"):
            self.library.add("https://reader.example.test/" + mode)
        with patch.object(library, "notify"):
            library.worker(self.library)
        return self.library.status()["jobs"][-1]

    def test_real_gallery_dl_manga_grouping_and_metadata(self):
        job = self.run_job("series")
        self.assertEqual(job["status"], "completed", self.library.status()["log"])
        self.assertEqual(len(job["outputs"]), 2)
        book = next(book for book in self.library.scan()["books"] if book["name"].startswith("Example manga"))
        self.assertEqual(len(book["chapters"]), 2)
        self.assertEqual(book["meta"]["tags"], ["quiet"])
        self.assertEqual(book["meta"]["languages"], ["english"])

    def test_real_gallery_dl_standalone_images_only_and_repeat_skips(self):
        job = self.run_job("mixed")
        self.assertEqual(job["status"], "completed", self.library.status()["log"])
        self.assertEqual(len(job["outputs"]), 1)
        with zipfile.ZipFile(job["outputs"][0]) as result:
            self.assertEqual(library.page_names(result.namelist()), ["001.bmp", "002.bmp"])
        repeated = self.run_job("mixed")
        self.assertEqual(repeated["status"], "completed", self.library.status()["log"])
        self.assertEqual(repeated["outputs"], job["outputs"])

    def test_retry_restores_an_archive_deleted_from_disk(self):
        job = self.run_job("gallery")
        self.assertEqual(job["status"], "completed", self.library.status()["log"])
        Path(job["outputs"][0]).unlink()
        repeated = self.run_job("gallery")
        self.assertEqual(repeated["status"], "completed", self.library.status()["log"])
        self.assertTrue(all(Path(path).is_file() for path in repeated["outputs"]))

    def test_real_gallery_dl_matching_titles_from_different_urls_stay_separate(self):
        first = self.run_job("gallery")
        self.assertEqual(first["status"], "completed", self.library.status()["log"])
        before = Path(first["outputs"][0]).read_bytes()
        second = self.run_job("mixed")
        self.assertEqual(second["status"], "completed", self.library.status()["log"])
        self.assertNotEqual(first["outputs"], second["outputs"])
        self.assertEqual(Path(first["outputs"][0]).read_bytes(), before)
        for path in [first["outputs"][0], second["outputs"][0]]:
            with zipfile.ZipFile(path) as result:
                self.assertEqual(library.page_names(result.namelist()), ["001.bmp", "002.bmp"])

    def test_changed_drive_is_rejected_before_starting_gallery_dl(self):
        with patch.object(self.library, "start_worker"):
            self.library.add("https://reader.example.test/gallery")
        job = self.library.status()["jobs"][0]
        job["device"] = -1
        with self.assertRaisesRegex(ValueError, "unmounted"):
            library.run_download(self.library, job)

    def test_failed_download_retains_staging_without_importing_partial_books(self):
        job = self.run_job("fail")
        self.assertEqual(job["status"], "failed")
        self.assertEqual(len(list(self.root.glob("*.cbz"))), 0)
        self.assertTrue(list((self.root / ".library-downloads").rglob("*.bmp")))

    def test_oversized_download_fails_cleanly_and_the_next_job_completes(self):
        oversized = self.run_job("huge")
        self.assertEqual(oversized["status"], "failed")
        self.assertIn("safe pixel limit", oversized["error"])
        self.assertEqual(oversized["outputs"], [])
        self.assertTrue(list((self.root / ".library-downloads" / oversized["id"]).rglob("*.bmp")))
        self.assertEqual(list(self.root.glob("*.cbz")), [])
        following = self.run_job("gallery")
        self.assertEqual(following["status"], "completed", self.library.status()["log"])
        self.assertTrue(all(Path(path).is_file() for path in following["outputs"]))

    def test_truncated_download_fails_without_publishing_and_retries_after_repair(self):
        job = self.run_job("truncated")
        self.assertEqual(job["status"], "failed")
        self.assertIn("Invalid downloaded image 001.bmp", job["error"])
        self.assertEqual(job["outputs"], [])
        self.assertEqual(list(self.root.glob("*.cbz")), [])
        stage = self.root / ".library-downloads" / job["id"]
        images = list(stage.rglob("*.bmp"))
        self.assertEqual(len(images), 2)
        for image in images:
            self.assertTrue(Path(str(image) + ".json").exists())
            image.write_bytes(oversized_bmp(1, 1))
        retried = self.run_job("truncated")
        self.assertEqual(retried["status"], "completed", self.library.status()["log"])
        with zipfile.ZipFile(retried["outputs"][0]) as result:
            self.assertEqual(library.page_names(result.namelist()), ["001.bmp", "002.bmp"])
            for name in library.page_names(result.namelist()):
                with Image.open(io.BytesIO(result.read(name))) as decoded:
                    decoded.load()
                    self.assertEqual(decoded.size, (1, 1))
        self.assertFalse(any(stage.rglob("*.bmp")))

    def test_cancellation_stops_a_silent_downloader_and_keeps_job_retryable(self):
        with patch.object(self.library, "start_worker"):
            self.library.add("https://reader.example.test/slow")
        thread = threading.Thread(target=library.worker, args=(self.library,), daemon=True)
        with patch.object(library, "notify"):
            thread.start()
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                job = library.document(self.library.queue_path)["jobs"][0]
                if job["status"] == "running":
                    break
                time.sleep(0.05)
            self.library.cancel(job["id"])
            thread.join(8)
        self.assertFalse(thread.is_alive())
        self.assertEqual(self.library.status()["jobs"][0]["status"], "cancelled")

    def test_detached_worker_completes_without_a_running_reader_helper(self):
        notify = self.base / "bin" / "notify-send"
        notify.write_text("#!/bin/sh\nexit 0\n")
        notify.chmod(0o755)
        self.library.add("https://reader.example.test/gallery")
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            job = self.library.status()["jobs"][0]
            if job["status"] not in ("pending", "running"):
                break
            time.sleep(0.1)
        self.assertEqual(job["status"], "completed", self.library.status()["log"])
        self.assertTrue(all(Path(path).is_file() for path in job["outputs"]))

    def test_killing_the_worker_stops_gallery_dl_and_recovers_both_active_job_states(self):
        self.check_worker_death(signal.SIGKILL)

    def test_terminating_the_worker_stops_gallery_dl_and_recovers_both_active_job_states(self):
        self.check_worker_death(signal.SIGTERM)

    def check_worker_death(self, termination_signal):
        # Queue two jobs under a stand-in worker's lock, then start the real
        # worker ourselves so the test owns exactly the process it terminates.
        with library.worker_lock(self.library), patch.object(self.library, "start_worker"):
            self.library.add("https://reader.example.test/slow")
            self.library.add("https://reader.example.test/gallery")
        command = [sys.executable, "-B", str(REPO / "scripts/library.py"), "--root", str(self.root),
                   "--state", str(self.library.state), "--cache", str(self.library.cache), "worker"]
        with (self.base / "worker-test.log").open("w") as log:
            worker = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                      start_new_session=True)
        try:
            with process_handle(wait_for_pid(self.base / "downloader.pid")) as downloader:
                jobs = self.library.status()["jobs"]
                self.assertEqual([job["status"] for job in jobs], ["running", "pending"])
                staged = self.root / ".library-downloads" / jobs[0]["id"] / "keep.part"
                staged.write_bytes(b"resume this download")
                worker.send_signal(termination_signal)
                worker.wait(timeout=8)
                self.assertTrue(select.select([downloader], [], [], 3)[0], "gallery-dl survived its worker")
            recovered = self.library.status()["jobs"]
            self.assertEqual([job["status"] for job in recovered], ["failed", "failed"])
            self.assertTrue(all("Retry" in job["error"] for job in recovered))
            self.assertEqual(staged.read_bytes(), b"resume this download")
            retry = self.run_job("gallery")
            self.assertEqual(retry["status"], "completed", self.library.status()["log"])
            self.assertEqual(staged.read_bytes(), b"resume this download")
        finally:
            if worker.poll() is None:
                worker.kill()
                worker.wait()


if __name__ == "__main__":
    unittest.main()
