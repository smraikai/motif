#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build ../work/benchmarks
label="current"
sources="Sources"
if [[ ! -x .deps/yt-dlp-runtime/yt-dlp_macos || ! -x .deps/deno ]]; then
  python3 Tools/fetch-dependencies.py
fi
if [[ "${1:-}" == "--baseline" ]]; then
  revision="${2:?Supply the baseline Git revision}"
  shift 2
  if [[ ! -x .deps/yt-dlp ]]; then
    python3 Tools/fetch-dependencies.py --include-baseline
  fi
  label="baseline-${revision:0:7}"
  sources=".build/benchmark-$label"
  mkdir -p "$sources"
  for name in Models YouTubeClient PreparedAudio StreamResolver PlayerStore; do
    git show "$revision:macos/Sources/$name.swift" > "$sources/$name.swift"
  done
fi
extra_sources=(-D MOTIF_BENCHMARK)
if [[ "$sources" == "Sources" ]]; then extra_sources+=(-D MOTIF_FAST_RESOLVER Sources/FastStreamResolver.swift); fi
xcrun swiftc -swift-version 5 -O -module-cache-path .build/ModuleCache \
  "${extra_sources[@]}" "$sources/Models.swift" "$sources/YouTubeClient.swift" "$sources/PreparedAudio.swift" \
  "$sources/StreamResolver.swift" "$sources/PlayerStore.swift" Tools/Benchmark.swift \
  -o ".build/benchmark-$label-bin"
".build/benchmark-$label-bin" --tools "$PWD/.deps" \
  --label "$label" --output "$PWD/../work/benchmarks/$label.json" "$@"
