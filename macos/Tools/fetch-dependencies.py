#!/usr/bin/env python3
"""Fetch pinned official binaries and verify their published SHA-256 digests."""
import hashlib
from pathlib import Path
import platform
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1] / '.deps'
ROOT.mkdir(exist_ok=True)
ASSETS = [
    ('yt-dlp', 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos',
     '0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202'),
]
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
    if name.endswith('.zip'):
        with zipfile.ZipFile(path) as archive:
            (ROOT / 'deno').write_bytes(archive.read('deno'))
    else:
        path.chmod(0o755)
(ROOT / 'deno').chmod(0o755)
print('Verified yt-dlp 2026.08.19 and Deno 2.9.6')
