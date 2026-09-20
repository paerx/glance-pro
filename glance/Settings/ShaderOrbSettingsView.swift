import AppKit
import SwiftUI

struct ShaderOrbSettingsView: View {
    @Bindable private var settings = GlanceSettings.shared
    @State private var state: ShaderOrbState = .thinking
    @State private var paused = false
    @State private var isVisible = false
    @State private var copied = false

    private var configuration: ShaderOrbConfiguration { settings.shaderOrbConfiguration }
    private var variant: ShaderOrbVariant? { ShaderOrbCatalog.variant(configuration.variantID) }
    private var draft: ShaderOrbDraft { configuration.draft(for: state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let variant {
                SettingsGroup {
                    SettingsRowContent(title: "Orb") {
                        SettingsMenuPickerPill(label: variant.label) {
                            ForEach(ShaderOrbCatalog.variants) { orb in
                                Button(L10n.ui("\(orb.label) · \(orb.note)")) {
                                    settings.shaderOrbConfiguration.variantID = orb.id
                                }
                            }
                        }
                    }
                    SettingsGroupDivider()
                    SettingsRowContent(title: "Configure state") {
                        Picker("State", selection: $state) {
                            ForEach(ShaderOrbState.allCases) { Text(L10n.ui($0.title)).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                VStack(spacing: 10) {
                    ShaderOrbView(configuration: configuration, state: state,
                                  paused: paused || !isVisible,
                                  fallbackMedia: state == .speaking ? .success : (state == .idle ? .failure : .idle))
                        .frame(width: min(configuration.clampedSize, 260), height: min(configuration.clampedSize, 260))
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .background(.black, in: RoundedRectangle(cornerRadius: 22))
                        .onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }
                    HStack {
                        Text(L10n.ui(variant.note)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.ui(paused ? "Play" : "Pause"), systemImage: paused ? "play.fill" : "pause.fill") {
                            paused.toggle()
                        }
                    }
                }

                SettingsCaption(text: "Scanning → Thinking · Success → Speaking · Failure → Idle. Each state saves its own colors, drive and parameters. Preview fits this panel; overlay size adapts to your display.")

                SettingsGroup {
                    slider("Size", value: Binding(
                        get: { configuration.clampedSize },
                        set: { settings.shaderOrbConfiguration.size = $0 }
                    ), range: ShaderOrbConfiguration.sizeRange, step: 10, suffix: " pt")
                    ForEach(variant.colors) { color in
                        SettingsGroupDivider()
                        SettingsRowContent(title: color.label) {
                            ColorPicker(L10n.ui(color.label), selection: colorBinding(color, variant: variant), supportsOpacity: false)
                                .labelsHidden()
                        }
                    }
                    SettingsGroupDivider()
                    SettingsRowContent(title: "Auto volumes") {
                        GlanceToggle(isOn: Binding(get: { draft.autoDrive }, set: { value in edit { $0.autoDrive = value } }))
                    }
                    if !draft.autoDrive {
                        SettingsGroupDivider()
                        slider("Input", value: Binding(get: { draft.input }, set: { value in edit { $0.input = value } }), range: 0...1, step: 0.01)
                        SettingsGroupDivider()
                        slider("Output", value: Binding(get: { draft.output }, set: { value in edit { $0.output = value } }), range: 0...1, step: 0.01)
                    }
                }
                SettingsCaption(text: "Drive volumes are animation controls only; no microphone or audio playback is used.")

                SettingsSectionTitle(text: "Parameters · \(state.rawValue.capitalized)")
                SettingsGroup {
                    ForEach(Array(variant.params.enumerated()), id: \.element.id) { index, parameter in
                        if index > 0 { SettingsGroupDivider() }
                        slider(parameter.label, value: Binding(
                            get: { draft.params[parameter.key] ?? variant.parameter(parameter, state: state) },
                            set: { value in edit { $0.params[parameter.key] = value } }
                        ), range: parameter.min...parameter.max, step: parameter.step)
                    }
                }
                HStack {
                    Button(L10n.ui("Reset this state")) { settings.shaderOrbConfiguration.reset(state) }
                    Spacer()
                    Button(L10n.ui(copied ? "Copied" : "Copy configuration")) {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        if let data = try? encoder.encode(configuration), let text = String(data: data, encoding: .utf8) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            copied = true
                        }
                    }
                }
                .onChange(of: configuration) { copied = false }
                Text(L10n.ui("shadercn · Shaders by XorDev · Non-commercial use with attribution"))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                SettingsCaption(text: "Shader catalog is unavailable. Rebuild the app with ShaderOrbCatalog.json included in Resources.")
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    private func edit(_ update: (inout ShaderOrbDraft) -> Void) {
        var next = draft
        update(&next)
        settings.shaderOrbConfiguration.setDraft(next, for: state)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                        step: Double, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.ui(title))
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0...3))) + suffix)
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func colorBinding(_ color: ShaderOrbColor, variant: ShaderOrbVariant) -> Binding<Color> {
        Binding(get: {
            let rgb = ShaderOrbRenderer.rgb(draft.colors[color.key] ?? variant.color(color, state: state))
            return Color(.sRGB, red: Double(rgb[0]), green: Double(rgb[1]), blue: Double(rgb[2]), opacity: 1)
        }, set: { value in
            guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02x%02x%02x", Int((rgb.redComponent * 255).rounded()),
                             Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
            edit { $0.colors[color.key] = hex }
        })
    }
}
