// Run: swift validate.swift path/to/ShaderOrbCatalog.json /tmp/orbs.png
// Compiles every translated shader, verifies uniform buffer sizes, and renders
// all 99 variant/state pairs to real Metal textures, checking GPU completion.
import AppKit
import Metal

let arguments = CommandLine.arguments
guard arguments.count == 3, let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    fatalError("Usage: validate.swift catalog.json contact-sheet.png (Metal device required)")
}
let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
let variants = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
precondition(variants.count == 33)
let side = 96
let tileWidth = 320, tileHeight = 122, columns = 3, rows = 11
let canvas = CGContext(data: nil, width: columns * tileWidth, height: rows * tileHeight,
                       bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
canvas.setFillColor(CGColor(gray: 0.025, alpha: 1))
canvas.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
var rendered = 0
for (index, variant) in variants.enumerated() {
    let id = variant["id"] as! String
    let library = try device.makeLibrary(source: variant["metal"] as! String, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "glanceVertex")
    descriptor.fragmentFunction = library.makeFunction(name: variant["fragment"] as! String)
    descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
    var reflection: MTLRenderPipelineReflection?
    let pipeline = try device.makeRenderPipelineState(descriptor: descriptor, options: [.argumentInfo, .bufferTypeInfo], reflection: &reflection)
    let count = variant["floatCount"] as! Int
    let buffer = reflection!.fragmentArguments!.first { $0.type == .buffer }!
    precondition(buffer.index == 0 && buffer.bufferDataSize <= count * 4, "\(id) uniform size")
    let slots = variant["slots"] as! [String: Int]
    for member in buffer.bufferStructType!.members {
        if let slot = slots[member.name] { precondition(member.offset == slot * 4, "\(id) \(member.name) offset") }
    }
    let params = variant["params"] as! [[String: Any]]
    let colors = variant["colors"] as! [[String: Any]]
    let presets = variant["statePresets"] as! [String: [String: Double]]
    let stateColors = variant["stateColors"] as! [String: [String: String]]
    for (stateIndex, state) in ["thinking", "speaking", "idle"].enumerated() {
        var words = [Float](repeating: 0, count: count)
        words[slots["time"]!] = 1
        words[slots["anim"]!] = 1
        words[slots["inputVol"]!] = [0.4, 0.7, 0][stateIndex]
        words[slots["outputVol"]!] = [0.5, 0.8, 0.3][stateIndex]
        words[slots["res"]!] = Float(side)
        words[slots["res"]! + 1] = Float(side)
        for param in params {
            let key = param["key"] as! String
            words[slots["p_\(key)"]!] = Float(presets[state]?[key] ?? (param["default"] as! Double))
        }
        for color in colors {
            let key = color["key"] as! String
            let hex = stateColors[state]?[key] ?? (color["default"] as! String)
            let rgb = UInt32(hex.dropFirst(), radix: 16)!
            let at = slots["c_\(key)"]!
            words[at] = Float((rgb >> 16) & 255) / 255
            words[at + 1] = Float((rgb >> 8) & 255) / 255
            words[at + 2] = Float(rgb & 255) / 255
        }
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: side, height: side, mipmapped: false)
        textureDescriptor.usage = [.renderTarget]
        textureDescriptor.storageMode = .shared
        let texture = device.makeTexture(descriptor: textureDescriptor)!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setRenderPipelineState(pipeline)
        words.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        precondition(command.status == .completed, "\(id) \(state): \(String(describing: command.error))")
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        texture.getBytes(&pixels, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        var lit = 0
        for at in stride(from: 0, to: pixels.count, by: 4) {
            let brightness = Int(pixels[at]) + Int(pixels[at + 1]) + Int(pixels[at + 2])
            if brightness > 15 { lit += 1 }
        }
        precondition(lit > 20, "\(id) \(state) rendered blank")
        // Composite RGB on black, matching the app's opaque notch panel.
        for at in stride(from: 3, to: pixels.count, by: 4) { pixels[at] = 255 }
        let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let x = (index % columns) * tileWidth + stateIndex * 104 + 4
        let y = (rows - 1 - index / columns) * tileHeight + 4
        canvas.draw(image, in: CGRect(x: x, y: y, width: side, height: side))
        rendered += 1
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
    ("\(id.uppercased())    Thinking / Speaking / Idle" as NSString).draw(at: NSPoint(x: (index % columns) * tileWidth + 8, y: (rows - 1 - index / columns) * tileHeight + 104),
        withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.white])
    NSGraphicsContext.restoreGraphicsState()
    print("PASS \(id): compiled, offsets verified, 3 states rendered")
}
let bitmap = NSBitmapImageRep(cgImage: canvas.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
print("PASS: \(rendered) renders; contact sheet at \(arguments[2])")
