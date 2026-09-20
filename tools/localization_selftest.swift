import Foundation
@MainActor final class GlanceSettings {
    static let shared = GlanceSettings()
    var language = AppLanguage.english
}
@main struct LocalizationSelfTest {
    @MainActor static func main() throws {
        var checks = 0
        let labels = ["Session locked", "Unlock session", "Language", "Organizing samples", "Confirm", "Back", "On wake", "Password encrypted", "Keep old data & continue"]
        for label in labels {
            precondition(L10n.string(label, language: .english) == label)
            precondition(L10n.string(label, language: .simplifiedChinese) != label)
            checks += 2
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: "glance/Resources/ShaderOrbCatalog.json"))
        let orbs = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let options = Set(orbs.flatMap { (($0["params"] as! [[String: Any]]) + ($0["colors"] as! [[String: Any]])).map { $0["label"] as! String } })
        for label in options {
            precondition(L10n.string(label, language: .simplifiedChinese) != label, "Untranslated option: \(label)")
            checks += 1
        }
        GlanceSettings.shared.language = .simplifiedChinese
        precondition(L10n.ui("Session locked") == "会话已锁定")
        GlanceSettings.shared.language = .english
        precondition(L10n.ui("Session locked") == "Session locked")
        checks += 2
        precondition(L10n.string("Alice", language: .simplifiedChinese) == "Alice")
        checks += 1
        print("PASS: \(checks) localization checks including \(options.count) shader option labels")
    }
}
