import AppKit
import MetalKit
import SwiftUI

/// Native Metal translation of shadercn's original WGSL, with the same uniform
/// layout, spring easing, integrated clocks, and synthesized drive volumes.
struct ShaderOrbView: View {
    let configuration: ShaderOrbConfiguration
    let state: ShaderOrbState
    var paused = false
    var fallbackMedia: ScanMedia = .idle
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if errorMessage != nil {
                ScanAnimationView(media: fallbackMedia)
            } else {
                ShaderOrbMetalView(configuration: configuration, state: state, paused: paused) {
                    errorMessage = $0
                }
            }
        }
        .help(errorMessage ?? "shadercn \(configuration.variantID) · \(state.rawValue)")
        .accessibilityLabel("\(configuration.variantID), \(state.title)")
        .onChange(of: configuration.variantID) { errorMessage = nil }
    }
}

private struct ShaderOrbMetalView: NSViewRepresentable {
    let configuration: ShaderOrbConfiguration
    let state: ShaderOrbState
    let paused: Bool
    let onError: (String) -> Void

    func makeNSView(context: Context) -> ShaderOrbMetalHost {
        let view = ShaderOrbMetalHost(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.configure(configuration, state: state, paused: paused, onError: onError)
        return view
    }
    func updateNSView(_ view: ShaderOrbMetalHost, context: Context) {
        view.configure(configuration, state: state, paused: paused, onError: onError)
    }
    static func dismantleNSView(_ view: ShaderOrbMetalHost, coordinator: ()) {
        view.isPaused = true
        view.delegate = nil
        view.renderer = nil
    }
}

final class ShaderOrbMetalHost: MTKView {
    var renderer: ShaderOrbRenderer?
    private var requestedPause = false
    private var visibilityObservers: [NSObjectProtocol] = []

    override init(frame: NSRect, device: (any MTLDevice)?) {
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        preferredFramesPerSecond = 30
        framebufferOnly = true
        autoResizeDrawable = false
        isPaused = true
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ configuration: ShaderOrbConfiguration, state: ShaderOrbState,
                   paused: Bool, onError: @escaping (String) -> Void) {
        requestedPause = paused
        if renderer?.variant.id != configuration.variantID {
            do {
                guard let device, let variant = ShaderOrbCatalog.variant(configuration.variantID) else {
                    throw NSError(domain: "ShaderOrb", code: 1, userInfo: [NSLocalizedDescriptionKey: "Shader animation unavailable; using the original animation."])
                }
                renderer = try ShaderOrbRenderer(device: device, variant: variant, configuration: configuration, state: state)
                delegate = renderer
            } catch {
                isPaused = true
                DispatchQueue.main.async { onError(error.localizedDescription) }
                return
            }
        }
        renderer?.configuration = configuration
        renderer?.state = state
        updatePlayback()
    }

    override func layout() {
        super.layout()
        // A bounded raster avoids rendering 720pt raymarchers at Retina 1440².
        let scale = min(window?.backingScaleFactor ?? 1, 2)
        let side = max(1, min(480, min(bounds.width, bounds.height) * scale))
        drawableSize = CGSize(width: side, height: side)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        visibilityObservers.forEach(NotificationCenter.default.removeObserver)
        visibilityObservers = []
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                visibilityObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updatePlayback() }
                })
            }
        }
        updatePlayback()
    }

    private func updatePlayback() {
        let visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        let shouldPause = requestedPause || !visible
        if isPaused != shouldPause { renderer?.resetFrameTime() }
        isPaused = shouldPause
    }

    deinit { visibilityObservers.forEach(NotificationCenter.default.removeObserver) }
}

final class ShaderOrbRenderer: NSObject, MTKViewDelegate {
    let variant: ShaderOrbVariant
    var configuration: ShaderOrbConfiguration
    var state: ShaderOrbState
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private var words: [Float]
    private var values: [Float]
    private var velocities: [Float]
    private var clocks: [Float]
    private var colorVelocities: [Float]
    private var seconds: Float = 0
    private var anim: Float = 0
    private var speed: Float = 0.1
    private var speedVelocity: Float = 0
    private var inputVolume: Float = 0
    private var outputVolume: Float = 0.3
    private var lastFrame: CFTimeInterval?
    private static var pipelines: [String: any MTLRenderPipelineState] = [:]

    init(device: any MTLDevice, variant: ShaderOrbVariant,
         configuration: ShaderOrbConfiguration, state: ShaderOrbState) throws {
        self.variant = variant
        self.configuration = configuration
        self.state = state
        guard let queue = device.makeCommandQueue() else {
            throw NSError(domain: "ShaderOrb", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create Metal command queue."])
        }
        self.queue = queue
        let cacheKey = "\(device.registryID)/\(variant.id)"
        if let cached = Self.pipelines[cacheKey] {
            pipeline = cached
        } else {
            let library = try device.makeLibrary(source: variant.metal, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "glanceVertex")
            descriptor.fragmentFunction = library.makeFunction(name: variant.fragment)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            // Match WebGPU's premultiplied surface against the black notch.
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            Self.pipelines[cacheKey] = pipeline
        }
        words = Array(repeating: 0, count: variant.floatCount)
        values = variant.params.map { Float(variant.parameter($0, state: state)) }
        velocities = Array(repeating: 0, count: variant.params.count)
        clocks = Array(repeating: 0, count: variant.params.count)
        colorVelocities = Array(repeating: 0, count: variant.colors.count * 3)
        super.init()
        for color in variant.colors {
            let rgb = Self.rgb(variant.color(color, state: state))
            if let at = variant.slots["c_\(color.key)"] {
                for channel in 0..<3 { words[at + channel] = rgb[channel] }
            }
        }
    }

    func resetFrameTime() { lastFrame = nil }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let now = CACurrentMediaTime()
        let dt = Float(min(max(now - (lastFrame ?? now - 1.0 / 30), 0), 0.05))
        lastFrame = now
        advance(dt: dt, size: view.drawableSize)
        encoder.setRenderPipelineState(pipeline)
        words.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    private func advance(dt: Float, size: CGSize) {
        seconds += dt
        let draft = configuration.draft(for: state)
        var targetInput: Float = 0
        var targetOutput: Float = 0.3
        switch state {
        case .speaking:
            targetInput = 0.65 + sin(seconds * 4.8) * 0.22
            targetOutput = 0.75 + sin(seconds * 3.6) * 0.22
        case .thinking:
            targetInput = 0.38 + 0.07 * sin(seconds * 0.7) + 0.05 * sin(seconds * 2.1) * sin(seconds * 0.37 + 1.2)
            targetOutput = 0.48 + 0.12 * sin(seconds * 1.05 + 0.6)
        case .idle: break
        }
        if !draft.autoDrive {
            targetInput = Self.finite(draft.input, fallback: 0, range: 0...1)
            targetOutput = Self.finite(draft.output, fallback: 0.3, range: 0...1)
        }
        let k = 1 - exp(-dt * 12)
        inputVolume += (targetInput - inputVolume) * k
        outputVolume += (targetOutput - outputVolume) * k
        (speed, speedVelocity) = Self.spring(speed, speedVelocity, 0.1 + (1 - pow(outputVolume - 1, 2)) * 0.9, dt)
        anim += dt * speed
        put("time", seconds * 0.5); put("anim", anim)
        put("inputVol", inputVolume); put("outputVol", outputVolume)
        if let at = variant.slots["res"] { words[at] = Float(size.width); words[at + 1] = Float(size.height) }
        for (i, def) in variant.params.enumerated() {
            let preset = variant.parameter(def, state: state)
            let target = Self.finite(draft.params[def.key] ?? preset, fallback: preset, range: def.min...def.max)
            (values[i], velocities[i]) = Self.spring(values[i], velocities[i], target, dt)
            if def.integrate == true {
                clocks[i] += dt * speed * values[i]
                put("p_\(def.key)", clocks[i])
            } else { put("p_\(def.key)", values[i]) }
        }
        for (i, def) in variant.colors.enumerated() {
            guard let at = variant.slots["c_\(def.key)"] else { continue }
            let rgb = Self.rgb(draft.colors[def.key] ?? variant.color(def, state: state))
            for channel in 0..<3 {
                let v = i * 3 + channel
                (words[at + channel], colorVelocities[v]) = Self.spring(words[at + channel], colorVelocities[v], rgb[channel], dt)
            }
        }
    }

    private func put(_ key: String, _ value: Float) { if let at = variant.slots[key] { words[at] = value } }
    private static func spring(_ x: Float, _ v: Float, _ target: Float, _ dt: Float) -> (Float, Float) {
        let f = 1 + 8 * dt, hoo = dt * 16, hhoo = dt * hoo
        let inverse = 1 / (f + hhoo)
        return ((f * x + dt * v + hhoo * target) * inverse, (v + hoo * (target - x)) * inverse)
    }
    private static func finite(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Float {
        Float(min(max(value.isFinite ? value : fallback, range.lowerBound), range.upperBound))
    }
    static func rgb(_ hex: String) -> [Float] {
        let h = hex.replacingOccurrences(of: "#", with: "")
        guard h.count == 6, let value = UInt32(h, radix: 16) else { return [1, 1, 1] }
        return [Float((value >> 16) & 255) / 255, Float((value >> 8) & 255) / 255, Float(value & 255) / 255]
    }
}
