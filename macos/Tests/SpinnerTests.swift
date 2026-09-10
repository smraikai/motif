import AppKit

@main struct SpinnerTests {
    static func animatedLayer(_ layer: CALayer) -> CALayer? {
        if layer.animation(forKey: "spin") != nil { return layer }
        return layer.sublayers?.compactMap(animatedLayer).first
    }
    static func main() {
        _ = NSApplication.shared
        let spinner = ArtworkLoadingView(frame: NSRect(x: 0, y: 0, width: 144, height: 144))
        spinner.wantsLayer = true // The app places it inside layer-backed artwork.
        let window = NSWindow(contentRect: spinner.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = spinner
        for size: CGFloat in [144, 180] {
            window.setContentSize(NSSize(width: size, height: size))
            spinner.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            spinner.setLoading(true)
            guard let ringLayer = spinner.subviews.first?.layer,
                  let arc = animatedLayer(ringLayer) else { fatalError("Missing spinner animation") }
            spinner.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            guard let root = spinner.layer else { fatalError("Missing artwork layer") }
            arc.removeAnimation(forKey: "spin")
            // Sample the actual layer geometry at quarter turns. Rotating an
            // AppKit backing layer with its reset anchor point fails this check.
            for quarter in 0..<4 {
                arc.transform = CATransform3DMakeRotation(CGFloat(quarter) * .pi / 2, 0, 0, 1)
                let center = arc.convert(CGPoint(x: arc.bounds.midX, y: arc.bounds.midY), to: root)
                precondition(abs(center.x - spinner.bounds.midX) < 0.01 && abs(center.y - spinner.bounds.midY) < 0.01,
                             "The spinner must rotate in place, not orbit the artwork")
            }
            arc.transform = CATransform3DIdentity
            spinner.setLoading(false)
            spinner.setLoading(true)
            precondition(animatedLayer(ringLayer) != nil)
            spinner.setLoading(false)
            precondition(animatedLayer(ringLayer) == nil && spinner.isHidden)
        }
        print("PASS: fixed spinner center across rotation, resizing, stop, and restart")
    }
}
