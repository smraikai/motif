#!/usr/bin/env python3
"""Fetch pinned official binaries and verify their published SHA-256 digests."""
import hashlib
from pathlib import Path
import platform
import stat
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1] / '.deps'
ROOT.mkdir(exist_ok=True)
ASSETS = [
    ('yt-dlp_macos.zip', 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos.zip',
     '07e54b0865303c864006925913bce2604f8ee8cc6f18699bac9c309f9328a6d8'),
]
if '--include-baseline' in sys.argv:
    # Only the comparison benchmark needs the former one-file distribution.
    ASSETS.append(('yt-dlp', 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos',
                   '0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202'))
if platform.machine() == 'arm64':
    ASSETS.append(('deno.zip', 'https://github.com/denoland/deno/releases/download/v2.9.6/deno-aarch64-apple-darwin.zip',
                   '213a2f304f04d3c9cb5220669afad138f60a5aab1fe80962abdeb8f35807a472'))
else:
    ASSETS.append(('deno.zip', 'https://github.com/denoland/deno/releases/download/v2.9.6/deno-x86_64-apple-darwin.zip',
                   '7d4524b82bcc557fe020a1a5b56956ed42b992ae5b28026e8ad5d17329533f5f'))
for name, url, digest in ASSETS:
    path = ROOT / name
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        print(f'Downloading {name}', flush=True)
        temporary = path.with_suffix('.download')
        urllib.request.urlretrieve(url, temporary)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != digest:
            temporary.unlink()
            raise SystemExit(f'Checksum mismatch: {name}')
        temporary.replace(path)
    if name == 'yt-dlp_macos.zip':
        # The official directory distribution avoids unpacking the Python
        # runtime into a temporary directory on every search/stream request.
        destination = ROOT / 'yt-dlp-runtime'
        destination.mkdir(exist_ok=True)
        with zipfile.ZipFile(path) as archive:
            for entry in archive.infolist():
                target = destination / entry.filename
                if not target.resolve().is_relative_to(destination.resolve()) or stat.S_ISLNK(entry.external_attr >> 16):
                    raise SystemExit(f'Unsafe archive member: {entry.filename}')
                if entry.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(entry))
                    target.chmod((entry.external_attr >> 16) & 0o777)
    elif name.endswith('.zip'):
        with zipfile.ZipFile(path) as archive:
            (ROOT / 'deno').write_bytes(archive.read('deno'))
    else:
        path.chmod(0o755)
(ROOT / 'deno').chmod(0o755)
print('Verified unpacked yt-dlp 2026.08.19 and Deno 2.9.6')
