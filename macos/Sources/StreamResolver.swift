import Foundation

// Main-thread coordinator. URLs remain in memory only and expire before YouTube's
// signed URL does. A click can join a warm-up instead of launching another extractor.
final class StreamResolver {
    struct Stream {
        let url: URL
        let reused: Bool
        let audio: PreparedAudio
    }
    private struct Entry {
        let url: URL
        let expires: Date
        var used: Date
        let audio: PreparedAudio
    }
    private final class Pending {
        let id = UUID()
        var callbacks: [UUID: (Result<Stream, Error>) -> Void] = [:]
        var job: Extraction?
    }
    private let client: MusicClient
    private let now: () -> Date
    private let preloadAssets: Bool
    private var cache: [String: Entry] = [:]
    private var pending: [String: Pending] = [:]
    private var candidates: [Track] = []
    private var warming: (id: String, token: Extraction)?
    init(client: MusicClient, preloadAssets: Bool = true, now: @escaping () -> Date = Date.init) {
        self.client = client; self.preloadAssets = preloadAssets; self.now = now
    }

    func resolve(_ track: Track, completion: @escaping (Result<Stream, Error>) -> Void) -> Extraction {
        candidates = []
        if warming?.id != track.id { stopWarmup() }
        return request(track, completion: completion)
    }
    func prepare(_ tracks: [Track]) {
        var seen = Set<String>()
        candidates = Array(tracks.filter { !$0.isLive && seen.insert($0.id).inserted }.prefix(2))
        if let warming, !candidates.contains(where: { $0.id == warming.id }) { stopWarmup() }
        warmNext()
    }
    func invalidate(_ track: Track) { cache.removeValue(forKey: track.id) }
    func shutdown() {
        candidates = []; stopWarmup()
        let jobs = pending.values.compactMap(\.job)
        pending.removeAll(); cache.removeAll()
        jobs.forEach { $0.cancel() }
    }
    private func request(_ track: Track, completion: @escaping (Result<Stream, Error>) -> Void) -> Extraction {
        let subscriber = UUID()
        let token = Extraction { [weak self] in
            let remove = { [weak self] in self?.remove(subscriber, from: track.id) }
            if Thread.isMainThread { remove() } else { DispatchQueue.main.async { remove() } }
        }
        cache = cache.filter { $0.value.expires > now() }
        if !track.isLive, var entry = cache[track.id] {
            entry.used = now(); cache[track.id] = entry
            let url = entry.url
            DispatchQueue.main.async {
                if !token.isCancelled { completion(.success(Stream(url: url, reused: true, audio: entry.audio))) }
            }
            return token
        }
        let delivery: (Result<Stream, Error>) -> Void = { result in
            if !token.isCancelled { completion(result) }
        }
        if let existing = pending[track.id] {
            existing.callbacks[subscriber] = delivery
            return token
        }
        let request = Pending()
        request.callbacks[subscriber] = delivery
        pending[track.id] = request
        request.job = client.stream(track) { [weak self, weak request] result in
            guard let self, let request, self.pending[track.id]?.id == request.id else { return }
            self.pending.removeValue(forKey: track.id)
            let response = result.map { url -> Stream in
                let audio = PreparedAudio(url: url, preload: self.preloadAssets && !track.isLive && self.warming?.id == track.id)
                if !track.isLive { self.remember(url, audio: audio, for: track.id) }
                return Stream(url: url, reused: false, audio: audio)
            }
            for callback in request.callbacks.values { callback(response) }
        }
        return token
    }
    private func remember(_ url: URL, audio: PreparedAudio, for id: String) {
        let date = now()
        let signedExpiry = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "expire" })?.value.flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        let expires = min(date.addingTimeInterval(15 * 60), signedExpiry?.addingTimeInterval(-60) ?? date.addingTimeInterval(5 * 60))
        guard expires > date else { return }
        cache[id] = Entry(url: url, expires: expires, used: date, audio: audio)
        while cache.count > 12, let oldest = cache.min(by: { $0.value.used < $1.value.used })?.key {
            cache.removeValue(forKey: oldest)
        }
    }
    private func remove(_ subscriber: UUID, from id: String) {
        guard let request = pending[id] else { return }
        request.callbacks.removeValue(forKey: subscriber)
        if request.callbacks.isEmpty {
            pending.removeValue(forKey: id)
            request.job?.cancel()
        }
    }
    private func stopWarmup() {
        let token = warming?.token
        warming = nil
        token?.cancel()
    }
    private func warmNext() {
        guard warming == nil else { return }
        while let candidate = candidates.first {
            candidates.removeFirst()
            if let entry = cache[candidate.id], entry.expires > now() { continue }
            let token = request(candidate) { [weak self] _ in
                guard let self, self.warming?.id == candidate.id else { return }
                self.warming = nil; self.warmNext()
            }
            warming = (candidate.id, token)
            break
        }
    }
}
