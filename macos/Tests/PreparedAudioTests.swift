import AVFoundation
import Foundation

@main struct PreparedAudioTests {
    static func main() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: file) }
        var wav = Data()
        func text(_ value: String) { wav.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36 + 160000)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(8000)); number(UInt32(16000)); number(UInt16(2)); number(UInt16(16))
        text("data"); number(UInt32(160000)); wav.append(Data(count: 160000))
        try wav.write(to: file)

        let prepared = PreparedAudio(url: file, preload: true)
        let claimed = prepared.claim()
        prepared.discard() // Evicting a cached URL must not cancel active media.
        precondition(claimed === prepared.asset)
        var result: Result<Bool, Error>?
        Task { @MainActor in
            do {
                let (playable, tracks) = try await claimed.load(.isPlayable, .tracks)
                result = .success(playable && !tracks.isEmpty)
            } catch { result = .failure(error) }
        }
        let deadline = Date().addingTimeInterval(5)
        while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        guard let result else { fatalError("Native media preparation timed out") }
        let playable = try result.get()
        precondition(playable, "The prepared native asset must remain playable after cache eviction")

        let primed = PreparedAudio(url: file, preload: true)
        let prerollDeadline = Date().addingTimeInterval(8)
        while !primed.isPrerolled && Date() < prerollDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        precondition(primed.isPrerolled, "Native audio must be buffered before selection")
        let player = primed.takePlayer()
        precondition(player.rate == 0, "Preroll must leave playback paused")
        // The item status notification can follow the player's preroll callback.
        let readyDeadline = Date().addingTimeInterval(2)
        while player.currentItem?.status != .readyToPlay && Date() < readyDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        precondition(player.currentItem?.status == .readyToPlay && player.rate == 0)
        precondition(player.currentTime().seconds < 0.02, "Prefetch must not advance playback")
        primed.discard()
        let start = ProcessInfo.processInfo.systemUptime
        player.playImmediately(atRate: 1)
        let playbackDeadline = Date().addingTimeInterval(5)
        while player.currentTime().seconds < 0.02 && Date() < playbackDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        precondition(player.timeControlStatus == .playing && player.currentTime().seconds >= 0.02,
                     "Claimed playback must survive cache eviction")
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let repeatPlayer = primed.takePlayer()
        precondition(repeatPlayer !== player && repeatPlayer.currentTime().seconds < 0.02,
                     "Replaying a cached track must create a fresh item at its beginning")
        player.pause(); player.replaceCurrentItem(with: nil)
        repeatPlayer.replaceCurrentItem(with: nil)
        print(String(format: "PASS: native preroll, silent preparation, playback handoff, eviction safety, replay reset (local fixture %.0f ms)", elapsed * 1000))
    }
}
