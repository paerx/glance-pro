import Foundation

enum ShaderOrbState: String, Codable, CaseIterable, Identifiable {
    case thinking, speaking, idle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .thinking: return "Scanning · Thinking"
        case .speaking: return "Success · Speaking"
        case .idle: return "Failure · Idle"
        }
    }
}

struct ShaderOrbParameter: Decodable, Identifiable {
    let key: String
    let label: String
    let min: Double
    let max: Double
    let step: Double
    let `default`: Double
    let integrate: Bool?
    var id: String { key }
}

struct ShaderOrbColor: Decodable, Identifiable {
    let key: String
    let label: String
    let `default`: String
    var id: String { key }
}

struct ShaderOrbVariant: Decodable, Identifiable {
    let id: String
    let label: String
    let note: String
    let params: [ShaderOrbParameter]
    let colors: [ShaderOrbColor]
    let statePresets: [String: [String: Double]]
    let stateColors: [String: [String: String]]
    let slots: [String: Int]
    let floatCount: Int
    let fragment: String
    let metal: String

    func parameter(_ def: ShaderOrbParameter, state: ShaderOrbState) -> Double {
        statePresets[state.rawValue]?[def.key] ?? def.default
    }
    func color(_ def: ShaderOrbColor, state: ShaderOrbState) -> String {
        stateColors[state.rawValue]?[def.key] ?? def.default
    }
}

enum ShaderOrbCatalog {
    static let variants: [ShaderOrbVariant] = {
        guard let url = Bundle.main.url(forResource: "ShaderOrbCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let variants = try? JSONDecoder().decode([ShaderOrbVariant].self, from: data) else { return [] }
        return variants
    }()
    static func variant(_ id: String) -> ShaderOrbVariant? {
        variants.first { $0.id == id } ?? variants.first
    }
}

struct ShaderOrbDraft: Codable, Equatable {
    var params: [String: Double] = [:]
    var colors: [String: String] = [:]
    var autoDrive = true
    var input: Double = 0.4
    var output: Double = 0.5

    static func initial(_ state: ShaderOrbState) -> Self {
        var draft = Self()
        switch state {
        case .thinking: break
        case .speaking: draft.input = 0.7; draft.output = 0.8
        case .idle: draft.input = 0; draft.output = 0.3
        }
        return draft
    }
}

/// Each orb keeps separate overrides for all three states, as in shadercn's playground.
struct ShaderOrbConfiguration: Codable, Equatable {
    var variantID = "orb-01"
    var size: Double = 160
    var drafts: [String: ShaderOrbDraft] = [:]
    static let sizeRange: ClosedRange<Double> = 120...720

    func draft(for state: ShaderOrbState) -> ShaderOrbDraft {
        drafts["\(variantID)/\(state.rawValue)"] ?? .initial(state)
    }
    mutating func setDraft(_ draft: ShaderOrbDraft, for state: ShaderOrbState) {
        drafts["\(variantID)/\(state.rawValue)"] = draft
    }
    mutating func reset(_ state: ShaderOrbState) {
        drafts.removeValue(forKey: "\(variantID)/\(state.rawValue)")
    }
    var clampedSize: Double {
        size.isFinite ? min(max(size, Self.sizeRange.lowerBound), Self.sizeRange.upperBound) : 160
    }
}
