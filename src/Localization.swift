import AppKit
import Foundation

/// Shared JSON catalogs are consumed by both the native UI and the Python worker.
final class Localization {
    static let shared = Localization()
    static let supported = ["en", "ru", "de", "fr", "es", "ja", "zh-Hans"]
    static let names = [
        "en": "English", "ru": "Русский", "de": "Deutsch", "fr": "Français", "es": "Español",
        "ja": "日本語", "zh-Hans": "简体中文",
    ]
    private let defaultsKey = "PDFLightLanguage"
    private var catalogs: [String: [String: String]] = [:]
    private var bindings: [() -> Void] = []
    private(set) var code: String
    var preference: String { UserDefaults.standard.string(forKey: defaultsKey) ?? "system" }

    static func resolve(preference: String, languages: [String]) -> String {
        if supported.contains(preference) { return preference }
        for value in languages {
            let tag = value.replacingOccurrences(of: "_", with: "-").lowercased()
            if tag == "zh" || tag.hasPrefix("zh-") { return "zh-Hans" }
            if let base = tag.split(separator: "-").first, supported.contains(String(base)) {
                return String(base)
            }
        }
        return "en"
    }

    private init() {
        let selected = UserDefaults.standard.string(forKey: defaultsKey) ?? "system"
        code = Self.resolve(preference: selected, languages: Locale.preferredLanguages)
        let folder = Bundle.main.resourceURL?.appendingPathComponent("locales")
        for language in Self.supported {
            if let url = folder?.appendingPathComponent(language + ".json"),
                let data = try? Data(contentsOf: url),
                let messages = try? JSONDecoder().decode([String: String].self, from: data)
            {
                catalogs[language] = messages
            }
        }
    }

    func text(_ key: String, _ values: [String: String] = [:]) -> String {
        let template = catalogs[code]?[key] ?? catalogs["en"]?[key] ?? key
        // A single pass prevents a value containing {another_key} being expanded again.
        let pattern = try! NSRegularExpression(pattern: #"\{([a-z_]+)\}"#)
        let mutable = NSMutableString(string: template)
        let matches = pattern.matches(
            in: template, range: NSRange(template.startIndex..., in: template))
        for match in matches.reversed() {
            let name = (template as NSString).substring(with: match.range(at: 1))
            if let value = values[name] { mutable.replaceCharacters(in: match.range, with: value) }
        }
        return mutable as String
    }

    func observe(_ update: @escaping () -> Void) { bindings.append(update) }

    func select(_ preference: String) {
        guard preference == "system" || Self.supported.contains(preference) else { return }
        UserDefaults.standard.set(preference, forKey: defaultsKey)
        code = Self.resolve(preference: preference, languages: Locale.preferredLanguages)
        for update in bindings { update() }
    }

    var numberLocale: Locale { preference == "system" ? .current : Locale(identifier: code) }
    func number(_ value: Double, decimals: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.locale = numberLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    func parseTarget(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept decimal comma or dot, but never ambiguously interpret thousands separators.
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
        else { return nil }
        return Double(normalized)
    }
}

func tr(_ key: String, _ values: [String: String] = [:]) -> String {
    Localization.shared.text(key, values)
}

func localizedLabel(
    _ key: String, _ size: CGFloat = 13, _ weight: NSFont.Weight = .regular,
    _ color: NSColor = ink
) -> NSTextField {
    let field = label(tr(key), size, weight, color)
    Localization.shared.observe { [weak field] in field?.stringValue = tr(key) }
    return field
}

func localizedButton(_ key: String, checkbox: Bool = false) -> NSButton {
    let button =
        checkbox
        ? NSButton(checkboxWithTitle: tr(key), target: nil, action: nil)
        : NSButton(title: tr(key), target: nil, action: nil)
    Localization.shared.observe { [weak button] in button?.title = tr(key) }
    return button
}
