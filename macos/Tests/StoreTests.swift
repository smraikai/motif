import Foundation

final class FakeClient: MusicClient {
    var available = true
    var searches: [(Result<[Track], Error>) -> Void] = []
    var mixes: [(Result<[Track], Error>) -> Void] = []
    var streams: [(Result<URL, Error>) -> Void] = []
    func search(_ query: String, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction {
        searches.append(completion); return Extraction()
    }
    func mix(_ seed: Track, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction {
        mixes.append(completion); return Extraction()
    }
    func stream(_ track: Track, completion: @escaping (Result<URL, Error>) -> Void) -> Extraction {
        streams.append(completion); return Extraction()
    }
}

@main struct StoreTests {
    static func main() {
        let suite = "youtube-music-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = FakeClient()
        let store = PlayerStore(client: client, defaults: defaults, enableMediaControls: false, enablePreloading: false)
        defer { store.shutdown() }
        let a = Track(id: "abcdefghijk", title: "A", artist: "Test", duration: 120, isLive: false)
        let b = Track(id: "lmnopqrstuv", title: "B", artist: "Test", duration: 120, isLive: false)
        let c = Track(id: "12345678901", title: "C", artist: "Test", duration: 120, isLive: false)
        store.search("old"); store.search("new")
        client.searches[1](.success([b]))
        client.searches[0](.success([a]))
        precondition(store.results == [b], "A stale search replaced the latest search")
        store.select(0)
        precondition(store.current == b && !store.showingSearch)
        precondition(client.mixes.isEmpty, "Audio extraction must not compete with building a mix")
        store.pause() // Pausing releases the pending background mix.
        store.startMix(from: a)
        precondition(client.mixes.count == 1, "The replacement seed must wait for its audio")
        client.mixes[0](.success([b, c]))
        precondition(store.queue.tracks == [a], "An old mix replaced a new queue")
        store.pause()
        client.mixes[1](.success([a, b, c, b]))
        precondition(store.queue.tracks == [a, b, c])
        // A stale failed resolver must not skip the user's newly selected track.
        client.streams[0](.failure(PlayerError(message: "old failure")))
        precondition(store.current == a)
        store.search("another search")
        precondition(store.current == a && store.showingSearch)
        client.searches[2](.success([c]))
        precondition(store.queue.tracks == [a, b, c] && store.results == [c])
        store.pause()
        precondition(!store.playing && !store.loading)
        // Consecutive extraction failures stop after three attempts.
        client.streams[1](.failure(PlayerError(message: "unavailable")))
        client.streams[2](.failure(PlayerError(message: "unavailable")))
        client.streams[3](.failure(PlayerError(message: "unavailable")))
        precondition(!store.message.isEmpty && !store.loading)
        let restored = PlayerStore(client: FakeClient(), defaults: defaults, enableMediaControls: false, enablePreloading: false)
        precondition(restored.current == c && !restored.playing)
        restored.shutdown()
        print("PASS: stale search/mix/stream rejection, queue preservation, failure cap, paused restoration")
    }
}
