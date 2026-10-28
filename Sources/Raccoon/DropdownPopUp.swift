import AppKit

/// A pop-up that opens as a dropdown (design-system §6 Dropdown placement): the menu hangs 4 pt
/// below the control with its left edge on the control's, and the selected item stays checked.
/// AppKit's own pop-up puts the selected item over the control instead. Mouse, Space and the
/// menu bar's `performClick` all come through here.
class DropdownPopUp: NSPopUpButton {
    override func mouseDown(with event: NSEvent) { open() }

    override func performClick(_ sender: Any?) { open() }

    private func open() {
        guard isEnabled, let menu else { return }
        let gap: CGFloat = 4
        // A menu's origin is its top-left corner; below the control is down in either coordinate system.
        let y = isFlipped ? bounds.height + gap : -gap
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: self)
    }
}
