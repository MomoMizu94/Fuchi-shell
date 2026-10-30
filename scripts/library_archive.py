#!/usr/bin/env python3
"""Stream one archive into flat, bounded page files using the installed libarchive."""
import ctypes as C
from ctypes.util import find_library
import json
import os
from pathlib import Path
import re
import signal
import sys


def extract(path, destination, entry_limit, chapter_limit, listing_limit):
    api = C.CDLL(find_library("archive") or "libarchive.so.13")
    signatures = {
        "archive_read_new": (C.c_void_p, []),
        "archive_read_support_filter_all": (C.c_int, [C.c_void_p]),
        "archive_read_support_format_all": (C.c_int, [C.c_void_p]),
        "archive_read_open_filename": (C.c_int, [C.c_void_p, C.c_char_p, C.c_size_t]),
        "archive_read_next_header": (C.c_int, [C.c_void_p, C.POINTER(C.c_void_p)]),
        "archive_entry_pathname": (C.c_char_p, [C.c_void_p]),
        "archive_entry_size": (C.c_int64, [C.c_void_p]),
        "archive_entry_filetype": (C.c_uint, [C.c_void_p]),
        "archive_read_data": (C.c_ssize_t, [C.c_void_p, C.c_void_p, C.c_size_t]),
        "archive_error_string": (C.c_char_p, [C.c_void_p]),
        "archive_read_free": (C.c_int, [C.c_void_p]),
    }
    for name, (result, arguments) in signatures.items():
        function = getattr(api, name)
        function.restype, function.argtypes = result, arguments
    handle = api.archive_read_new()
    if not handle:
        raise MemoryError("Could not allocate an archive reader")

    def check(code):
        if code < 0:
            message = api.archive_error_string(handle)
            raise ValueError(message.decode(errors="replace") if message else "Could not read archive")
        return code

    pages, total, listing_size = [], 0, 0
    buffer = C.create_string_buffer(64 * 1024)
    try:
        check(api.archive_read_support_filter_all(handle))
        check(api.archive_read_support_format_all(handle))
        check(api.archive_read_open_filename(handle, os.fsencode(path), 64 * 1024))
        entry = C.c_void_p()
        while check(api.archive_read_next_header(handle, C.byref(entry))) != 1:
            raw_name = api.archive_entry_pathname(entry) or b""
            listing_size += len(raw_name) + 1
            if listing_size > listing_limit:
                raise ValueError("Archive listing exceeds the 8 MiB limit")
            name = os.fsdecode(raw_name)
            suffix = Path(name).suffix.lower()
            if suffix not in {".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif", ".bmp"} \
                    or "__MACOSX" in Path(name).parts:
                continue
            if api.archive_entry_filetype(entry) != 0o100000:
                raise ValueError("Archive page images must be regular files")
            if api.archive_entry_size(entry) > entry_limit:
                raise ValueError("An archive entry exceeds the 200 MiB page limit")
            temporary = Path(destination) / f"p{len(pages):05d}{suffix}"
            size = 0
            with temporary.open("xb") as target:
                while True:
                    count = check(api.archive_read_data(handle, buffer, len(buffer)))
                    if not count:
                        break
                    size += count
                    total += count
                    if size > entry_limit:
                        raise ValueError("An archive entry exceeds the 200 MiB page limit")
                    if total > chapter_limit:
                        raise ValueError("Extracted chapter exceeds the 2 GiB cache limit")
                    target.write(buffer.raw[:count])
            if not size:
                raise ValueError("An archive page image is empty")
            pages.append((name, temporary))
    finally:
        api.archive_read_free(handle)
    pages.sort(key=lambda item: [int(part) if part.isdigit() else part.casefold()
                                for part in re.split(r"(\d+)", item[0])])
    names = []
    for index, (_, temporary) in enumerate(pages):
        name = f"{index:05d}{temporary.suffix}"
        temporary.rename(Path(destination) / name)
        names.append(name)
    return names


if __name__ == "__main__":
    try:
        # Stop cache extraction if its Library helper exits while we are reading.
        libc = C.CDLL(None, use_errno=True)
        libc.prctl.argtypes = [C.c_int, C.c_ulong, C.c_ulong, C.c_ulong, C.c_ulong]
        libc.prctl.restype = C.c_int
        if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
            raise OSError("Could not protect the archive reader's helper lifetime")
        if os.getppid() != int(sys.argv[6]):
            raise OSError("Library helper stopped before archive extraction started")
        result = extract(sys.argv[1], sys.argv[2], *(int(value) for value in sys.argv[3:6]))
        print(json.dumps(result))
    except (OSError, ValueError, MemoryError) as error:
        print(str(error)[:2000], file=sys.stderr)
        sys.exit(1)
