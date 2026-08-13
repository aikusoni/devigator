import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Devigator

final class ProfileTests: XCTestCase {
    func testBundledCatalogIsValid() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = repositoryRoot
            .appendingPathComponent("Sources/Devigator/Resources/DefaultProfiles.json")
        let catalog = try JSONDecoder().decode(
            ShortcutCatalog.self,
            from: Data(contentsOf: catalogURL)
        )

        XCTAssertNoThrow(try ProfileValidator.validate(catalog))
        XCTAssertEqual(catalog.profiles.count, 6)
    }

    func testCapabilityCatalogIsBilingualAndCoversBuiltInProfiles() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = repositoryRoot.appendingPathComponent("Sources/Devigator/Resources")
        let capabilities = try JSONDecoder().decode(
            CapabilityCatalog.self,
            from: Data(contentsOf: resources.appendingPathComponent("CapabilityCatalog.json"))
        )
        let profiles = try JSONDecoder().decode(
            ShortcutCatalog.self,
            from: Data(contentsOf: resources.appendingPathComponent("DefaultProfiles.json"))
        )

        XCTAssertTrue(capabilities.categories.allSatisfy {
            $0.labels["en"] != nil && $0.labels["ko"] != nil
        })
        XCTAssertTrue(capabilities.capabilities.allSatisfy {
            $0.labels["en"] != nil && $0.labels["ko"] != nil
        })

        let categoryIDs = Set(capabilities.categories.map(\.id))
        let capabilityIDs = Set(capabilities.capabilities.map(\.id))
        for profile in profiles.profiles {
            for group in profile.groups {
                if let categoryID = group.categoryID {
                    XCTAssertTrue(categoryIDs.contains(categoryID), "Unknown category: \(categoryID)")
                }
                for shortcut in group.shortcuts {
                    if let capabilityID = shortcut.capabilityID {
                        XCTAssertTrue(capabilityIDs.contains(capabilityID), "Unknown capability: \(capabilityID)")
                    }
                }
            }
        }
    }

    func testExactBundleIdentifierMatches() {
        let app = FrontmostApplication(
            name: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            icon: nil
        )
        let matcher = ShortcutProfile.ApplicationMatcher(
            bundleIdentifiers: ["com.microsoft.VSCode"]
        )

        XCTAssertTrue(ApplicationMatcher.matches(app, matcher: matcher))
    }

    func testBundleIdentifierGlobMatchesVersionedApplication() {
        let app = FrontmostApplication(
            name: "IntelliJ IDEA 2026.2 EAP",
            bundleIdentifier: "com.jetbrains.intellij-EAP",
            icon: nil
        )
        let matcher = ShortcutProfile.ApplicationMatcher(
            bundleIdentifierPatterns: ["com.jetbrains.intellij*"]
        )

        XCTAssertTrue(ApplicationMatcher.matches(app, matcher: matcher))
    }

    func testDuplicateShortcutIsRejected() throws {
        let shortcut = ShortcutProfile.Shortcut(
            id: "definition",
            action: "정의로 이동",
            keys: ["F12"]
        )
        let profile = ShortcutProfile(
            id: "test.editor",
            name: "Test",
            application: .init(bundleIdentifiers: ["test.editor"]),
            metadata: .init(version: "1.0.0", author: "Test"),
            groups: [
                .init(id: "one", title: "One", shortcuts: [shortcut]),
                .init(id: "two", title: "Two", shortcuts: [shortcut])
            ]
        )

        XCTAssertThrowsError(
            try ProfileValidator.validate(
                ShortcutCatalog(schemaVersion: "1.0", profiles: [profile])
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileValidationError,
                .duplicateShortcutID(profile: "test.editor", shortcut: "definition")
            )
        }
    }

    func testCustomHotKeyDisplayAndSerialization() throws {
        let binding = HotKeyBinding(
            keyCode: 2,
            modifiers: UInt32(controlKey | optionKey | shiftKey),
            keyLabel: "D"
        )

        XCTAssertEqual(binding.displayKeys, ["⌃", "⌥", "⇧", "D"])
        XCTAssertEqual(binding.displayName, "⌃⌥⇧D")
        XCTAssertEqual(try JSONDecoder().decode(
            HotKeyBinding.self,
            from: JSONEncoder().encode(binding)
        ), binding)
    }

    @MainActor
    func testUserProfileOverridesProviderProfile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("devigator-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let builtInURL = root.appendingPathComponent("built-in.json")
        try encodedCatalog(name: "Built-in").write(to: builtInURL)

        let store = ProfileStore(profilesDirectory: root.appendingPathComponent("Profiles"), builtInCatalogURL: builtInURL)
        let providerURL = store.providerProfilesDirectory.appendingPathComponent("provider.devigator.json")
        let userURL = store.userProfilesDirectory.appendingPathComponent("user.devigator.json")
        try encodedCatalog(name: "Provider").write(to: providerURL)
        try encodedCatalog(name: "User").write(to: userURL)
        store.reload()

        let loaded = store.profile(for: FrontmostApplication(
            name: "Test Editor",
            bundleIdentifier: "test.editor",
            icon: nil
        ))
        XCTAssertEqual(loaded?.profile.name, "User")
        XCTAssertEqual(loaded?.source, .user)
    }

    @MainActor
    func testInvalidProviderDoesNotHideValidProfiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("devigator-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let builtInURL = root.appendingPathComponent("built-in.json")
        try encodedCatalog(name: "Built-in").write(to: builtInURL)

        let store = ProfileStore(profilesDirectory: root.appendingPathComponent("Profiles"), builtInCatalogURL: builtInURL)
        try Data("not-json".utf8).write(
            to: store.providerProfilesDirectory.appendingPathComponent("broken.devigator.json")
        )
        store.reload()

        XCTAssertEqual(store.profiles.first?.profile.name, "Built-in")
        XCTAssertNotNil(store.lastError)
    }

    private func encodedCatalog(name: String) throws -> Data {
        let profile = ShortcutProfile(
            id: "test.editor",
            name: name,
            application: .init(bundleIdentifiers: ["test.editor"], applicationNames: ["Test Editor"]),
            metadata: .init(version: "1.0.0", author: "Test"),
            groups: [
                .init(id: "navigation", title: "Navigation", shortcuts: [
                    .init(id: "definition", action: "Definition", keys: ["F12"])
                ])
            ]
        )
        return try JSONEncoder().encode(ShortcutCatalog(schemaVersion: "1.0", profiles: [profile]))
    }
}

private extension Data {
    func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try write(to: url, options: .atomic)
    }
}
