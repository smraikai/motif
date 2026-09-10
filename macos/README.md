# Motif for macOS

A compact native menu-bar player for YouTube. The menu bar
shows one custom wave icon. Click it to open the 340 × 460 player; hover for track details.

## Install and launch

```sh
./macos/build.sh
./macos/install.sh --open-at-login
```

The installer puts Motif in `/Applications/Motif.app`. Launch it from Applications or Spotlight. Right-click the menu-bar icon and toggle **Open at Login** at any time. Startup registration uses macOS Service Management and is also visible in System Settings → General → Login Items. If macOS requests approval, use **Allow in System Settings…** in the same menu.

Omit `--open-at-login` to install without changing startup preferences. Launching at login keeps the popup closed and the saved queue paused. Opening Motif normally shows the player.

After building, you can also double-click `macos/Install Motif.command` in Finder
to install the latest build and reopen Motif without changing startup preferences.

## Run

Open `Motif.app`. It stays in the menu bar and keeps playing when the
popup closes. Right-click its icon for the player menu and Quit.
Click the menu-bar icon again to close the popup. Clicking outside also closes it.

Click the search icon at the top right or press Command-K to expand the search
capsule leftward within the header. The magnifier stays at its right edge. The
field stays on one line: the capsule grows with the query, stops before the app
name, and truncates long text when not editing. While editing, long queries
scroll horizontally so the caret stays visible. Playback, selection, search,
and volume accents use YouTube red.
Search runs after a short pause while typing. Results fill the player.
Click a result once or select it and press Return to play.
Choosing a result collapses search and returns to centered artwork, transport
controls, and Up next. Clearing the query returns to the current queue.
Choosing a search result starts its mix. The queue advances at
the end of each track and requests more recommendations near the end. YouTube
can return a finite mix or repeated recommendations, so a station can end.

- Play/pause, previous, next, seek, and per-track mixes. Volume is in the menu-bar icon's right-click menu.
- Command-K toggles the header search field. Down moves from search into the result list.
- Arrow keys select a row. Return plays it. Space toggles playback outside text fields.
- Command-Left and Command-Right change tracks. Escape closes the popup.
- macOS Now Playing and media-command integration.
- The queue and volume survive restarts. Relaunching restores the queue paused.

Motif resolves audio through YouTube's public playback API using an in-memory
visitor context and a shared HTTP session. This avoids starting an extractor
process for ordinary selections. The pinned extractor handles unsupported
responses, live streams, and fast-path failures. No Google account is used.

Motif prepares the first two search results, a hovered track, and the next two
queued tracks before selection. It resolves two likely choices concurrently
and primes paused audio players, then hands the selected player directly to
playback. At most two paused players are prepared alongside the active player.
Preparation stays silent and does not advance the track. Other cache entries
retain only their URLs and media assets. Expired links are refreshed.
Audio-only HLS streams take priority because some direct M4A streams stall
before becoming ready in AVPlayer. Mix requests wait until audio starts, and
playback does not wait for duration metadata. A circular spinner over the artwork shows buffering; the footer is
reserved for error messages. Playback starts when audio becomes available, while automatic
recovery remains enabled for network stalls. The extractor also keeps its
player-data cache between launches. The app bundles the official unpacked
extractor so requests do not each unpack a Python runtime into a temporary folder.

This uses public YouTube search, without Google sign-in. Search is general
YouTube search; adding `music` or `soundtrack` can narrow broad queries.
Unavailable, restricted, or unsupported tracks may fail. The player tries the
next queued track and stops after three consecutive failures.

## Build

Requires macOS 13 or newer, Apple Command Line Tools, and Python 3. Full Xcode,
Homebrew, mpv, jq, and socat are not required for the Mac app.

```sh
./macos/build.sh
open "macos/dist/Motif.app"
```

The build downloads pinned official yt-dlp and Deno releases, verifies their
published SHA-256 digests, and bundles them. The first build needs internet
access. Later builds use the verified cached files. The build targets the
current Mac's architecture. The initial packaged app is for Apple silicon.

The app uses AppKit and AVPlayer. Search, mix, and stream requests have separate
cancellation tokens, so late results cannot replace a newer selection. There is
only one player producing audio. Prepared players stay paused until selection.

The build is locally ad-hoc signed. It is not Developer ID signed or notarized
for public distribution. Vendor binaries retain their original signatures.
Signing happens in a temporary folder to avoid iCloud Finder metadata being
attached during the signing step.

## Checks

```sh
./macos/check.sh
```

Checks cover parsing, video ID validation, deduplication, queue boundaries,
saved-state validation, stale search/mix/stream responses, repeated failures,
search toggling, typing debounce, full-height results, one-action selection, and
clearing search back to the queue.
GitHub Actions also compiles the app on macOS.
Stream checks cover shared warm-up requests, reused media assets, expiry,
cancellation, prioritizing audio over mix requests, live streams, and outside
clicks. Interaction checks cover the artwork spinner during loading, pause,
and resume, with errors still visible in the footer. Spinner geometry checks
verify that its center stays fixed through a full turn and after resizing.
Native playback checks also cover preroll, paused preparation, player handoff,
volume, pausing during resolution, cache eviction during playback, and replay
starting at the beginning. Fast-resolver checks cover shared context, audio-only
selection, mismatched video IDs, unsupported responses, fallback and cancellation.

## Playback benchmarks

The [September 10 benchmark report](Benchmarks/2026-09-10.md) records before/after
measurements, the initial playback failure, and the remaining startup limits.

```sh
./macos/benchmark-comparison.sh
# More samples, including a click shortly after a search:
./macos/benchmark-comparison.sh --session shared --runs 3 --modes cold,search-click-1s,prefetched
# Individual runs:
./macos/benchmark.sh --baseline 6756fb3
./macos/benchmark.sh --runs 3
```

The scripts fetch missing pinned dependencies before compiling. The comparison
retains the original one-file extractor for the baseline. Run in a normal
Terminal or an execution environment with network and audio access. Pause any other music before running the benchmark.
The benchmark uses an isolated preferences domain and briefly plays audio at
15% app volume. It does not replace your queue or change Motif's settings.
Reports are written under `work/benchmarks/` and excluded from Git.

The default tracks are three long-form music videos. Search results are supplied
to the real store without a search request; mix requests are disabled to isolate
selection latency. The selected track is the first result by default. Use
`--result-position 2` to measure the second result's preparation.
Override the tracks with
`--tracks ID1,ID2,ID3`. `cold` starts with an empty resolver; `prefetched` gives
URL resolution and two seconds of preparation before the simulated click.
`--modes cold,search-click-1s,prefetched` additionally measures a click one second
after results appear. Extraction's on-disk player cache remains enabled.

`--session fresh` creates a new HTTP client for each sample and includes public
context initialization in cold resolution. `--session shared` keeps one client
throughout the run, matching an app that stays open. Both create an empty stream
cache for each sample. The first shared sample still includes client startup.

The endpoint requires AVPlayer to be playing with at least 20 ms of advancing
media time, sampled every 5 ms. Reports separate resolution, extractor invocations, item readiness,
selection-to-playback, preparation lead time, and stalls in the following second.
This is a playback-pipeline measurement, not an acoustic loopback recording; it
does not remove silence at the beginning of a track or measure device latency.

The comparison uses `--profile hls` for the baseline and `--profile standard`
for the current build. `--profile standard` uses each build's own resolver. The original build
can fail on direct M4A streams on macOS 27. `--profile hls` applies the current
HLS preference to both builds, allowing a timing comparison of playable audio
without changing the baseline source. This profile bypasses the native resolver
in the current build, isolating the unpacked extractor and preroll changes.
Keep those results separate from the
original failure report. `--profile lean` additionally tests skipping initial
page data and DASH manifest extraction. It is not enabled in the application.
Reports retain failures, native error codes, buffering reasons, and item status.
Compare the same tracks, connection, and audio device.

Initial app validation on an Apple silicon Mac running macOS 15.7.9:

- Official bundled tools searched YouTube and resolved an AAC audio stream.
- A muted AVPlayer check decoded the stream and advanced over two seconds.
- The actual app loaded a 40-track Zelda mix and played a track with an advancing progress slider.
- Restarting the compact build restored that queue paused.
- The native 340 × 460 view was rendered for layout inspection.
- Local app bundle signature verification passed before copying it to Documents.

## Source layout

- `Sources/Models.swift`: tracks, parsing, queue rules, persistence shape.
- `Sources/YouTubeClient.swift`: native resolution, extractor fallback, cancellation.
- `Sources/FastStreamResolver.swift`: public visitor context, player API, audio-only HLS.
- `Sources/PlayerStore.swift`: playback, mixes, queue state, media commands.
- `Sources/PlayerViewController.swift`: compact AppKit player and result list.
- `Sources/main.swift`: menu-bar icon, popup lifecycle, menus, single-instance check.
- `Tools/fetch-dependencies.py`: pinned download URLs and checksums.

Update the release URLs and digests in `fetch-dependencies.py` when a YouTube
change requires a newer extractor, then rebuild. No files are downloaded or
executed from a user-supplied search string, and external tools receive arguments
directly rather than through a shell.

The Mac app stores its queue and volume in the standard UserDefaults domain
`io.github.itsdotdev.motif`. It stores no Google credentials or
stream URLs. Third-party notices are included in the app's Resources folder.

The custom app and menu-bar artwork and its generation prompts are saved in
`Resources/`. The player has no three-dot menu; use the menu-bar icon's right-click menu.

On the first Motif launch, the app copies the prior YouTube Music queue and volume without overwriting existing Motif preferences.

For installation verification, `"/Applications/Motif.app/Contents/MacOS/Motif" --login-item-status` prints the current macOS login-item registration state.
