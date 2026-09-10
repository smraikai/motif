import AppKit

private final class SpinnerRing: NSView {
    let arc = CAShapeLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        arc.name = "spinner-arc"
        arc.fillColor = nil
        arc.strokeColor = PlayerTheme.accent.cgColor
        arc.lineWidth = 2.5
        arc.lineCap = .round
        arc.strokeStart = 1.0 / 12
        arc.strokeEnd = 5.0 / 6
        layer?.addSublayer(arc)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.bounds = bounds
        arc.position = CGPoint(x: bounds.midX, y: bounds.midY)
        arc.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        arc.path = CGPath(ellipseIn: bounds.insetBy(dx: 2, dy: 2), transform: nil)
        CATransaction.commit()
    }
    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 2, dy: 2)
        NSColor.white.withAlphaComponent(0.2).setStroke()
        let track = NSBezierPath(ovalIn: circle)
        track.lineWidth = 2.5; track.stroke()
    }
}

final class ArtworkLoadingView: NSView {
    private let ring = SpinnerRing(frame: .zero)
    private(set) var isAnimating = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(ring)
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("Buffering audio")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.4).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
    override func layout() {
        super.layout()
        ring.frame = NSRect(x: bounds.midX - 17, y: bounds.midY - 17, width: 34, height: 34)
    }
    func setLoading(_ loading: Bool) {
        guard loading != isAnimating else { return }
        isAnimating = loading
        isHidden = !loading
        if loading {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0; rotation.toValue = -2 * Double.pi
            rotation.duration = 0.85; rotation.repeatCount = .infinity
            // AppKit owns the backing layer's anchor point. Rotate our own
            // centered arc layer so layout cannot turn the spin into an orbit.
            ring.arc.add(rotation, forKey: "spin")
        } else {
            ring.arc.removeAnimation(forKey: "spin")
        }
    }
}
