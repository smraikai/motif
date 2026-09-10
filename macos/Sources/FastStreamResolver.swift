import Foundation

// Uses the public VISIONOS client supported by our pinned yt-dlp release.
// Visitor context and signed URLs stay in memory. yt-dlp remains the fallback
// when YouTube changes this response or a track needs another supported client.
final class FastStreamResolver {
    typealias Transport = (URLRequest) async throws -> Data
    private let transport: Transport
    private var context: Task<String, Error>?
    private var contextExpires = Date.distantPast
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    init(transport: Transport? = nil) {
        if let transport { self.transport = transport }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 2
            configuration.timeoutIntervalForResource = 3
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            self.transport = { request in
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                    throw PlayerError(message: "The fast stream request was unavailable.")
                }
                return data
            }
        }
    }
    // Called on the main thread. Search gives this request time to finish before
    // results arrive, and subsequent selections share the connection and context.
    func prepare() {
        guard context == nil || contextExpires < Date() else { return }
        contextExpires = Date().addingTimeInterval(10 * 60)
        let transport = transport
        context = Task { @MainActor [weak self] in
            do {
                var request = URLRequest(url: URL(string: "https://www.youtube.com/")!)
                request.timeoutInterval = 2
                request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
                return try Self.visitor(from: await transport(request))
            } catch {
                self?.contextExpires = Date().addingTimeInterval(30)
                throw error
            }
        }
    }
    @MainActor func stream(_ track: Track) async throws -> URL {
        prepare()
        let deadline = Date().addingTimeInterval(2)
        let visitor = try await context!.value
        try Task.checkCancellation()
        var request = try Self.request(URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!, deadline: deadline)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("101", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.02", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": ["client": ["clientName": "VISIONOS", "clientVersion": "1.02",
                "deviceMake": "Apple", "deviceModel": "RealityDevice17,1", "userAgent": Self.userAgent,
                "osName": "visionOS", "osVersion": "26.5.23O471", "hl": "en", "timeZone": "UTC", "utcOffsetMinutes": 0] as [String: Any]],
            "videoId": track.id,
            "playbackContext": ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]],
            "contentCheckOk": true, "racyCheckOk": true
        ])
        let manifest = try Self.manifest(from: await transport(request), trackID: track.id)
        try Task.checkCancellation()
        let playlist = try await transport(Self.request(manifest, deadline: deadline))
        try Task.checkCancellation()
        return try Self.audioURL(from: playlist, base: manifest)
    }
    private static func request(_ url: URL, deadline: Date) throws -> URLRequest {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw URLError(.timedOut) }
        var request = URLRequest(url: url)
        request.timeoutInterval = remaining
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
    static func visitor(from data: Data) throws -> String {
        guard let page = String(data: data, encoding: .utf8),
              let match = page.range(of: #"ytcfg\.set\s*\(\s*\{.+?\}\s*\)\s*;"#, options: .regularExpression),
              let start = page[match].firstIndex(of: "{"), let end = page[match].lastIndex(of: "}"),
              let bytes = String(page[start...end]).data(using: .utf8),
              let config = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw PlayerError(message: "YouTube's public playback context was unavailable.")
        }
        let client = (config["INNERTUBE_CONTEXT"] as? [String: Any])?["client"] as? [String: Any]
        guard let value = (config["VISITOR_DATA"] ?? client?["visitorData"]) as? String, !value.isEmpty else {
            throw PlayerError(message: "YouTube's public playback context was empty.")
        }
        return value
    }
    static func manifest(from data: Data, trackID: String) throws -> URL {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (object?["playabilityStatus"] as? [String: Any])?["status"] as? String == "OK",
              (object?["videoDetails"] as? [String: Any])?["videoId"] as? String == trackID,
              let raw = (object?["streamingData"] as? [String: Any])?["hlsManifestUrl"] as? String,
              let url = mediaURL(raw) else {
            throw PlayerError(message: "This track needs the fallback stream resolver.")
        }
        return url
    }
    static func audioURL(from data: Data, base: URL) throws -> URL {
        let text = String(data: data, encoding: .utf8) ?? ""
        guard text.hasPrefix("#EXTM3U") else { throw PlayerError(message: "Invalid audio playlist.") }
        let audio = text.components(separatedBy: .newlines).filter {
            $0.hasPrefix("#EXT-X-MEDIA:") && $0.contains("TYPE=AUDIO") && $0.contains("DEFAULT=YES")
        }
        // 234 is YouTube's high quality AAC audio group; 233 is its low quality group.
        let ordered = audio.filter { $0.contains("GROUP-ID=\"234\"") } + audio
        for line in ordered {
            guard let range = line.range(of: #"URI="[^"]+""#, options: .regularExpression) else { continue }
            let raw = String(line[range].dropFirst(5).dropLast())
            if let url = URL(string: raw, relativeTo: base)?.absoluteURL, mediaURL(url.absoluteString) != nil { return url }
        }
        throw PlayerError(message: "No default audio-only stream was available.")
    }
    private static func mediaURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", let host = url.host,
              host == "googlevideo.com" || host.hasSuffix(".googlevideo.com") else { return nil }
        return url
    }
}
