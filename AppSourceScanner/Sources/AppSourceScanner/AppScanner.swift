import AppKit
import Foundation

struct AppScanner {
    func scanApplications() -> [InstalledApp] {
        let brewApps = loadBrewCasks()
        let appStoreApps = loadMasApps()
        let applicationURLs = loadApplicationURLs()

        let applications = applicationURLs.compactMap { appURL in
            let appName = appURL.deletingPathExtension().lastPathComponent
            let source = detectSource(for: appURL, appName: appName, brewApps: brewApps, appStoreApps: appStoreApps)
            return InstalledApp(
                name: appName,
                kind: .application,
                bundleIdentifier: bundleIdentifier(for: appURL),
                version: version(for: appURL),
                path: appURL.path,
                source: source,
                icon: NSWorkspace.shared.icon(forFile: appURL.path)
            )
        }

        let cliTools = loadBrewFormulae()

        return (applications + cliTools)
            .sorted { lhs, rhs in
                switch lhs.name.localizedCaseInsensitiveCompare(rhs.name) {
                case .orderedSame:
                    return lhs.kind.rawValue < rhs.kind.rawValue
                case .orderedAscending:
                    return true
                case .orderedDescending:
                    return false
                }
            }
    }

    private func loadApplicationURLs() -> [URL] {
        let searchRoots = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        let keys: [URLResourceKey] = [.isApplicationKey, .isDirectoryKey]
        var urls = Set<URL>()

        for root in searchRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                urls.insert(url)
            }
        }

        return Array(urls)
    }

    private func loadBrewCasks() -> [String] {
        guard let output = Shell.run("brew", arguments: ["list", "--cask"]) else {
            return []
        }

        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    private func loadMasApps() -> Set<String> {
        guard let output = Shell.run("mas", arguments: ["list"]) else {
            return []
        }

        let names = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                let fullName = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                return normalize(stripMasVersionSuffix(from: fullName))
            }

        return Set(names)
    }

    private func loadBrewFormulae() -> [InstalledApp] {
        guard let output = Shell.run("brew", arguments: ["list", "--formula"]) else {
            return []
        }

        let versions = loadBrewFormulaVersions()
        let cellarPath = Shell.run("brew", arguments: ["--cellar"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/opt/homebrew/Cellar"
        let icon = cliIcon()

        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { formula in
                let version = versions[formula] ?? "Installed"
                let path = URL(fileURLWithPath: cellarPath).appendingPathComponent(formula).path
                return InstalledApp(
                    name: formula,
                    kind: .cliTool,
                    bundleIdentifier: formula,
                    version: version,
                    path: path,
                    source: .homebrew,
                    icon: icon
                )
            }
    }

    private func loadBrewFormulaVersions() -> [String: String] {
        guard let output = Shell.run("brew", arguments: ["list", "--versions", "--formula"]) else {
            return [:]
        }

        return output
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { partialResult, line in
                let parts = line.split(separator: " ").map(String.init)
                guard let name = parts.first else { return }
                let version = parts.dropFirst().joined(separator: ", ")
                partialResult[name] = version.isEmpty ? "Installed" : version
            }
    }

    private func detectSource(for appURL: URL, appName: String, brewApps: [String], appStoreApps: Set<String>) -> AppSource {
        let normalizedName = normalize(appName)

        for brewApp in brewApps {
            let normalizedBrewName = normalize(brewApp)
            if normalizedName.contains(normalizedBrewName) || normalizedBrewName.contains(normalizedName) {
                return .homebrew
            }
        }

        if appStoreApps.contains(normalizedName) {
            return .appStore
        }

        if hasAppStoreReceipt(appURL) {
            return .appStore
        }

        return .manual
    }

    private func hasAppStoreReceipt(_ appURL: URL) -> Bool {
        guard let output = Shell.run(
            "mdls",
            arguments: ["-raw", "-name", "kMDItemAppStoreHasReceipt", appURL.path]
        ) else {
            return false
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private func bundleIdentifier(for appURL: URL) -> String {
        Bundle(url: appURL)?.bundleIdentifier ?? "Unknown"
    }

    private func version(for appURL: URL) -> String {
        guard let bundle = Bundle(url: appURL) else {
            return "Unknown"
        }

        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion?.isEmpty == false ? shortVersion : nil, buildNumber?.isEmpty == false ? buildNumber : nil) {
        case let (version?, build?) where version != build:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        case let (_, build?):
            return build
        default:
            return "Unknown"
        }
    }

    private func cliIcon() -> NSImage {
        if let symbolImage = NSImage(systemSymbolName: "terminal", accessibilityDescription: "CLI Tool") {
            return symbolImage
        }

        return NSWorkspace.shared.icon(forFileType: "public.unix-executable")
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func stripMasVersionSuffix(from value: String) -> String {
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

enum Shell {
    private static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    static func run(_ command: String, arguments: [String]) -> String? {
        let process = Process()
        guard let executableURL = resolveExecutableURL(for: command) else {
            return nil
        }

        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func resolveExecutableURL(for command: String) -> URL? {
        if command.contains("/") {
            return URL(fileURLWithPath: command)
        }

        for path in searchPaths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}
