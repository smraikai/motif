import AppKit
import AVFoundation
import Foundation

private final class PlaybackClient: MusicClient {
    var available = true
    var streams: [(Result<URL, Error>) -> Void] = []
    func search(_ query: String, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction { Extraction() }
    func mix(_ seed: Track, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction { Extraction() }
    func stream(_ track: Track, completion: @escaping (Result<URL, Error>) -> Void) -> Extraction {
        streams.append(completion); return Extraction()
    }
}

@main struct PlaybackTests {
    static func wait(_ condition: () -> Bool) {
        let end = Date().addingTimeInterval(5)
        while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        precondition(condition(), "Native playback state timed out")
    }
    static func main() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: file) }
        var wav = Data()
        func text(_ value: String) { wav.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian; withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36 + 160000)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(8000)); number(UInt32(16000)); number(UInt16(2)); number(UInt16(16))
        text("data"); number(UInt32(160000)); wav.append(Data(count: 160000)); try wav.write(to: file)
        let suite = "motif-native-playback-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = PlaybackClient()
        let store = PlayerStore(client: client, defaults: defaults, enableMediaControls: false, enablePreloading: false)
        defer { store.shutdown() }
        let a = Track(id: "abcdefghijk", title: "A", artist: "Test", duration: 10, isLive: false)
        let b = Track(id: "lmnopqrstuv", title: "B", artist: "Test", duration: 10, isLive: false)
        store.volume = 0.23
        store.startMix(from: a); client.streams[0](.success(file))
        wait { store.playing && store.player.currentTime().seconds > 0.02 }
        let former = store.player
        store.startMix(from: b)
        store.pause() // Resolving the new track after this must not start audio.
        client.streams[1](.success(file))
        wait { store.player.currentItem?.status == .readyToPlay }
        precondition(store.player !== former && former.currentItem == nil && former.rate == 0)
        precondition(store.player.volume == 0.23 && store.player.rate == 0 && !store.playing && !store.loading)
        store.resume()
        wait { store.playing && store.player.currentTime().seconds > 0.02 }
        store.pause()
        precondition(store.player.rate == 0 && !store.loading)
        store.startMix(from: a) // Cache hit creates another fresh player/item.
        wait { store.playing && store.current == a && store.player.currentTime().seconds > 0.02 }
        precondition(client.streams.count == 2, "Replaying a cached track must not extract again")
        precondition(store.player.currentTime().seconds < 1, "A cached replay must restart at the beginning")
        print("PASS: native player handoff, old-player shutdown, volume, pause while resolving, resume, cached replay")
    }
}
