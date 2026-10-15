import Foundation

struct ScanOptions: Sendable {
    let includeSystemApplications: Bool
    let includeUserApplications: Bool
    let includeExternalVolumes: Bool

    static let `default` = ScanOptions(
        includeSystemApplications: true,
        includeUserApplications: true,
        includeExternalVolumes: false
    )
}

enum ScanMode: String, CaseIterable, Sendable {
    case quick
    case full
}

struct ScanResult: Sendable {
    let apps: [ScannedApp]
    let cacheHits: Int
    let cacheMisses: Int
}

private struct CachedAppMetadata: Sendable {
    let fingerprint: String
    let bundleIdentifier: String
    let version: String
    let securityStatus: SecurityStatus
    let sizeInBytes: Int64?
    let source: AppSource
}

private actor AppMetadataCache {
    static let shared = AppMetadataCache()
    private var entries: [String: CachedAppMetadata] = [:]

    func entry(for path: String) -> CachedAppMetadata? {
        entries[path]
    }

    func store(_ entry: CachedAppMetadata, for path: String) {
        entries[path] = entry
    }

    func clear() {
        entries.removeAll()
    }
}

struct AppScanner: Sendable {
    private let metadataBatchSize = 8

    func scanApplications(options: ScanOptions = .default, mode: ScanMode = .quick) async -> ScanResult {
        if mode == .full {
            await AppMetadataCache.shared.clear()
        }

        let brewApps = loadBrewCasks()
        let appStoreApps = loadMasApps()
        let applicationURLs = loadApplicationURLs(options: options)

        let applicationScanResult = await scanAppBundles(
            applicationURLs,
            brewApps: brewApps,
            appStoreApps: appStoreApps,
            mode: mode
        )

        let cliTools = Task.isCancelled ? [] : loadBrewFormulae()
        let sortedApps = (applicationScanResult.apps + cliTools)
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

        return ScanResult(
            apps: sortedApps,
            cacheHits: applicationScanResult.cacheHits,
            cacheMisses: applicationScanResult.cacheMisses
        )
    }

    func scanAppBundles(_ applicationURLs: [URL], brewApps: [String], appStoreApps: Set<String>, mode: ScanMode) async -> (apps: [ScannedApp], cacheHits: Int, cacheMisses: Int) {
        guard !applicationURLs.isEmpty else {
            return ([], 0, 0)
        }

        var scannedApps: [ScannedApp] = []
        var cacheHits = 0
        var cacheMisses = 0
        scannedApps.reserveCapacity(applicationURLs.count)

        for startIndex in stride(from: 0, to: applicationURLs.count, by: metadataBatchSize) {
            if Task.isCancelled {
                break
            }

            let endIndex = min(startIndex + metadataBatchSize, applicationURLs.count)
            let batch = Array(applicationURLs[startIndex ..< endIndex])

            let scannedBatch = await withTaskGroup(of: (ScannedApp, Bool)?.self, returning: [(ScannedApp, Bool)].self) { group in
                for appURL in batch {
                    group.addTask {
                        if Task.isCancelled {
                            return nil
                        }

                        return await self.makeScannedApplication(
                            for: appURL,
                            brewApps: brewApps,
                            appStoreApps: appStoreApps,
                            mode: mode
                        )
                    }
                }

                var batchResult: [(ScannedApp, Bool)] = []
                for await entry in group {
                    if let entry {
                        batchResult.append(entry)
                    }
                }

                return batchResult
            }

            for (app, usedCache) in scannedBatch {
                scannedApps.append(app)
                if usedCache {
                    cacheHits += 1
                } else {
                    cacheMisses += 1
                }
            }
        }

        return (scannedApps, cacheHits, cacheMisses)
    }

    private func makeScannedApplication(for appURL: URL, brewApps: [String], appStoreApps: Set<String>, mode: ScanMode) async -> (ScannedApp, Bool)? {
        let appName = appURL.deletingPathExtension().lastPathComponent
        let fingerprint = metadataFingerprint(for: appURL)
        let locationContext = storageLocation(for: appURL)
        let path = appURL.path
        let useCache = mode == .quick
        let source = detectSource(for: appURL, appName: appName, brewApps: brewApps, appStoreApps: appStoreApps)

        if useCache,
           let fingerprint,
           let cachedMetadata = await AppMetadataCache.shared.entry(for: path),
           cachedMetadata.fingerprint == fingerprint,
           cachedMetadata.source == source {
            return (
                ScannedApp(
                    name: appName,
                    kind: .application,
                    bundleIdentifier: cachedMetadata.bundleIdentifier,
                    version: cachedMetadata.version,
                    securityStatus: cachedMetadata.securityStatus,
                    sizeInBytes: cachedMetadata.sizeInBytes,
                    path: path,
                    source: cachedMetadata.source,
                    location: locationContext.label,
                    isExternal: locationContext.isExternal
                ),
                true
            )
        }

        let bundleMetadata = bundleMetadata(for: appURL)
        let bundleIdentifier = bundleMetadata.identifier
        let version = bundleMetadata.version
        let securityStatus = securityStatus(for: appURL, source: source)
        let sizeInBytes = allocatedSize(for: appURL)

        guard !Task.isCancelled else { return nil }

        if let fingerprint {
            await AppMetadataCache.shared.store(
                CachedAppMetadata(
                    fingerprint: fingerprint,
                    bundleIdentifier: bundleIdentifier,
                    version: version,
                    securityStatus: securityStatus,
                    sizeInBytes: sizeInBytes,
                    source: source
                ),
                for: path
            )
        }

        return (
            ScannedApp(
                name: appName,
                kind: .application,
                bundleIdentifier: bundleIdentifier,
                version: version,
                securityStatus: securityStatus,
                sizeInBytes: sizeInBytes,
                path: path,
                source: source,
                location: locationContext.label,
                isExternal: locationContext.isExternal
            ),
            false
        )
    }

    private func loadApplicationURLs(options: ScanOptions) -> [URL] {
        var searchRoots: [URL] = []
        if options.includeSystemApplications {
            searchRoots.append(URL(fileURLWithPath: "/Applications"))
        }
        if options.includeUserApplications {
            searchRoots.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"))
        }
        if options.includeExternalVolumes {
            searchRoots.append(contentsOf: externalApplicationRoots())
        }

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
                guard !Task.isCancelled else { return Array(urls) }
                guard url.pathExtension.lowercased() == "app",
                      (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                urls.insert(url.standardizedFileURL)
            }
        }

        return Array(urls)
    }

    private func externalApplicationRoots() -> [URL] {
        let volumeKeys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsLocalKey]
        guard let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: volumeKeys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        return mountedVolumes.compactMap { volumeURL in
            guard volumeURL.path != "/" else {
                return nil
            }

            guard let values = try? volumeURL.resourceValues(forKeys: Set(volumeKeys)),
                  values.volumeIsLocal == true,
                  values.volumeIsInternal == false else {
                return nil
            }

            let applicationsURL = volumeURL.appendingPathComponent("Applications", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: applicationsURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }

            return applicationsURL
        }
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
                return ScannerLogic.normalizedTokenString(ScannerLogic.stripMasVersionSuffix(from: fullName))
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
                let locationContext = storageLocation(for: URL(fileURLWithPath: path))
                return ScannedApp(
                    name: formula,
                    kind: .cliTool,
                    bundleIdentifier: formula,
                    version: version,
                    securityStatus: .notApplicable,
                    sizeInBytes: allocatedSize(for: URL(fileURLWithPath: path)),
                    path: path,
                    source: .homebrew,
                    location: locationContext.label,
                    isExternal: locationContext.isExternal
                )
            }
    }

    private func storageLocation(for itemURL: URL) -> (label: String, isExternal: Bool) {
        ScannerLogic.storageLocation(forPath: itemURL.path)
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
        ScannerLogic.detectSource(
            appName: appName,
            brewApps: brewApps,
            appStoreApps: appStoreApps,
            hasAppStoreReceipt: hasAppStoreReceipt(appURL)
        )
    }

    private func hasAppStoreReceipt(_ appURL: URL) -> Bool {
        let receiptURL = appURL.appendingPathComponent("Contents/_MASReceipt/receipt")
        return (try? receiptURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func bundleMetadata(for appURL: URL) -> (identifier: String, version: String) {
        // Bundle caches Info.plist values for a URL, even after an app updates in place.
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        let info = (try? Data(contentsOf: infoURL))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
        let identifier = info["CFBundleIdentifier"] as? String ?? "Unknown"
        let shortVersion = info["CFBundleShortVersionString"] as? String
        let buildNumber = info["CFBundleVersion"] as? String
        switch (shortVersion?.isEmpty == false ? shortVersion : nil, buildNumber?.isEmpty == false ? buildNumber : nil) {
        case let (version?, build?) where version != build:
            return (identifier, "\(version) (\(build))")
        case let (version?, _):
            return (identifier, version)
        case let (_, build?):
            return (identifier, build)
        default:
            return (identifier, "Unknown")
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
            guard !Task.isCancelled else { return nil }
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

    private func metadataFingerprint(for appURL: URL) -> String? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey, .fileSizeKey]
        guard (try? appURL.resourceValues(forKeys: keys)) != nil else {
            return nil
        }

        // Updating an existing nested file does not change the .app directory date.
        let paths = ["", "Contents", "Contents/Info.plist", "Contents/MacOS", "Contents/_CodeSignature/CodeResources", "Contents/_MASReceipt/receipt"]
        return paths.map { path in
            let url = path.isEmpty ? appURL : appURL.appendingPathComponent(path)
            guard let values = try? url.resourceValues(forKeys: keys) else { return "\(path):missing" }
            let modifiedAt = values.contentModificationDate ?? values.creationDate ?? .distantPast
            return "\(path):\(modifiedAt.timeIntervalSinceReferenceDate):\(values.fileSize ?? 0)"
        }.joined(separator: "|")
    }
}

enum Shell {
    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func store(_ data: Data) {
            lock.lock()
            self.data = data
            lock.unlock()
        }

        func string() -> String {
            lock.lock()
            defer { lock.unlock() }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

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
        } catch {
            return nil
        }

        // Both pipes must drain while the child runs; waiting first can fill a
        // pipe and leave both the process and the scanner waiting forever.
        let readers = DispatchGroup()
        let stdoutBuffer = OutputBuffer()
        let stderrBuffer = OutputBuffer()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutBuffer.store(stdout.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBuffer.store(stderr.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        process.waitUntilExit()
        readers.wait()

        return Result(
            terminationStatus: process.terminationStatus,
            standardOutput: stdoutBuffer.string(),
            standardError: stderrBuffer.string()
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
