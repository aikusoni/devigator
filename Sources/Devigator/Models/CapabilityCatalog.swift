import Foundation

struct CapabilityCatalog: Codable, Hashable {
    struct Category: Codable, Identifiable, Hashable {
        var id: String
        var labels: [String: String]
        var descriptions: [String: String]?
    }

    struct Capability: Codable, Identifiable, Hashable {
        var id: String
        var categoryID: String
        var labels: [String: String]
        var descriptions: [String: String]?
    }

    var schemaVersion: String
    var categories: [Category]
    var capabilities: [Capability]
}

@MainActor
enum CapabilityLocalization {
    private static let catalog: CapabilityCatalog? = loadCatalog()

    static var languageCode: String {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("ko") ? "ko" : "en"
    }

    static func profileName(_ profile: ShortcutProfile) -> String {
        profile.name
    }

    static func groupTitle(_ group: ShortcutProfile.Group) -> String {
        guard let categoryID = group.categoryID,
              let category = catalog?.categories.first(where: { $0.id == categoryID }) else {
            return group.title
        }
        return localized(category.labels, fallback: group.title)
    }

    static func action(_ shortcut: ShortcutProfile.Shortcut) -> String {
        guard let capabilityID = shortcut.capabilityID,
              let capability = catalog?.capabilities.first(where: { $0.id == capabilityID }) else {
            return shortcut.action
        }
        return localized(capability.labels, fallback: shortcut.action)
    }

    static func categoryID(
        for shortcut: ShortcutProfile.Shortcut,
        fallback: String?
    ) -> String? {
        guard let capabilityID = shortcut.capabilityID,
              let capability = catalog?.capabilities.first(where: { $0.id == capabilityID }) else {
            return fallback
        }
        return capability.categoryID
    }

    static func description(_ shortcut: ShortcutProfile.Shortcut) -> String? {
        if let capabilityID = shortcut.capabilityID,
           let capability = catalog?.capabilities.first(where: { $0.id == capabilityID }),
           let descriptions = capability.descriptions {
            return localized(descriptions, fallback: shortcut.description)
        }
        return shortcut.description
    }

    static func interfaceText(korean: String, english: String) -> String {
        languageCode == "ko" ? korean : english
    }

    private static func localized(_ values: [String: String], fallback: String?) -> String {
        values[languageCode] ?? values["en"] ?? values["ko"] ?? fallback ?? ""
    }

    private static func loadCatalog() -> CapabilityCatalog? {
        let url = Bundle.main.url(forResource: "CapabilityCatalog", withExtension: "json")
            ?? Bundle.module.url(forResource: "CapabilityCatalog", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CapabilityCatalog.self, from: data)
    }
}
