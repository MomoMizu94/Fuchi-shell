"""Read cliphist entries for the sidebar and restore their original bytes."""
import argparse
import base64
import io
import json
import re
import subprocess
import sys
import tempfile


def list_entries():
    result = subprocess.run(["cliphist", "list"], capture_output=True)
    if result.returncode:
        if b"please store something first" in result.stderr:
            return []
        raise RuntimeError("Could not read clipboard history.")
    entries = []
    for line in result.stdout.decode("utf-8", errors="replace").split("\n"):
        key, tab, preview = line.partition("\t")
        if not tab or not key.isascii() or not key.isdigit():
            continue
        binary = preview.startswith("[[ binary data ") and preview.endswith(" ]]")
        if binary:
            info = preview[len("[[ binary data "):-len(" ]]")]
            image = re.fullmatch(r"(.+?) (\w+) (\d+)x(\d+)", info)
            preview = f"{image[2].upper()} · {image[3]} × {image[4]}" if image else info
        elif "\x00" in preview:
            # cliphist prints raw bytes for some formats, including WebP and ICO
            binary = True
            preview = "WebP image" if preview.startswith("RIFF") and "WEBP" in preview[4:20] else "Binary data"
        entries.append({"key": key, "label": preview, "binary": binary})
    return entries


def thumbnail(stream):
    from PIL import Image, ImageOps, UnidentifiedImageError

    try:
        with Image.open(stream) as image:
            image.thumbnail((240, 144))
            thumb = ImageOps.exif_transpose(image).convert("RGBA")
            encoded = io.BytesIO()
            thumb.save(encoded, format="PNG")
            return "data:image/png;base64," + base64.b64encode(encoded.getvalue()).decode("ascii")
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError, ValueError):
        return ""


def run(action, key):
    if action == "list":
        return json.dumps(list_entries())
    if not key or not key.isascii() or not key.isdigit():
        raise ValueError("Select a clipboard entry first.")
    # Decode before taking ownership of the clipboard in case the entry has expired
    with tempfile.TemporaryFile(buffering=0) as data:
        result = subprocess.run(["cliphist", "decode"], input=key.encode(), stdout=data,
                                stderr=subprocess.DEVNULL)
        if result.returncode or not data.tell():
            raise RuntimeError("This entry is no longer in clipboard history.")
        data.seek(0)
        if action == "thumbnail":
            return thumbnail(data)
        command = ["wl-copy"]
        if action == "copy-text":
            command += ["--type", "text/plain;charset=utf-8"]
        else:
            header = data.read(12)
            if header.startswith(b"RIFF") and header[8:] == b"WEBP":
                command += ["--type", "image/webp"]
            data.seek(0)
        subprocess.run(command, stdin=data, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       check=True)
    return ""


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["list", "thumbnail", "copy-text", "copy-binary"])
    parser.add_argument("key", nargs="?")
    args = parser.parse_args()
    try:
        print(run(args.action, args.key))
    except FileNotFoundError as error:
        sys.exit(f"Install {error.filename} to use clipboard history.")
    except subprocess.CalledProcessError:
        sys.exit("Could not copy this entry to the Wayland clipboard.")
    except (OSError, RuntimeError, ValueError) as error:
        sys.exit(str(error))
