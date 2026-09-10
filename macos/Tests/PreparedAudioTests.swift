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
        text("RIFF"); number(UInt32(36 + 16000)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(8000)); number(UInt32(16000)); number(UInt16(2)); number(UInt16(16))
        text("data"); number(UInt32(16000)); wav.append(Data(count: 16000))
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
        print("PASS: native audio preparation, media tracks, asset reuse, eviction during playback preparation")
    }
}
