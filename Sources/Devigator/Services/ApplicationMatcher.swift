import AppKit
import Foundation

struct FrontmostApplication: Equatable {
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?
}

enum ApplicationMatcher {
    static func profile(
        for application: FrontmostApplication,
        in profiles: [LoadedProfile]
    ) -> LoadedProfile? {
        profiles.max { lhs, rhs in
            matchScore(application, loaded: lhs) < matchScore(application, loaded: rhs)
        }.flatMap { matchScore(application, loaded: $0) >= 0 ? $0 : nil }
    }

    static func matches(
        _ application: FrontmostApplication,
        matcher: ShortcutProfile.ApplicationMatcher
    ) -> Bool {
        matchScore(application, matcher: matcher) >= 0
    }

    private static func matchScore(
        _ application: FrontmostApplication,
        loaded: LoadedProfile
    ) -> Int {
        let sourceScore: Int
        switch loaded.source {
        case .builtIn: sourceScore = 0
        case .provider: sourceScore = 100_000
        case .user: sourceScore = 200_000
        }
        let matcherScore = matchScore(application, matcher: loaded.profile.application)
        guard matcherScore >= 0 else { return -1 }
        return sourceScore + matcherScore + ((loaded.profile.priority ?? 0) * 10)
    }

    private static func matchScore(
        _ application: FrontmostApplication,
        matcher: ShortcutProfile.ApplicationMatcher
    ) -> Int {
        if let bundleID = application.bundleIdentifier?.lowercased() {
            if matcher.bundleIdentifiers.contains(where: { $0.lowercased() == bundleID }) {
                return 30_000
            }
            let matchingPatterns = matcher.bundleIdentifierPatterns.filter { globMatches($0, value: bundleID) }
            if let mostSpecific = matchingPatterns.max(by: { literalLength($0) < literalLength($1) }) {
                return 20_000 + literalLength(mostSpecific)
            }
        }

        if matcher.applicationNames.contains(where: {
            $0.compare(application.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return 10_000
        }
        return -1
    }

    private static func globMatches(_ pattern: String, value: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern.lowercased())
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return value.range(of: "^\(escaped)$", options: .regularExpression) != nil
    }

    private static func literalLength(_ pattern: String) -> Int {
        pattern.filter { $0 != "*" && $0 != "?" }.count
    }
}
