import Foundation

enum VersionPolicy {
    static let forbiddenDigit = "4"

    static func isAllowed(_ version: String) -> Bool {
        guard !version.contains(forbiddenDigit) else {
            return false
        }
        let parts = version.split(separator: ".")
        guard parts.count == 3 else {
            return false
        }
        return parts.allSatisfy { Int($0) != nil }
    }

    static func nextMinor(after version: String) -> String {
        guard let parsed = parse(version) else {
            return "0.1.0"
        }
        let major = parsed.major
        var minor = parsed.minor
        while true {
            minor += 1
            let candidate = "\(major).\(minor).0"
            if isAllowed(candidate) {
                return candidate
            }
        }
    }

    static func nextPatch(after version: String) -> String {
        guard let parsed = parse(version) else {
            return "0.1.0"
        }
        let major = parsed.major
        let minor = parsed.minor
        var patch = parsed.patch
        while true {
            patch += 1
            let candidate = "\(major).\(minor).\(patch)"
            if isAllowed(candidate) {
                return candidate
            }
        }
    }

    private struct ParsedVersion {
        let major: Int
        let minor: Int
        let patch: Int
    }

    private static func parse(_ version: String) -> ParsedVersion? {
        let parts = version.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2])
        else {
            return nil
        }
        return ParsedVersion(major: major, minor: minor, patch: patch)
    }
}
