import Foundation
import CoreGraphics

enum PopoverHitTest {
    // The icon is inside the interaction region: its mouse-up action owns the
    // toggle. Only a click outside BOTH regions should dismiss on mouse-down.
    static func isOutside(_ point: NSPoint, icon: NSRect, popup: NSRect) -> Bool {
        !icon.contains(point) && !popup.contains(point)
    }
}
