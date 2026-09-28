//
//  NotchWindow.swift
//  glance
//
//  Borderless, transparent, click-through panel. All expansion/collapse occurs
//  inside a fixed host footprint. The controller restores that footprint only
//  if AppKit moves/resizes the window during display or lock-space transitions.
//

import AppKit

final class NotchWindow: NSPanel {
    /// Whether the panel may become key. Tracked separately from
    /// `ignoresMouseEvents`, which `NotchWindowController` flips on and off as
    /// the cursor moves over/away from the visible panel — tying key status to
    /// that would stop onboarding's text fields taking focus whenever the
    /// cursor happened to sit outside the panel.
    var acceptsKey = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Decorative by default — clicks pass through until a failed attempt is
        // waiting to be tapped for retry (see NotchWindowController.setInteractive).
        ignoresMouseEvents = true
    }

    // AppKit normally constrains panels below the menu bar when ordering/keying
    // them. This overlay deliberately occupies that area and anchors to frame.maxY.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Must become key while interactive or the tap-to-retry gesture never receives
    /// the click; never becomes main, so it doesn't take over as the app's primary window.
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}
