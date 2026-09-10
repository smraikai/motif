import AVFoundation

// Keep the opened media asset with its resolved URL so a later click can reuse
// the connection and metadata work. No second player or audio output is created.
final class PreparedAudio {
    let asset: AVURLAsset
    private var preparation: Task<Void, Never>?
    private var claimed = false

    init(url: URL, preload: Bool) {
        asset = AVURLAsset(url: url)
        if preload {
            let asset = self.asset
            preparation = Task {
                _ = try? await asset.load(.isPlayable, .tracks)
            }
        }
    }
    func claim() -> AVURLAsset {
        claimed = true
        return asset
    }
    func discard() {
        // A cache eviction must never interrupt the asset now being played.
        if !claimed { preparation?.cancel(); asset.cancelLoading() }
        preparation = nil
    }
    deinit { discard() }
}
