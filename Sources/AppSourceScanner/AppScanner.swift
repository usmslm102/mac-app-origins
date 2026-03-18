import Foundation

struct AppScanner {
    func scanApplications() -> [ScannedApp] {
        let brewApps = loadBrewCasks()
        let appStoreApps = loadMasApps()
        let applicationURLs = loadApplicationURLs()

        let applications = applicationURLs.compactMap { appURL in
            let appName = appURL.deletingPathExtension().lastPathComponent
            let source = detectSource(for: appURL, appName: appName, brewApps: brewApps, appStoreApps: appStoreApps)
            return ScannedApp(
                name: appName,
                kind: .application,
                bundleIdentifier: bundleIdentifier(for: appURL),
                version: version(for: appURL),
                securityStatus: securityStatus(for: appURL, source: source),
                sizeInBytes: allocatedSize(for: appURL),
                path: appURL.path,
                source: source
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

    private func loadBrewFormulae() -> [ScannedApp] {
        guard let output = Shell.run("brew", arguments: ["list", "--formula"]) else {
            return []
        }

        let versions = loadBrewFormulaVersions()
        let cellarPath = Shell.run("brew", arguments: ["--cellar"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/opt/homebrew/Cellar"

        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { formula in
                let version = versions[formula] ?? "Installed"
                let path = URL(fileURLWithPath: cellarPath).appendingPathComponent(formula).path
                return ScannedApp(
                    name: formula,
                    kind: .cliTool,
                    bundleIdentifier: formula,
                    version: version,
                    securityStatus: .notApplicable,
                    sizeInBytes: allocatedSize(for: URL(fileURLWithPath: path)),
                    path: path,
                    source: .homebrew
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

    private func securityStatus(for appURL: URL, source: AppSource) -> SecurityStatus {
        if source == .appStore {
            return .appStore
        }

        guard let result = Shell.runDetailed(
            "/usr/bin/codesign",
            arguments: ["-dv", "--verbose=4", appURL.path]
        ) else {
            return .unsigned
        }

        let output = result.combinedOutput.lowercased()

        if result.terminationStatus != 0 {
            if output.contains("not signed at all") || output.contains("code object is not signed") {
                return .unsigned
            }

            return .unsigned
        }

        if output.contains("signature=adhoc") || output.contains("flags=0x2(adhoc)") || output.contains("flags=0x20002(adhoc") {
            return .adHoc
        }

        return .signed
    }

    private func allocatedSize(for url: URL) -> Int64? {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]

        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            return nil
        }

        if values.isRegularFile == true {
            return fileSize(from: values)
        }

        if values.isDirectory == true {
            return directoryAllocatedSize(for: url, resourceKeys: resourceKeys)
        }

        return fileSize(from: values)
    }

    private func directoryAllocatedSize(for directoryURL: URL, resourceKeys: Set<URLResourceKey>) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys)
        ) else {
            return nil
        }

        var totalSize: Int64 = 0
        var foundAnyEntry = false

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }

            if values.isDirectory == true {
                continue
            }

            if let fileSize = fileSize(from: values) {
                totalSize += fileSize
                foundAnyEntry = true
            }
        }

        return foundAnyEntry ? totalSize : 0
    }

    private func fileSize(from values: URLResourceValues) -> Int64? {
        if let totalAllocatedSize = values.totalFileAllocatedSize {
            return Int64(totalAllocatedSize)
        }

        if let allocatedSize = values.fileAllocatedSize {
            return Int64(allocatedSize)
        }

        if let fileSize = values.fileSize {
            return Int64(fileSize)
        }

        return nil
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
    struct Result {
        let terminationStatus: Int32
        let standardOutput: String
        let standardError: String

        var combinedOutput: String {
            if standardOutput.isEmpty {
                return standardError
            }

            if standardError.isEmpty {
                return standardOutput
            }

            return "\(standardOutput)\n\(standardError)"
        }
    }

    private static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    static func run(_ command: String, arguments: [String]) -> String? {
        guard let result = runDetailed(command, arguments: arguments), result.terminationStatus == 0 else {
            return nil
        }

        return result.standardOutput
    }

    static func runDetailed(_ command: String, arguments: [String]) -> Result? {
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

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        return Result(
            terminationStatus: process.terminationStatus,
            standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
            standardError: String(data: stderrData, encoding: .utf8) ?? ""
        )
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
