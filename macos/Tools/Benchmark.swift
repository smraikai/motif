import AppKit
import AVFoundation
import Foundation

// Uses the real PlayerStore and extractor. No stream URLs, cookies, or user
// preferences are written to the report. Playback is intentionally audible.
final class BenchmarkClient: MusicClient {
    let source: YouTubeClient
    let profile: String
    var available: Bool { source.available }
    var track: Track!
    var alternatives: [Track] = []
    var resultPosition = 1
    var resolvedAt: Double?
    var startedAt: Double?
    var extractionError: String?
    var requests = 0
    var extractorRequests = 0
    var events: [[String: Any]] = []
    init(tools: URL, cache: URL, profile: String, sharedSource: YouTubeClient? = nil) {
        if let sharedSource { source = sharedSource }
        else {
            #if MOTIF_FAST_RESOLVER
            source = YouTubeClient(tools: tools, cacheDirectory: cache, enableFastResolver: profile == "standard")
            #else
            source = YouTubeClient(tools: tools, cacheDirectory: cache)
            #endif
        }
        self.profile = profile
        #if MOTIF_FAST_RESOLVER
        source.streamEvent = { [weak self] id, event in
            guard let self else { return }
            if event == "extractor-start" { self.extractorRequests += 1 }
            if id == self.track?.id {
                self.events.append(["event": event, "atMs": (ProcessInfo.processInfo.systemUptime - (self.startedAt ?? ProcessInfo.processInfo.systemUptime)) * 1000])
            }
        }
        #endif
    }
    func search(_ query: String, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction {
        let token = Extraction()
        var results = alternatives
        results.insert(track, at: min(resultPosition - 1, results.count))
        DispatchQueue.main.async { if !token.isCancelled { completion(.success(results)) } }
        return token
    }
    func mix(_ seed: Track, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction {
        let token = Extraction()
        DispatchQueue.main.async { if !token.isCancelled { completion(.success([])) } }
        return token
    }
    func stream(_ track: Track, completion: @escaping (Result<URL, Error>) -> Void) -> Extraction {
        requests += 1
        #if MOTIF_FAST_RESOLVER
        if profile != "standard" { extractorRequests += 1 }
        #else
        extractorRequests += 1
        #endif
        let measured = track.id == self.track.id
        if measured { startedAt = ProcessInfo.processInfo.systemUptime }
        let done: (Result<URL, Error>) -> Void = { result in
            if measured {
                self.resolvedAt = ProcessInfo.processInfo.systemUptime
                if case .failure(let error) = result {
                    self.extractionError = error.localizedDescription.replacingOccurrences(of: "https?://[^\\s]+", with: "[URL]", options: .regularExpression)
                }
            }
            completion(result)
        }
        guard profile != "standard" else { return source.stream(track, completion: done) }
        let extra = profile == "lean" ? ["--extractor-args", "youtube:player_skip=initial_data;skip=dash"] : []
        return source.request(extra + [
            "--no-playlist", "--skip-download", "--dump-single-json",
            "--format", "bestaudio[protocol*=m3u8]/bestaudio[ext=m4a]/best[ext=mp4]", track.url.absoluteString
        ]) { response in
            done(response.flatMap { data in Result {
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let raw = object?["url"] as? String, let url = URL(string: raw), url.scheme == "https" else {
                    throw PlayerError(message: "No compatible stream returned by the test profile")
                }
                return url
            } })
        }
    }
}

@main struct Benchmark {
    static func tick() { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    static var clock: Double { ProcessInfo.processInfo.systemUptime }
    static func wait(_ seconds: Double) { let end = clock + seconds; while clock < end { tick() } }
    static func main() {
        do { try run() }
        catch { fputs("Benchmark error: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run() throws {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        func option(_ name: String, _ fallback: String) -> String {
            guard let i = args.lastIndex(of: name), args.indices.contains(i + 1) else { return fallback }
            return args[i + 1]
        }
        let tools = URL(fileURLWithPath: option("--tools", ".deps"), isDirectory: true)
        let output = URL(fileURLWithPath: option("--output", "benchmark.json"))
        let profile = option("--profile", "standard")
        let session = option("--session", "fresh")
        let ids = option("--tracks", "JCKBaJDRMw4,1fueZCTYkpA,Hes3qNwMzIg").split(separator: ",").map(String.init)
        let modes = option("--modes", "cold,prefetched").split(separator: ",").map(String.init)
        let repeats = max(1, min(10, Int(option("--runs", "1")) ?? 1))
        let resultPosition = max(1, Int(option("--result-position", "1")) ?? 1)
        guard ["fresh", "shared"].contains(session), !ids.isEmpty, !modes.isEmpty, ids.allSatisfy(Track.validID), ["standard", "hls", "lean"].contains(profile),
              modes.allSatisfy({ ["cold", "prefetched", "search-click-1s"].contains($0) }) else {
            throw PlayerError(message: "Invalid benchmark options")
        }
        let cache = output.deletingLastPathComponent().appendingPathComponent("extractor-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        var rows: [[String: Any]] = []
        var sharedSource: YouTubeClient?
        func save() throws {
            let report: [String: Any] = [
                "date": ISO8601DateFormatter().string(from: Date()), "profile": profile,
                "label": option("--label", "current"),
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "resultPosition": resultPosition, "session": session,
                "endpoint": "AVPlayer playing with media time >= 20 ms; 5 ms polling. Does not measure acoustic output latency or remove silence in the recording.",
                "warmup": "prefetched waits for URL resolution plus 2 seconds; search-click-1s clicks 1 second after results appear. Cold uses a new resolver; extractor disk cache is retained.",
                "samples": rows
            ]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        }
        try save()
        print("Motif playback benchmark: \(profile). Audio will play briefly at 15% volume.")
        fflush(stdout)
        for run in 1...repeats {
            for id in ids {
                for mode in modes {
                    let suite = "motif-benchmark-" + UUID().uuidString
                    let defaults = UserDefaults(suiteName: suite)!
                    let client = BenchmarkClient(tools: tools, cache: cache, profile: profile, sharedSource: sharedSource)
                    if session == "shared" { sharedSource = client.source }
                    let track = Track(id: id, title: id, artist: "Benchmark", duration: 0, isLive: false)
                    client.track = track
                    client.resultPosition = resultPosition
                    client.alternatives = ids.filter { $0 != id }.map {
                        Track(id: $0, title: $0, artist: "Benchmark", duration: 0, isLive: false)
                    }
                    let store = PlayerStore(client: client, defaults: defaults, enableMediaControls: false, enablePreloading: true)
                    store.volume = 0.15
                    defer { store.shutdown(); defaults.removePersistentDomain(forName: suite) }
                    let began = clock
                    if mode != "cold" {
                        store.search("benchmark")
                        if mode == "prefetched" {
                            while client.resolvedAt == nil && clock - began < 70 { tick() }
                            if client.extractionError == nil { wait(2) }
                        } else { wait(1) }
                    }
                    let selected = clock
                    var row: [String: Any] = ["track": id, "mode": mode, "run": run, "prefetchMs": (selected - began) * 1000]
                    if let error = client.extractionError {
                        row["error"] = error
                    } else {
                        store.startMix(from: track)
                        var firstPlayback: Double?
                        var ready: Double?
                        var observedItems: [AVPlayerItem] = []
                        var waitingReasons = Set<String>()
                        var maximumBufferedSeconds = 0.0
                        while clock - selected < 75 {
                            if let item = store.player.currentItem {
                                if !observedItems.contains(where: { $0 === item }) { observedItems.append(item) }
                                maximumBufferedSeconds = max(maximumBufferedSeconds, item.loadedTimeRanges.reduce(0) { $0 + $1.timeRangeValue.duration.seconds })
                            }
                            if let reason = store.player.reasonForWaitingToPlay { waitingReasons.insert(reason.rawValue) }
                            if ready == nil, store.player.currentItem?.status == .readyToPlay { ready = clock }
                            if store.player.timeControlStatus == .playing, store.player.currentTime().seconds >= 0.02 {
                                firstPlayback = clock; break
                            }
                            if !store.loading && !store.message.isEmpty { break }
                            tick()
                        }
                        row["elapsedMs"] = (clock - selected) * 1000
                        row["waitingReasons"] = waitingReasons.sorted()
                        row["maximumBufferedSeconds"] = maximumBufferedSeconds
                        row["itemStatuses"] = observedItems.map { $0.status.rawValue }
                        row["nativeErrors"] = observedItems.compactMap { $0.error as NSError? }.map { "\($0.domain):\($0.code)" }
                        row["streamErrors"] = observedItems.flatMap { $0.errorLog()?.events ?? [] }.map { "\($0.errorDomain):\($0.errorStatusCode)" }
                        if let firstPlayback {
                            row["selectionToPlaybackMs"] = (firstPlayback - selected) * 1000
                            var stalled = 0.0
                            var last = clock
                            let end = clock + 1
                            while clock < end {
                                tick(); let current = clock
                                if store.player.timeControlStatus != .playing { stalled += current - last }
                                last = current
                            }
                            row["stallMsInNextSecond"] = stalled * 1000
                        } else { row["error"] = client.extractionError ?? (store.message.isEmpty ? "Playback timed out" : store.message) }
                        if let ready { row["selectionToReadyMs"] = (ready - selected) * 1000 }
                    }
                    if let start = client.startedAt, let resolved = client.resolvedAt {
                        row["resolutionMs"] = (resolved - start) * 1000
                        row["selectionToStreamMs"] = max(0, resolved - selected) * 1000
                    }
                    row["resolutionRequests"] = client.requests
                    row["extractorRequests"] = client.extractorRequests
                    row["resolutionEvents"] = client.events
                    rows.append(row); try save()
                    if let ms = row["selectionToPlaybackMs"] as? Double {
                        print(String(format: "%@ %@ run %d: %.0f ms to playback", id, mode, run, ms))
                    } else { print("\(id) \(mode) run \(run): FAILED \(row["error"] ?? "Unknown error")") }
                    fflush(stdout)
                    store.shutdown()
                    wait(0.25)
                }
            }
        }
        print("Report: \(output.path)")
    }
}
