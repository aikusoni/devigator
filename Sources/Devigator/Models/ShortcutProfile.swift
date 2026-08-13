import Foundation

struct ShortcutCatalog: Codable {
    let schemaVersion: String
    var profiles: [ShortcutProfile]
}

struct ShortcutProfile: Codable, Identifiable, Hashable {
    struct ApplicationMatcher: Codable, Hashable {
        var bundleIdentifiers: [String]
        var bundleIdentifierPatterns: [String]
        var applicationNames: [String]

        init(
            bundleIdentifiers: [String] = [],
            bundleIdentifierPatterns: [String] = [],
            applicationNames: [String] = []
        ) {
            self.bundleIdentifiers = bundleIdentifiers
            self.bundleIdentifierPatterns = bundleIdentifierPatterns
            self.applicationNames = applicationNames
        }

        private enum CodingKeys: String, CodingKey {
            case bundleIdentifiers
            case bundleIdentifierPatterns
            case applicationNames
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .bundleIdentifiers) ?? []
            bundleIdentifierPatterns = try container.decodeIfPresent(
                [String].self,
                forKey: .bundleIdentifierPatterns
            ) ?? []
            applicationNames = try container.decodeIfPresent([String].self, forKey: .applicationNames) ?? []
        }
    }

    struct Metadata: Codable, Hashable {
        var version: String
        var author: String
        var homepage: String?
        var description: String?
    }

    struct Group: Codable, Identifiable, Hashable {
        var id: String
        var title: String
        var categoryID: String? = nil
        var shortcuts: [Shortcut]
    }

    struct Shortcut: Codable, Identifiable, Hashable {
        var id: String
        var action: String
        var keys: [String]
        var description: String?
        var tags: [String]?
        var commandID: String?
        var capabilityID: String? = nil
        var when: String? = nil
    }

    var id: String
    var name: String
    var priority: Int? = nil
    var application: ApplicationMatcher
    var metadata: Metadata
    var groups: [Group]
}

struct LoadedProfile: Identifiable, Hashable {
    enum Source: String, Hashable {
        case builtIn = "기본 제공"
        case provider = "IDE 제공자"
        case user = "사용자"
    }

    var id: String { profile.id }
    var profile: ShortcutProfile
    var source: Source
    var fileURL: URL?
    var sourceProfileCount: Int = 1
}

enum ProfileValidationError: LocalizedError, Equatable {
    case unsupportedSchema(String)
    case emptyProfileID
    case emptyApplicationMatcher(String)
    case duplicateProfileID(String)
    case duplicateGroupID(profile: String, group: String)
    case duplicateShortcutID(profile: String, shortcut: String)
    case emptyKeys(profile: String, shortcut: String)
    case invalidPriority(profile: String, priority: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "지원하지 않는 schemaVersion입니다: \(version)"
        case .emptyProfileID:
            return "프로필 id는 비어 있을 수 없습니다."
        case .emptyApplicationMatcher(let profile):
            return "\(profile): application 매처가 하나 이상 필요합니다."
        case .duplicateProfileID(let id):
            return "중복된 프로필 id입니다: \(id)"
        case .duplicateGroupID(let profile, let group):
            return "\(profile): 중복된 그룹 id입니다: \(group)"
        case .duplicateShortcutID(let profile, let shortcut):
            return "\(profile): 중복된 shortcut id입니다: \(shortcut)"
        case .emptyKeys(let profile, let shortcut):
            return "\(profile): \(shortcut)의 keys가 비어 있습니다."
        case .invalidPriority(let profile, let priority):
            return "\(profile): priority \(priority)는 -100부터 100 사이여야 합니다."
        }
    }
}

enum ProfileValidator {
    static let supportedSchemaVersion = "1.1"
    static let supportedSchemaVersions: Set<String> = ["1.0", "1.1"]

    static func validate(_ catalog: ShortcutCatalog) throws {
        guard supportedSchemaVersions.contains(catalog.schemaVersion) else {
            throw ProfileValidationError.unsupportedSchema(catalog.schemaVersion)
        }

        var profileIDs = Set<String>()
        for profile in catalog.profiles {
            guard !profile.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ProfileValidationError.emptyProfileID
            }
            guard profileIDs.insert(profile.id).inserted else {
                throw ProfileValidationError.duplicateProfileID(profile.id)
            }

            let matcher = profile.application
            guard !(matcher.bundleIdentifiers.isEmpty
                    && matcher.bundleIdentifierPatterns.isEmpty
                    && matcher.applicationNames.isEmpty) else {
                throw ProfileValidationError.emptyApplicationMatcher(profile.id)
            }
            if let priority = profile.priority, !(-100...100).contains(priority) {
                throw ProfileValidationError.invalidPriority(profile: profile.id, priority: priority)
            }

            var groupIDs = Set<String>()
            var shortcutIDs = Set<String>()
            for group in profile.groups {
                guard groupIDs.insert(group.id).inserted else {
                    throw ProfileValidationError.duplicateGroupID(profile: profile.id, group: group.id)
                }
                for shortcut in group.shortcuts {
                    guard shortcutIDs.insert(shortcut.id).inserted else {
                        throw ProfileValidationError.duplicateShortcutID(
                            profile: profile.id,
                            shortcut: shortcut.id
                        )
                    }
                    guard !shortcut.keys.isEmpty else {
                        throw ProfileValidationError.emptyKeys(
                            profile: profile.id,
                            shortcut: shortcut.id
                        )
                    }
                }
            }
        }
    }
}
