import Foundation

final class ResolverClient: MusicClient {
    struct Request {
        let track: Track
        let token: Extraction
        let complete: (Result<URL, Error>) -> Void
    }
    var available = true
    var requests: [Request] = []
    func search(_ query: String, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction { Extraction() }
    func mix(_ seed: Track, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction { Extraction() }
    func stream(_ track: Track, completion: @escaping (Result<URL, Error>) -> Void) -> Extraction {
        let token = Extraction()
        requests.append(Request(track: track, token: token, complete: completion))
        return token
    }
}

@main struct StreamResolverTests {
    static func tick() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    static func main() {
        let a = Track(id: "abcdefghijk", title: "A", artist: "Test", duration: 120, isLive: false)
        let b = Track(id: "lmnopqrstuv", title: "B", artist: "Test", duration: 120, isLive: false)
        let c = Track(id: "12345678901", title: "C", artist: "Test", duration: 120, isLive: false)
        var date = Date(timeIntervalSince1970: 2_000_000_000)
        let url = URL(string: "https://audio.invalid/song.m4a?expire=2000000600")!
        let client = ResolverClient()
        let resolver = StreamResolver(client: client, preloadAssets: false, now: { date })
        var deliveries = 0
        var openedAudio: PreparedAudio?
        resolver.prepare([a, b, c])
        precondition(client.requests.count == 2 && client.requests[0].track == a && client.requests[1].track == b,
                     "Prepare the two likely choices together, without extracting the whole result list")
        let click = resolver.resolve(a) { result in
            precondition((try? result.get().url) == url); deliveries += 1
            openedAudio = try? result.get().audio
        }
        precondition(client.requests.count == 2, "Clicking a warming track must reuse its extractor")
        precondition(client.requests[1].token.isCancelled, "Playback must take priority over unrelated preparation")
        resolver.prepare([])
        precondition(!client.requests[0].token.isCancelled, "Cancelling warm-up must preserve the click's subscription")
        client.requests[0].complete(.success(url))
        precondition(deliveries == 1)
        var reused = false
        _ = resolver.resolve(a) {
            reused = (try? $0.get().reused) == true
            precondition((try? $0.get().audio) === openedAudio, "Reuse the prepared media asset, not just its URL")
        }
        tick()
        precondition(reused && client.requests.count == 2, "A ready track must skip extraction entirely")
        let cancelledHit = resolver.resolve(a) { _ in fatalError("A cancelled cache hit was delivered") }
        cancelledHit.cancel(); tick()
        click.cancel()

        date = date.addingTimeInterval(541)
        _ = resolver.resolve(a) { _ in }
        precondition(client.requests.count == 3, "Refresh before the signed URL expires")
        resolver.shutdown()
        client.requests[2].complete(.success(url))

        let secondClient = ResolverClient()
        let second = StreamResolver(client: secondClient, preloadAssets: false)
        second.prepare([a, b, c])
        precondition(secondClient.requests.count == 2 && secondClient.requests[1].track == b)
        // The second result can finish first; neither selection waits for the other.
        secondClient.requests[1].complete(.success(URL(string: "https://audio.invalid/b")!))
        secondClient.requests[0].complete(.success(URL(string: "https://audio.invalid/a")!))
        precondition(secondClient.requests.count == 2, "Don't resolve an entire search result list")
        second.invalidate(a)
        _ = second.resolve(a) { _ in }
        precondition(secondClient.requests.count == 3, "An invalidated URL must be fetched again")
        second.shutdown()

        let thirdClient = ResolverClient()
        let third = StreamResolver(client: thirdClient, preloadAssets: false)
        third.prepare([a]); third.prepare([b])
        precondition(thirdClient.requests[0].token.isCancelled)
        thirdClient.requests[0].complete(.success(url))
        _ = third.resolve(a) { _ in }
        precondition(thirdClient.requests.count == 3, "A cancelled warm-up cannot repopulate the cache")
        precondition(thirdClient.requests[1].token.isCancelled, "The chosen track takes priority over unrelated warm-up")
        third.shutdown()

        let live = Track(id: a.id, title: "Live", artist: "Test", duration: 0, isLive: true)
        let liveClient = ResolverClient()
        let liveResolver = StreamResolver(client: liveClient, preloadAssets: false)
        liveResolver.prepare([live])
        precondition(liveClient.requests.isEmpty)
        _ = liveResolver.resolve(live) { _ in }
        liveClient.requests[0].complete(.success(url))
        _ = liveResolver.resolve(live) { _ in }
        precondition(liveClient.requests.count == 2, "Never reuse a live stream snapshot")
        liveResolver.shutdown()

        let icon = NSRect(x: 500, y: 900, width: 24, height: 24)
        let popup = NSRect(x: 180, y: 440, width: 340, height: 460)
        precondition(!PopoverHitTest.isOutside(NSPoint(x: 510, y: 910), icon: icon, popup: popup),
                     "An icon mouse-down must leave the popup open for the click's close action")
        precondition(!PopoverHitTest.isOutside(NSPoint(x: 300, y: 600), icon: icon, popup: popup))
        precondition(PopoverHitTest.isOutside(NSPoint(x: 50, y: 600), icon: icon, popup: popup))
        print("PASS: prefetch reuse, zero-extraction cache hits, URL expiry, shared cancellation, warm-up priority, live streams, outside-click exclusion")
    }
}
