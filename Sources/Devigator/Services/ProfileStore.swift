import AppKit
import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [LoadedProfile] = []
    @Published private(set) var lastError: String?

    static let profileExtension = "devigator.json"

    let profilesDirectory: URL
    var providerProfilesDirectory: URL {
        profilesDirectory.appendingPathComponent("Providers", isDirectory: true)
    }
    var userProfilesDirectory: URL {
        profilesDirectory.appendingPathComponent("User", isDirectory: true)
    }
    private let builtInCatalogURL: URL?
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    init(
        profilesDirectory: URL? = nil,
        builtInCatalogURL: URL? = nil
    ) {
        self.profilesDirectory = profilesDirectory ?? Self.defaultProfilesDirectory()
        self.builtInCatalogURL = builtInCatalogURL ?? Self.defaultBuiltInCatalogURL()
        reload()
    }

    func reload() {
        do {
            try FileManager.default.createDirectory(
                at: providerProfilesDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(at: userProfilesDirectory, withIntermediateDirectories: true)

            var merged: [String: LoadedProfile] = [:]
            if let builtInCatalogURL {
                let catalog = try decodeCatalog(at: builtInCatalogURL)
                for profile in catalog.profiles {
                    merged[profile.id] = LoadedProfile(
                        profile: profile,
                        source: .builtIn,
                        fileURL: nil
                    )
                }
            }

            var warnings = loadCatalogs(in: providerProfilesDirectory, source: .provider, into: &merged)
            warnings += loadCatalogs(in: userProfilesDirectory, source: .user, into: &merged)

            profiles = merged.values.sorted {
                $0.profile.name.localizedCaseInsensitiveCompare($1.profile.name) == .orderedAscending
            }
            lastError = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func profile(for application: FrontmostApplication) -> LoadedProfile? {
        ApplicationMatcher.profile(for: application, in: profiles)
    }

    func json(for loadedProfile: LoadedProfile) throws -> String {
        let catalog = ShortcutCatalog(
            schemaVersion: ProfileValidator.supportedSchemaVersion,
            profiles: [loadedProfile.profile]
        )
        return String(decoding: try encoder.encode(catalog), as: UTF8.self)
    }

    func validate(json: String) throws -> ShortcutCatalog {
        let catalog = try decoder.decode(ShortcutCatalog.self, from: Data(json.utf8))
        try ProfileValidator.validate(catalog)
        return catalog
    }

    @discardableResult
    func save(json: String, replacing loadedProfile: LoadedProfile?) throws -> URL {
        let catalog = try validate(json: json)
        guard let profile = catalog.profiles.first else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "저장할 프로필이 없습니다."
            ])
        }

        let safeID = profile.id
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]", with: "-", options: .regularExpression)
        let destination: URL
        if let loadedProfile,
           loadedProfile.source == .user,
           loadedProfile.sourceProfileCount == 1,
           let existing = loadedProfile.fileURL {
            destination = existing
        } else {
            destination = userProfilesDirectory.appendingPathComponent("\(safeID).\(Self.profileExtension)")
        }

        let encoded = try encoder.encode(catalog)
        try encoded.write(to: destination, options: .atomic)
        reload()
        return destination
    }

    @discardableResult
    func importProfile(from source: URL) throws -> String? {
        let data = try Data(contentsOf: source)
        let catalog = try decoder.decode(ShortcutCatalog.self, from: data)
        try ProfileValidator.validate(catalog)
        guard let profile = catalog.profiles.first else { return nil }
        let destination = userProfilesDirectory.appendingPathComponent(
            "\(profile.id).\(Self.profileExtension)"
        )
        try data.write(to: destination, options: .atomic)
        reload()
        return profile.id
    }

    func export(_ loadedProfile: LoadedProfile, to destination: URL) throws {
        try Data(json(for: loadedProfile).utf8).write(to: destination, options: .atomic)
    }

    func templateJSON() -> String {
        let profile = ShortcutProfile(
            id: "com.example.editor",
            name: "My Editor",
            application: .init(
                bundleIdentifiers: ["com.example.editor"],
                applicationNames: ["My Editor"]
            ),
            metadata: .init(
                version: "1.0.0",
                author: NSFullUserName().isEmpty ? "User" : NSFullUserName(),
                homepage: nil,
                description: "사용자 정의 코드 탐색 단축키"
            ),
            groups: [
                .init(id: "navigation", title: "코드 탐색", shortcuts: [
                    .init(
                        id: "go-to-definition",
                        action: "정의로 이동",
                        keys: ["⌘", "B"],
                        description: nil,
                        tags: ["navigation"],
                        commandID: nil,
                        pointerGestures: [
                            .init(modifiers: ["⌘"], button: .primary, clickCount: 1)
                        ]
                    )
                ])
            ]
        )
        let catalog = ShortcutCatalog(schemaVersion: ProfileValidator.supportedSchemaVersion, profiles: [profile])
        return String(decoding: (try? encoder.encode(catalog)) ?? Data(), as: UTF8.self)
    }

    private func decodeCatalog(at url: URL) throws -> ShortcutCatalog {
        let catalog = try decoder.decode(ShortcutCatalog.self, from: Data(contentsOf: url))
        try ProfileValidator.validate(catalog)
        return catalog
    }

    private func loadCatalogs(
        in directory: URL,
        source: LoadedProfile.Source,
        into merged: inout [String: LoadedProfile]
    ) -> [String] {
        var warnings: [String] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return warnings }
        let urls = enumerator.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasSuffix(".\(Self.profileExtension)") }
            .sorted { $0.path < $1.path }

        for url in urls {
            do {
                let catalog = try decodeCatalog(at: url)
                for profile in catalog.profiles {
                    merged[profile.id] = LoadedProfile(
                        profile: profile,
                        source: source,
                        fileURL: url,
                        sourceProfileCount: catalog.profiles.count
                    )
                }
            } catch {
                warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return warnings
    }

    private static func defaultBuiltInCatalogURL() -> URL? {
        Bundle.main.url(forResource: "DefaultProfiles", withExtension: "json")
            ?? Bundle.module.url(forResource: "DefaultProfiles", withExtension: "json")
    }

    private static func defaultProfilesDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Devigator/Profiles", isDirectory: true)
    }
}
