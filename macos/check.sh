#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
xcrun swiftc -swift-version 5 -module-cache-path .build/ModuleCache Sources/Models.swift Tests/CoreTests.swift -o .build/check-core
.build/check-core
plutil -lint Resources/Info.plist
xcrun swiftc -swift-version 5 -module-cache-path .build/ModuleCache Sources/Models.swift Sources/YouTubeClient.swift Sources/FastStreamResolver.swift Sources/PreparedAudio.swift Sources/StreamResolver.swift Sources/PlayerStore.swift Tests/StoreTests.swift -o .build/check-store
.build/check-store
xcrun swiftc -swift-version 5 -module-cache-path .build/ModuleCache Sources/Models.swift Sources/YouTubeClient.swift Sources/FastStreamResolver.swift Sources/PreparedAudio.swift Sources/StreamResolver.swift Sources/PlayerStore.swift Sources/PlayerTheme.swift Sources/ArtworkLoadingView.swift Sources/PlayerViewController.swift Tests/InteractionTests.swift -o .build/check-interactions
.build/check-interactions
xcrun swiftc -swift-version 5 -module-cache-path .build/ModuleCache Sources/AppPreferences.swift Sources/LoginItemController.swift Tests/AppSettingsTests.swift -o .build/check-settings
.build/check-settings
xcrun swiftc -swift-version 5 -module-cache-path .build/ModuleCache Sources/Models.swift Sources/YouTubeClient.swift Sources/FastStreamResolver.swift Sources/PreparedAudio.swift Sources/StreamResolver.swift Sources/PopoverHitTest.swift Tests/StreamResolverTests.swift -o .build/check-resolver
.build/check-resolver
xcrun swiftc -swift-version 5 -module-cache-path .build/ModuleCache Sources/PreparedAudio.swift Tests/PreparedAudioTests.swift -o .build/check-prepared-audio
.build/check-prepared-audio
xcrun swiftc -swift-version 5 -module-cache-path .build/ModuleCache Sources/Models.swift Sources/YouTubeClient.swift Sources/FastStreamResolver.swift Sources/PreparedAudio.swift Sources/StreamResolver.swift Sources/PlayerStore.swift Tests/PlaybackTests.swift -o .build/check-playback
.build/check-playback
xcrun swiftc -swift-version 5 -module-cache-path .build/ModuleCache Sources/PlayerTheme.swift Sources/ArtworkLoadingView.swift Tests/SpinnerTests.swift -o .build/check-spinner
.build/check-spinner

xcrun swiftc -swift-version 5 -module-cache-path .build/ModuleCache Sources/Models.swift Sources/YouTubeClient.swift Sources/FastStreamResolver.swift Tests/FastStreamTests.swift -o .build/check-fast-stream
.build/check-fast-stream
