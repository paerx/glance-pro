import AppKit

@MainActor final class VTAHotkey {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    var onCancel: (() -> Void)?
    var keyCode: UInt16 = 97 // F6
    var modifiers: UInt64 = 0
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held = false

    func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    Unmanaged<VTAHotkey>.fromOpaque(info).takeUnretainedValue().handle(type, event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; source = nil
        if held { held = false; onCancel?() }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if held { held = false; onCancel?() }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(keyCode) else { return Unmanaged.passUnretained(event) }
        if type == .keyUp, held { held = false; onUp?(); return nil }
        let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        guard type == .keyDown, event.flags.intersection(mask).rawValue == modifiers else { return Unmanaged.passUnretained(event) }
        guard !LockMonitor.isScreenActuallyLocked() else { return Unmanaged.passUnretained(event) }
        if !held { held = true; onDown?() }
        return nil
    }
}
