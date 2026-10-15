import Foundation

enum ScannerLogic {
    static func detectSource(appName: String, brewApps: [String], appStoreApps: Set<String>, hasAppStoreReceipt: Bool) -> AppSource {
        let normalizedName = normalizedTokenString(appName)

        // A receipt is stronger evidence than a name match against a cask.
        if hasAppStoreReceipt || appStoreApps.contains(normalizedName) {
            return .appStore
        }

        guard !normalizedName.isEmpty else {
            return .manual
        }

        let appPhrase = " \(normalizedName) "
        for brewApp in brewApps {
            let normalizedBrewName = normalizedTokenString(brewApp)
            guard !normalizedBrewName.isEmpty else { continue }
            // Match whole words, so casks such as "arc" do not claim "Spark".
            let brewPhrase = " \(normalizedBrewName) "
            if appPhrase.contains(brewPhrase) || brewPhrase.contains(appPhrase) {
                return .homebrew
            }
        }

        return .manual
    }

    static func storageLocation(forPath path: String) -> (label: String, isExternal: Bool) {
        let components = URL(fileURLWithPath: path).pathComponents
        guard components.count > 2, components[1] == "Volumes" else {
            return ("Internal Disk", false)
        }

        return ("External: \(components[2])", true)
    }

    static func duplicateKey(kind: InstallKind, bundleIdentifier: String, name: String) -> String? {
        guard kind == .application else {
            return nil
        }

        let normalizedIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if !normalizedIdentifier.isEmpty, normalizedIdentifier != "unknown" {
            return "bundle:\(normalizedIdentifier)"
        }

        return "name:\(normalizedTokenString(name))"
    }

    static func normalizedTokenString(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func stripMasVersionSuffix(from value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let versionRange = trimmedValue.range(
            of: #"\s+\([^)]+\)$"#,
            options: .regularExpression
        ) else {
            return trimmedValue
        }

        return String(trimmedValue[..<versionRange.lowerBound])
    }
}
