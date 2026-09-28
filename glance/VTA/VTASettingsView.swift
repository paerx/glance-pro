import SwiftUI

struct VTASettingsView: View {
    @Bindable var controller: VTAController
    @State private var monitor: Any?
    var body: some View {
        SettingsSectionTitle(text: "VTA · Voice to ChatGPT")
        SettingsGroup {
            SettingsRowContent(title: "Enable VTA") { GlanceToggle(isOn: $controller.enabled) }
            SettingsGroupDivider()
            SettingsRowContent(title: "Hold-to-talk shortcut") {
                Button(controller.bindingShortcut ? L10n.ui("Press a key… Esc to cancel") : controller.shortcutLabel) {
                    controller.bindingShortcut.toggle()
                }.disabled(controller.busy)
            }
            SettingsGroupDivider()
            SettingsRowContent(title: "Speech language") {
                Picker("", selection: $controller.language) {
                    Text("简体中文").tag("zh-CN")
                    Text("English").tag("en-US")
                }.labelsHidden().disabled(controller.busy)
            }
            SettingsGroupDivider()
            SettingsRowContent(title: "Microphone, Speech & Accessibility") {
                Button(L10n.ui("Grant")) { Task { await controller.preparePermissions() } }
            }
        }
        SettingsCaption(text: "Hold the shortcut to record, release to transcribe locally and send to a new chat in the ChatGPT Mac app. Sign in to ChatGPT first. Audio stays on this Mac; the transcript is sent to ChatGPT. Maximum recording: 60 seconds.")
        SettingsCaption(text: controller.status)
        if !controller.transcript.isEmpty {
            Text(controller.transcript).textSelection(.enabled).font(.system(size: 12))
            HStack {
                Button(L10n.ui("Copy transcript")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(controller.transcript, forType: .string)
                }
                Button(L10n.ui("Send in a new ChatGPT chat")) { controller.sendTranscript() }
                    .disabled(controller.busy)
            }
        }
        if controller.busy { Button(L10n.ui("Cancel")) { controller.cancel() } }
        Color.clear.frame(height: 0)
            .onChange(of: controller.bindingShortcut) { _, binding in
                if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
                if binding {
                    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        MainActor.assumeIsolated { controller.bind(event) }
                        return nil
                    }
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
                controller.bindingShortcut = false
            }
    }
}
