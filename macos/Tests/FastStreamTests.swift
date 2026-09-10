import Foundation

@main struct FastStreamTests {
    static let track = Track(id: "abcdefghijk", title: "Test", artist: "Test", duration: 10, isLive: false)
    static let home = Data(#"ytcfg.set({"INNERTUBE_CONTEXT":{"client":{"visitorData":"anonymous-test-context"}}});"#.utf8)
    static let playlist = Data("""
    #EXTM3U
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="233",DEFAULT=YES,URI="low.m3u8"
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="234",NAME="Default, high",DEFAULT=YES,URI="high.m3u8"
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="dubbed",DEFAULT=NO,URI="dubbed.m3u8"
    #EXT-X-STREAM-INF:RESOLUTION=1920x1080
    video.m3u8
    """.utf8)
    static func response(id: String = track.id, status: String = "OK", url: String = "https://manifest.googlevideo.com/master.m3u8") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["playabilityStatus": ["status": status],
            "videoDetails": ["videoId": id], "streamingData": ["hlsManifestUrl": url]])
    }
    static func rejected(_ body: () throws -> Void) {
        do { try body(); fatalError("Invalid stream response was accepted") } catch {}
    }
    static func main() throws {
        let visitor = try FastStreamResolver.visitor(from: home)
        precondition(visitor == "anonymous-test-context")
        let base = URL(string: "https://manifest.googlevideo.com/master.m3u8")!
        let audioURL = try FastStreamResolver.audioURL(from: playlist, base: base)
        precondition(audioURL.absoluteString == "https://manifest.googlevideo.com/high.m3u8")
        rejected { _ = try FastStreamResolver.manifest(from: response(status: "LOGIN_REQUIRED"), trackID: track.id) }
        rejected { _ = try FastStreamResolver.manifest(from: response(id: "lmnopqrstuv"), trackID: track.id) }
        rejected { _ = try FastStreamResolver.manifest(from: response(url: "https://googlevideo.com.example.org/audio"), trackID: track.id) }
        rejected { _ = try FastStreamResolver.audioURL(from: Data("#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=1920x1080\nvideo.m3u8".utf8), base: base) }
        rejected { _ = try FastStreamResolver.visitor(from: Data("consent required".utf8)) }
        var failure: Error?
        var finished = false
        Task { @MainActor in
            do { try await exerciseRequests() } catch { failure = error }
            finished = true
        }
        let deadline = Date().addingTimeInterval(8)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        precondition(finished, "Fast stream tests timed out")
        if let failure { throw failure }
        print("PASS: shared public context, audio-only selection, response validation, fallback and cancellation")
    }
    @MainActor static func exerciseRequests() async throws {
        var homes = 0, players = 0, manifests = 0
        let resolver = FastStreamResolver { request in
            if request.url?.path == "/" { homes += 1; return home }
            if request.url?.path == "/youtubei/v1/player" {
                players += 1
                precondition(request.httpMethod == "POST")
                precondition(request.value(forHTTPHeaderField: "X-Goog-Visitor-Id") == "anonymous-test-context")
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                precondition(body["videoId"] as? String == track.id)
                return try response()
            }
            manifests += 1; return playlist
        }
        async let a = resolver.stream(track)
        async let b = resolver.stream(track)
        let urls = try await [a, b]
        precondition(urls.allSatisfy { $0.lastPathComponent == "high.m3u8" })
        precondition(homes == 1 && players == 2 && manifests == 2, "Concurrent selections must share one context request")

        let tools = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tools) }
        let executable = tools.appendingPathComponent("yt-dlp")
        try "#!/bin/sh\nprintf '%s' '{\"url\":\"https://fallback.googlevideo.com/audio.m3u8\"}'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let unavailable = FastStreamResolver { _ in throw URLError(.cannotConnectToHost) }
        let client = YouTubeClient(tools: tools, cacheDirectory: tools, fastResolver: unavailable)
        let fallbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            _ = client.stream(track) { continuation.resume(with: $0) }
        }
        precondition(fallbackURL.host == "fallback.googlevideo.com", "A fast-path failure must use the bundled extractor")

        let slow = FastStreamResolver { request in
            try await Task.sleep(nanoseconds: 50_000_000)
            if request.url?.path == "/" { return home }
            return try response()
        }
        let cancellingClient = YouTubeClient(tools: tools, cacheDirectory: tools, fastResolver: slow)
        var delivered = false
        let token = cancellingClient.stream(track) { _ in delivered = true }
        token.cancel()
        try await Task.sleep(nanoseconds: 150_000_000)
        precondition(!delivered, "Cancelled selections must not deliver a stream or fallback result")
    }
}
