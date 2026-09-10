import Foundation

struct Track: Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let duration: Double
    let isLive: Bool
    var url: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    var artworkURL: URL { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")! }
    var durationLabel: String { isLive ? "LIVE" : (duration > 0 ? clockTime(duration) : "") }

    static func validID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }

    static func parse(_ data: Data) throws -> [Track] {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let entries = object["entries"] as? [[String: Any]] ?? [object]
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let id = entry["id"] as? String, validID(id), seen.insert(id).inserted,
                  let title = entry["title"] as? String, !title.isEmpty,
                  title != "[Deleted video]", title != "[Private video]" else { return nil }
            return Track(id: id, title: title,
                         artist: entry["channel"] as? String ?? entry["uploader"] as? String ?? "YouTube",
                         duration: (entry["duration"] as? NSNumber)?.doubleValue ?? 0,
                         isLive: entry["live_status"] as? String == "is_live")
        }
    }
}

func clockTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
    return String(format: "%d:%02d", total / 60, total % 60)
}

struct QueueState: Codable {
    var tracks: [Track] = []
    var index = 0
    var current: Track? { tracks.indices.contains(index) ? tracks[index] : nil }
    mutating func advance(by offset: Int, wrap: Bool) -> Bool {
        guard !tracks.isEmpty else { return false }
        let next = index + offset
        guard wrap || tracks.indices.contains(next) else { return false }
        index = (next % tracks.count + tracks.count) % tracks.count
        return true
    }
    mutating func appendUnique(_ candidates: [Track]) {
        var seen = Set(tracks.map(\.id))
        tracks += candidates.filter { seen.insert($0.id).inserted }
        if tracks.count > 200 && index > 80 {
            let trim = min(index - 40, tracks.count - 200)
            tracks.removeFirst(trim)
            index -= trim
        }
    }
    var isValid: Bool { tracks.isEmpty || (tracks.indices.contains(index) && tracks.allSatisfy { Track.validID($0.id) }) }
}
