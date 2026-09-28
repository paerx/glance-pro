import AppKit
import AVFoundation
import Speech
import Observation
import SwiftUI

@Observable @MainActor final class VTAController {
    enum Phase { case idle, recording, transcribing, sending, success, failure }
    var enabled = UserDefaults.standard.bool(forKey: "VTA.enabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "VTA.enabled"); configureHotkey() }
    }
    var keyCode = UInt16(clamping: UserDefaults.standard.object(forKey: "VTA.keyCode") as? Int ?? 97)
    var modifiers = UInt64(clamping: UserDefaults.standard.object(forKey: "VTA.modifiers") as? Int ?? 0)
    var shortcutLabel = UserDefaults.standard.string(forKey: "VTA.shortcutLabel") ?? "F6"
    var language = UserDefaults.standard.string(forKey: "VTA.language") ?? "zh-CN" {
        didSet { UserDefaults.standard.set(language, forKey: "VTA.language") }
    }
    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var status = "Hold your shortcut to talk"
    private(set) var level: Float = 0
    private(set) var overlayVisible = false
    private var lockObserver: NSObjectProtocol?
    var bindingShortcut = false { didSet { configureHotkey() } }
    private let hotkey = VTAHotkey()
    private let engine = AVAudioEngine()
    private var audioRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var timeout: Task<Void, Never>?
    private var delivery: Task<Void, Never>?
    private var generation = UUID()
    private var tapInstalled = false
    private var panel: NSPanel?
    private var sleepObserver: NSObjectProtocol?
    var busy: Bool { [.recording, .transcribing, .sending].contains(phase) }

    init() {
        hotkey.onDown = { [weak self] in self?.record() }
        hotkey.onUp = { [weak self] in self?.finishRecording() }
        hotkey.onCancel = { [weak self] in self?.cancel() }
        configureHotkey()
        lockObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cancel() }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }
    func preparePermissions() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        _ = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        KeystrokeInjector.promptForAccessibility()
        configureHotkey()
    }
    func bind(_ event: NSEvent) {
        guard event.keyCode != 53 else { bindingShortcut = false; return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        keyCode = event.keyCode
        modifiers = UInt64(flags.rawValue)
        shortcutLabel = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + keyName(event)
        UserDefaults.standard.set(Int(keyCode), forKey: "VTA.keyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "VTA.modifiers")
        UserDefaults.standard.set(shortcutLabel, forKey: "VTA.shortcutLabel")
        bindingShortcut = false
    }
    private func keyName(_ event: NSEvent) -> String {
        let names: [UInt16: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 49: "Space", 36: "Return", 48: "Tab"]
        return names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }

    private func configureHotkey() {
        hotkey.stop()
        guard enabled, !bindingShortcut else { cancel(); return }
        hotkey.keyCode = keyCode; hotkey.modifiers = modifiers
        if !hotkey.start() { status = "Allow Accessibility for Glance first." }
        else { status = "Hold your shortcut to talk" }
    }
    private func record() {
        guard !busy, enabled, !LockMonitor.isScreenActuallyLocked() else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              SFSpeechRecognizer.authorizationStatus() == .authorized else { fail("Grant microphone and speech permissions in VTA settings."); return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else { fail("On-device speech recognition is unavailable for this language."); return }
        cancel()
        self.recognizer = recognizer
        generation = UUID(); let id = generation
        transcript = ""; phase = .recording; status = "Recording — release to send"
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        audioRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.generation == id else { return }
                if let text { self.transcript = text }
                if final {
                    if self.phase == .recording { self.finishRecording() }
                    if self.phase == .transcribing { self.sendTranscript() }
                } else if let message { self.fail(message) }
            }
        }
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { fail("No microphone is available."); return }
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let count = Int(buffer.frameLength)
            var peak: Float = 0
            if let data = buffer.floatChannelData?.pointee { for i in 0..<count { peak = max(peak, abs(data[i])) } }
            let amplitude = min(1, peak * 5)
            Task { @MainActor [weak self] in if self?.generation == id { self?.level = amplitude } }
        }
        tapInstalled = true
        do { engine.prepare(); try engine.start() } catch { fail(error.localizedDescription); return }
        showPanel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, self?.generation == id else { return }
            self?.finishRecording()
        }
    }
    private func stopAudio() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }
    private func finishRecording() {
        guard phase == .recording else { return }
        stopAudio(); audioRequest?.endAudio(); timeout?.cancel()
        phase = .transcribing; status = "Transcribing…"; level = 0
        let id = generation
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, self?.generation == id, self?.phase == .transcribing else { return }
            self?.fail("Transcription timed out. Your partial text is kept in VTA settings.")
        }
    }
    func sendTranscript() {
        guard phase != .sending else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { fail("No speech detected."); return }
        timeout?.cancel(); recognitionTask?.cancel(); recognitionTask = nil
        phase = .sending; status = "Opening a new ChatGPT chat…"
        showPanel()
        let id = generation
        delivery = Task { [weak self] in
            do {
                try await ChatGPTDelivery.send(text)
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.phase = .success; self.status = "Sent to ChatGPT"
                try await Task.sleep(for: .seconds(2))
                guard self.generation == id else { return }
                self.overlayVisible = false
                self.panel?.orderOut(nil)
            } catch is CancellationError { }
            catch { guard let self, self.generation == id else { return }; self.fail(error.localizedDescription) }
        }
    }
    func cancel() {
        generation = UUID(); timeout?.cancel(); delivery?.cancel()
        stopAudio(); recognitionTask?.cancel(); recognitionTask = nil; audioRequest = nil
        phase = .idle; level = 0; overlayVisible = false; panel?.orderOut(nil)
    }
    private func fail(_ message: String) {
        generation = UUID(); stopAudio(); recognitionTask?.cancel(); recognitionTask = nil
        audioRequest = nil; timeout?.cancel(); phase = .failure; status = message; showPanel()
    }
    private func showPanel() {
        if panel == nil {
            let window = NotchWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 250))
            let host = NSHostingView(rootView: VTAOverlayView(controller: self))
            host.sizingOptions = []
            host.safeAreaRegions = []
            window.contentView = host
            window.ignoresMouseEvents = false
            panel = window
        }
        guard let panel, let screen = NotchGeometry.preferredScreen() else { return }
        panel.setFrameOrigin(OverlayPlacement.origin(screen: screen.frame, window: panel.frame.size))
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase != .idle else { return }
            self.overlayVisible = true
        }
    }
}

struct VTAOverlayView: View {
    let controller: VTAController
    var body: some View {
        VStack(spacing: 8) {
            if controller.phase == .recording {
                Image(systemName: "mic.fill").font(.system(size: 30)).foregroundStyle(.red)
                    .symbolEffect(.pulse)
                HStack(spacing: 4) {
                    ForEach(0..<15) { i in
                        Capsule().fill(.red.opacity(0.8)).frame(width: 4, height: 5 + CGFloat(controller.level) * CGFloat(12 + (i * 7) % 27))
                    }
                }.frame(height: 38).animation(.easeOut(duration: 0.1), value: controller.level)
            } else {
                ShaderOrbView(configuration: configuration, state: controller.phase == .success ? .speaking : controller.phase == .failure ? .idle : .thinking)
                    .frame(width: 90, height: 90)
            }
            Text(L10n.ui(controller.status)).font(.system(size: 12)).multilineTextAlignment(.center).lineLimit(3)
            Button(L10n.ui("Dismiss")) { controller.cancel() }.buttonStyle(.plain)
        }
        .padding(20).frame(width: 320).background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
        .foregroundStyle(.white)
        .scaleEffect(controller.overlayVisible ? 1 : 0.2, anchor: .top)
        .opacity(controller.overlayVisible ? 1 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: controller.overlayVisible)
        .animation(.easeInOut(duration: 0.2), value: controller.phase)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
    private var configuration: ShaderOrbConfiguration {
        var config = GlanceSettings.shared.shaderOrbConfiguration; config.size = 90; return config
    }
}
