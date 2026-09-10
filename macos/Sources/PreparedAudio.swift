import AVFoundation

// Keep a paused, prerolled player so selection can use the same decoder and
// buffered audio. Preparing asset metadata alone leaves that work on the click.
final class PreparedAudio {
    let asset: AVURLAsset
    private var preparedPlayer: AVPlayer?
    private var statusObserver: NSKeyValueObservation?
    private var prerollStarted = false
    private(set) var isPrerolled = false
    private var claimed = false

    init(url: URL, preload: Bool) {
        asset = AVURLAsset(url: url)
        if preload { preparePlayback() }
    }
    private func makePlayer() -> AVPlayer {
        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: [])
        item.preferredForwardBufferDuration = 2
        return AVPlayer(playerItem: item)
    }
    func preparePlayback() {
        guard preparedPlayer == nil else { return }
        let player = makePlayer()
        preparedPlayer = player; prerollStarted = false; isPrerolled = false
        statusObserver = player.observe(\.status, options: [.initial, .new]) { [weak self, weak player] _, _ in
            DispatchQueue.main.async {
                guard let self, let player, self.preparedPlayer === player,
                      player.status == .readyToPlay, !self.prerollStarted else { return }
                self.prerollStarted = true
                // Preroll requires a ready player at rate zero. It does not play
                // muted audio or advance the track in the background.
                player.preroll(atRate: 1) { [weak self, weak player] ready in
                    DispatchQueue.main.async {
                        guard let self, let player, self.preparedPlayer === player else { return }
                        self.isPrerolled = ready
                    }
                }
            }
        }
    }
    func takePlayer() -> AVPlayer {
        claimed = true
        let player = preparedPlayer ?? makePlayer()
        preparedPlayer = nil; statusObserver = nil
        player.cancelPendingPrerolls()
        isPrerolled = false
        return player
    }
    func claim() -> AVURLAsset {
        claimed = true
        return asset
    }
    func discard() {
        // A cache eviction must never interrupt the asset now being played.
        discardPreroll()
        if !claimed { asset.cancelLoading() }
    }
    func discardPreroll() {
        statusObserver = nil
        let player = preparedPlayer
        preparedPlayer = nil; isPrerolled = false
        player?.cancelPendingPrerolls()
        player?.pause(); player?.replaceCurrentItem(with: nil)
    }
    deinit { discard() }
}
