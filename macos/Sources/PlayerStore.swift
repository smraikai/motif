import AppKit
import AVFoundation
import MediaPlayer

final class PlayerStore {
    let client: MusicClient
    let player = AVPlayer()
    private let resolver: StreamResolver
    private let enablePreloading: Bool
    var changed: (() -> Void)?
    private(set) var queue = QueueState()
    private(set) var results: [Track] = []
    private(set) var searching = false
    private(set) var mixing = false
    private(set) var loading = false
    private(set) var playing = false
    private(set) var position = 0.0
    private(set) var duration = 0.0
    var showingSearch = true
    var query = ""
    var message = ""
    var volume: Float = 0.7 { didSet { player.volume = volume; defaults.set(volume, forKey: "volume") } }
    private var searchJob: Extraction?
    private var mixJob: Extraction?
    private var pendingMixSeed: Track?
    private var streamJob: Extraction?
    private var searchID = UUID()
    private var mixID = UUID()
    private var streamID = UUID()
    private var queueID = UUID()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var startupBufferObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var lastRefillSeed = ""
    private var failures = 0
    private var wantsPlayback = false
    private var retryCachedStream = false
    private let defaults: UserDefaults
    private let enableMediaControls: Bool
    var current: Track? { queue.current }
    var displayedTracks: [Track] { showingSearch ? results : queue.tracks }

    init(client: MusicClient = YouTubeClient(), defaults: UserDefaults = .standard, enableMediaControls: Bool = true, enablePreloading: Bool = true) {
        self.client = client; self.defaults = defaults; self.enableMediaControls = enableMediaControls
        resolver = StreamResolver(client: client, preloadAssets: enablePreloading); self.enablePreloading = enablePreloading
        if let saved = defaults.data(forKey: "queue"), let decoded = try? JSONDecoder().decode(QueueState.self, from: saved), decoded.isValid {
            queue = decoded
            showingSearch = queue.current == nil
        }
        if defaults.object(forKey: "volume") != nil { volume = defaults.float(forKey: "volume") }
        player.volume = volume
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            self.position = time.seconds.isFinite ? max(0, time.seconds) : 0
            let seconds = self.player.currentItem?.duration.seconds ?? 0
            self.duration = seconds.isFinite ? max(0, seconds) : 0
            if self.position > 10 { self.failures = 0 }
            self.notify()
        }
        rateObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.playing = self.player.timeControlStatus == .playing
                self.loading = self.wantsPlayback && (self.streamJob != nil || self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
                if self.playing {
                    self.retryCachedStream = false; self.startupBufferObserver = nil
                    self.startPendingMix()
                    self.prepareNextTrack()
                }
                self.notify()
            }
        }
        if enableMediaControls { installRemoteCommands() }
        if !client.available { message = "The bundled player tools are missing. Rebuild or reinstall the app." }
        if enablePreloading, let current { resolver.prepare([current]) }
    }

    func notify() {
        updateNowPlaying()
        changed?()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(queue) { defaults.set(data, forKey: "queue") }
    }
    // Invalidate results as soon as the user edits, before the debounce fires.
    func editQuery(_ text: String) {
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        searchJob?.cancel(); searchID = UUID()
        if enablePreloading { resolver.prepare([]) }
        searching = false; results = []; message = ""
        showingSearch = !query.isEmpty || current == nil
        notify()
    }
    func search(_ text: String) {
        editQuery(text)
        guard !query.isEmpty else { return }
        searching = true; notify()
        let id = searchID
        searchJob = client.search(query) { [weak self] response in
            guard let self, self.searchID == id else { return }
            self.searching = false
            switch response {
            case .success(let tracks):
                self.results = tracks; self.message = tracks.isEmpty ? "No tracks found. Try another search." : ""
                if self.enablePreloading && !self.loading { self.resolver.prepare(Array(tracks.prefix(2))) }
            case .failure: self.message = "Search couldn't reach YouTube. Check your connection and try again."
            }
            self.notify()
        }
    }

    func select(_ index: Int) {
        guard displayedTracks.indices.contains(index) else { return }
        if showingSearch { startMix(from: results[index]) }
        else { queue.index = index; failures = 0; playCurrent() }
    }
    func startMix(from track: Track) {
        searchJob?.cancel(); searchID = UUID(); searching = false
        mixJob?.cancel(); mixJob = nil; mixID = UUID(); queueID = UUID()
        queue = QueueState(tracks: [track], index: 0)
        lastRefillSeed = ""; failures = 0
        showingSearch = false
        pendingMixSeed = track; mixing = true
        playCurrent()
    }
    private func buildMix(seed: Track) {
        mixJob?.cancel(); mixJob = nil; mixID = UUID()
        pendingMixSeed = seed; mixing = true
        if !loading { startPendingMix() }
        notify()
    }
    private func startPendingMix() {
        guard let seed = pendingMixSeed else { return }
        pendingMixSeed = nil
        let id = mixID, revision = queueID
        mixing = true; lastRefillSeed = seed.id; notify()
        mixJob = client.mix(seed) { [weak self] response in
            guard let self, self.mixID == id, self.queueID == revision else { return }
            self.mixing = false; self.mixJob = nil
            switch response {
            case .success(let tracks):
                self.queue.appendUnique(tracks); self.save()
                if self.playing { self.prepareNextTrack() }
            case .failure: self.message = "The mix couldn't load. Your current track will keep playing."
            }
            self.notify()
        }
    }
    func retryMix() {
        if let track = current { buildMix(seed: track) }
    }

    func playCurrent() {
        guard let track = current else { return }
        streamJob?.cancel(); streamID = UUID()
        let id = streamID
        clearItem()
        wantsPlayback = true; loading = true; playing = false
        position = 0; duration = 0; message = ""
        retryCachedStream = false
        save(); notify()
        resolveCurrent(track, id: id)
        if queue.tracks.count - queue.index <= 5, !mixing,
           let seed = queue.tracks.last, seed.id != lastRefillSeed {
            buildMix(seed: seed)
        }
    }
    private func resolveCurrent(_ track: Track, id: UUID) {
        streamJob = resolver.resolve(track) { [weak self] response in
            guard let self, self.streamID == id else { return }
            self.streamJob = nil
            switch response {
            case .success(let stream):
                self.retryCachedStream = stream.reused
                self.load(stream.audio, id: id)
            case .failure: self.failed(id: id)
            }
        }
    }
    func prepareForSelection(_ track: Track) {
        if enablePreloading && !loading && current?.id != track.id { resolver.prepare([track]) }
    }
    private func prepareNextTrack() {
        guard enablePreloading, !showingSearch, !loading,
              queue.tracks.indices.contains(queue.index + 1) else { return }
        resolver.prepare([queue.tracks[queue.index + 1]])
    }
    private func clearItem() {
        statusObserver = nil
        startupBufferObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil; failureObserver = nil
        player.pause(); player.replaceCurrentItem(with: nil)
    }
    private func load(_ audio: PreparedAudio, id: UUID) {
        // Duration is already available in the search result. Do not delay the
        // first audio frame to load it again before marking the item ready.
        let item = AVPlayerItem(asset: audio.claim(), automaticallyLoadedAssetKeys: [])
        item.preferredForwardBufferDuration = 2
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.streamID == id else { return }
                if item.status == .failed { self.failed(id: id) }
                else if item.status == .readyToPlay {
                    self.loading = self.wantsPlayback && self.player.timeControlStatus != .playing
                    self.startAvailableAudio(item, id: id)
                    self.notify()
                }
            }
        }
        startupBufferObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async { self?.startAvailableAudio(item, id: id) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self, self.streamID == id else { return }
            if self.queue.advance(by: 1, wrap: false) { self.playCurrent() }
            else { self.wantsPlayback = false; self.playing = false; self.loading = false; self.notify() }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.failed(id: id)
        }
        player.replaceCurrentItem(with: item)
        if wantsPlayback { player.play() }
        // A ready stream that never starts must not leave the UI loading forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { [weak self] in
            guard let self, self.streamID == id, self.wantsPlayback,
                  self.position < 0.1, self.player.timeControlStatus != .playing else { return }
            self.failed(id: id)
        }
    }
    private func startAvailableAudio(_ item: AVPlayerItem, id: UUID) {
        guard streamID == id, wantsPlayback, item.status == .readyToPlay,
              !item.isPlaybackBufferEmpty else { return }
        // Skip the initial "likely to play through" wait. Keep AVPlayer's
        // automatic waiting enabled so an actual network stall still recovers.
        player.playImmediately(atRate: 1)
    }
    private func failed(id: UUID) {
        guard streamID == id else { return }
        if retryCachedStream, let track = current {
            retryCachedStream = false; resolver.invalidate(track)
            streamID = UUID(); let freshID = streamID
            clearItem(); loading = wantsPlayback
            resolveCurrent(track, id: freshID)
            notify(); return
        }
        streamID = UUID(); clearItem()
        failures += 1; playing = false; loading = false; wantsPlayback = false
        if failures < 3, queue.advance(by: 1, wrap: false) { playCurrent() }
        else {
            message = "This track couldn't play. Try another track or retry playback."
            startPendingMix(); notify()
        }
    }
    func toggle() {
        if wantsPlayback { pause() }
        else { resume() }
    }
    func pause() {
        wantsPlayback = false; player.pause(); playing = false; loading = false
        startPendingMix(); notify()
    }
    func resume() {
        if player.currentItem == nil && streamJob == nil { failures = 0; playCurrent() }
        else if duration > 0 && position >= duration - 0.5 { playCurrent() }
        else {
            wantsPlayback = true; loading = !playing
            if player.currentItem != nil { player.playImmediately(atRate: 1) }
            notify()
        }
    }
    func next() { if queue.advance(by: 1, wrap: true) { failures = 0; playCurrent() } }
    func previous() {
        if queue.advance(by: -1, wrap: true) { failures = 0; playCurrent() }
    }
    func seek(_ seconds: Double) {
        guard duration > 0 else { return }
        player.seek(to: CMTime(seconds: min(duration, max(0, seconds)), preferredTimescale: 600))
    }
    func shutdown() {
        streamID = UUID(); searchID = UUID(); mixID = UUID()
        searchJob?.cancel(); mixJob?.cancel(); streamJob?.cancel()
        pendingMixSeed = nil
        resolver.shutdown()
        clearItem()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        if enableMediaControls {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }
    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.toggle() }; return .success }
        center.playCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.resume() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.pause() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            DispatchQueue.main.async { self?.seek(event.positionTime) }; return .success
        }
    }
    private func updateNowPlaying() {
        guard enableMediaControls, let track = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: track.isLive
        ]
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }
}
