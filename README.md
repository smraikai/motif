# Motif

A compact native macOS menu-bar music player. Search YouTube, start a mix, and keep listening without opening a browser tab.

## Install

```sh
./macos/build.sh
./macos/install.sh --open-at-login
```

This installs `Motif.app` in `/Applications` and opens it. Omit `--open-at-login` to leave the current startup setting unchanged.

Open Motif from Applications or Spotlight. Click its wave icon to show the player. Right-click for volume, **Open at Login**, and Quit. Login launches stay in the menu bar and restore your queue paused.

Search expands from the top-right magnifier or Command-K, results play with one click, and selecting a track builds its mix. The search field grows with the query and stays on one line. Red accents and an artwork spinner show playback state.

See [macOS setup, controls, and development](macos/README.md). The build bundles verified yt-dlp and Deno tools and uses AppKit with AVPlayer. Requires macOS 13 or later. Local builds are ad-hoc signed.

## Development

```sh
./macos/check.sh
./macos/build.sh
```

Motif keeps your queue and volume when upgrading from the earlier YouTube Music build.

## Attribution

Motif is an independent macOS project, originally adapted from [itsdotdev/omarchy-youtube-music](https://github.com/itsdotdev/omarchy-youtube-music). This repository contains only Motif. The original project's copyright notice is retained in [LICENSE](LICENSE).

MIT. Third-party licenses are included in the app.
