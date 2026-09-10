#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
report_dir="$PWD/../work/benchmarks/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$report_dir"
printf 'Pause other music. Reports will be saved in %s\n' "$report_dir"
./benchmark.sh --baseline 6756fb3 --profile hls --output "$report_dir/baseline.json" "$@"
./benchmark.sh --profile standard --output "$report_dir/current.json" "$@"
python3 - "$report_dir" <<'PY'
import json, math, statistics, sys
from pathlib import Path
directory = Path(sys.argv[1])
summary = []
for name in ('baseline', 'current'):
    report = json.loads((directory / f'{name}.json').read_text())
    for mode in sorted({row['mode'] for row in report['samples']}):
        samples = [row for row in report['samples'] if row['mode'] == mode]
        values = sorted(row['selectionToPlaybackMs'] for row in samples if 'selectionToPlaybackMs' in row)
        row = {'build': name, 'mode': mode, 'samples': len(samples), 'failures': len(samples) - len(values)}
        if values:
            row.update(p50Ms=round(statistics.median(values)),
                       p95Ms=round(values[math.ceil(len(values) * .95) - 1]),
                       belowOneSecond=sum(value < 1000 for value in values))
        summary.append(row)
        print(json.dumps(row))
(directory / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print('Comparison saved to', directory / 'summary.json')
PY
