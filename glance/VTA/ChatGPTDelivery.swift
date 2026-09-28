import AppKit
import ApplicationServices

/// Uses named accessibility controls, never blind paste/Return into the front app.
/// No API key, clipboard replacement or browser query-string transport is used.
@MainActor enum ChatGPTDelivery {
    static func send(_ text: String) async throws {
        guard AXIsProcessTrusted() else { throw failure("Allow Accessibility for Glance first.") }
        let workspace = NSWorkspace.shared
        let url = workspace.urlForApplication(withBundleIdentifier: "com.openai.chat")
            ?? URL(fileURLWithPath: "/Applications/ChatGPT.app")
        guard let bundle = Bundle(url: url), ["com.openai.chat", "com.openai.codex"].contains(bundle.bundleIdentifier ?? "") else {
            throw failure("Install and sign in to the ChatGPT Mac app first.")
        }
        let app = try await workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.3)
        var created = false
        for _ in 0..<30 {
            try Task.checkCancellation()
            guard !LockMonitor.isScreenActuallyLocked() else { throw failure("Delivery stopped because the screen locked.") }
            // Match Chat-specific actions only; never create a Codex task instead.
            if let action = find(root, matching: { element in
                let role = string(element, kAXRoleAttribute)
                let title = string(element, kAXTitleAttribute)
                let description = string(element, kAXDescriptionAttribute)
                return [kAXButtonRole, kAXMenuItemRole].contains(role)
                    && ["New chat", "New Chat", "New conversation", "新聊天", "新建聊天", "新对话", "新建对话"].contains(title.isEmpty ? description : title)
                    && bool(element, kAXEnabledAttribute)
            }), AXUIElementPerformAction(action, kAXPressAction as CFString) == .success {
                created = true; break
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard created else { throw failure("Could not find ChatGPT's New chat action. Your transcript is kept in VTA settings.") }
        try await Task.sleep(for: .milliseconds(500))
        for _ in 0..<30 {
            try Task.checkCancellation()
            guard !LockMonitor.isScreenActuallyLocked() else { throw failure("Delivery stopped because the screen locked.") }
            if let editor = find(root, matching: { element in
                string(element, kAXRoleAttribute) == kAXTextAreaRole
                    && string(element, kAXValueAttribute).isEmpty
                    && bool(element, kAXEnabledAttribute)
            }) {
                let set = AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, text as CFString)
                if set == .success, string(editor, kAXValueAttribute) == text {
                    for _ in 0..<20 {
                        try Task.checkCancellation()
                        guard !LockMonitor.isScreenActuallyLocked() else { throw failure("Delivery stopped because the screen locked.") }
                        if let send = find(root, matching: { element in
                            let label = string(element, kAXDescriptionAttribute)
                            let title = string(element, kAXTitleAttribute)
                            return string(element, kAXRoleAttribute) == kAXButtonRole
                                && ["Send", "Send message", "Send Message", "Send prompt", "发送", "发送消息"].contains(label.isEmpty ? title : label)
                                && bool(element, kAXEnabledAttribute)
                        }), AXUIElementPerformAction(send, kAXPressAction as CFString) == .success {
                            for _ in 0..<20 {
                                try await Task.sleep(for: .milliseconds(150))
                                if let current = value(editor, kAXValueAttribute) as? String, current.isEmpty { return }
                            }
                            throw failure("Could not confirm delivery. Check ChatGPT before sending again.")
                        }
                        try await Task.sleep(for: .milliseconds(150))
                    }
                    throw failure("Text is in ChatGPT, but automatic sending is unavailable. Press Send in ChatGPT.")
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw failure("Could not fill the new ChatGPT chat. Your transcript is kept in VTA settings.")
    }

    private static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    private static func string(_ element: AXUIElement, _ key: String) -> String { value(element, key) as? String ?? "" }
    private static func bool(_ element: AXUIElement, _ key: String) -> Bool { value(element, key) as? Bool ?? false }
    private static func find(_ root: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue = [root]; var index = 0
        while index < queue.count, index < 600 {
            let element = queue[index]; index += 1
            if predicate(element) { return element }
            queue.append(contentsOf: value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [])
        }
        return nil
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "VTA", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
