import Foundation

/// Numeric app versions with SemVer prerelease ordering. A missing minor or patch
/// component is treated as zero, and build metadata does not affect ordering.
struct ReleaseVersion: Comparable, Hashable, Codable, Sendable, CustomStringConvertible {
    let description: String
    private let components: [String]
    private let prerelease: [String]

    var isPrerelease: Bool { !prerelease.isEmpty }

    init?(_ value: String) {
        let unprefixed = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let buildParts = unprefixed.split(separator: "+", omittingEmptySubsequences: false)
        guard (1...2).contains(buildParts.count),
              buildParts.count == 1 || Self.validIdentifiers(String(buildParts[1]), allowLeadingZeros: true) else {
            return nil
        }

        let versionParts = buildParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = versionParts[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(core.count), core.allSatisfy(Self.validNumber) else { return nil }
        let prereleaseString = versionParts.count == 2 ? String(versionParts[1]) : nil
        if let prereleaseString,
           !Self.validIdentifiers(prereleaseString, allowLeadingZeros: false) {
            return nil
        }

        var normalized = core
        while normalized.count > 1, normalized.last == "0" {
            normalized.removeLast()
        }
        components = normalized
        prerelease = prereleaseString?.split(separator: ".").map(String.init) ?? []
        description = String(buildParts[0])
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.components == rhs.components && lhs.prerelease == rhs.prerelease
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : "0"
            let right = index < rhs.components.count ? rhs.components[index] : "0"
            if left != right { return numericLessThan(left, right) }
        }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftIsNumeric = left.utf8.allSatisfy(isDigit)
            let rightIsNumeric = right.utf8.allSatisfy(isDigit)
            if leftIsNumeric && rightIsNumeric { return numericLessThan(left, right) }
            if leftIsNumeric != rightIsNumeric { return leftIsNumeric }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(components)
        hasher.combine(prerelease)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let version = Self(value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid app version")
        }
        self = version
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private static func numericLessThan(_ lhs: String, _ rhs: String) -> Bool {
        lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
    }

    private static func isDigit(_ character: UInt8) -> Bool {
        (48...57).contains(character)
    }

    private static func validNumber(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy(isDigit) && (value == "0" || !value.hasPrefix("0"))
    }

    private static func validIdentifiers(_ value: String, allowLeadingZeros: Bool) -> Bool {
        value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { identifier in
            guard !identifier.isEmpty, identifier.utf8.allSatisfy({ character in
                isDigit(character) || (65...90).contains(character) || (97...122).contains(character) || character == 45
            }) else { return false }
            return allowLeadingZeros || !identifier.utf8.allSatisfy(isDigit) || validNumber(String(identifier))
        }
    }
}

/// Only official, stable releases can be created or decoded from a stored cache.
struct AppRelease: Codable, Equatable, Sendable {
    let version: ReleaseVersion
    let tagName: String
    let releaseURL: URL
    let downloadURL: URL?

    init?(tagName: String, releaseURL: URL, downloadURL: URL? = nil) {
        guard let version = ReleaseVersion(tagName), !version.isPrerelease,
              Self.isOfficialURL(releaseURL, path: "/usmslm102/mac-app-origins/releases/tag/\(tagName)"),
              downloadURL.map({ Self.isOfficialURL($0, path: "/usmslm102/mac-app-origins/releases/download/\(tagName)/AppOrigins.dmg") }) ?? true else {
            return nil
        }
        self.version = version
        self.tagName = tagName
        // Construct canonical links, rather than preserving response-supplied URLs.
        self.releaseURL = URL(string: "https://github.com/usmslm102/mac-app-origins/releases/tag/\(tagName)")!
        self.downloadURL = downloadURL == nil ? nil : URL(string: "https://github.com/usmslm102/mac-app-origins/releases/download/\(tagName)/AppOrigins.dmg")!
    }

    private enum CodingKeys: String, CodingKey {
        case tagName, releaseURL, downloadURL
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tagName = try container.decode(String.self, forKey: .tagName)
        let releaseURL = try container.decode(URL.self, forKey: .releaseURL)
        let downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL)
        guard let release = Self(tagName: tagName, releaseURL: releaseURL, downloadURL: downloadURL) else {
            throw DecodingError.dataCorruptedError(forKey: .releaseURL, in: container, debugDescription: "Invalid official AppOrigins release")
        }
        self = release
    }

    private static func isOfficialURL(_ url: URL, path: String) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == "https"
            && components.host?.lowercased() == "github.com"
            && components.user == nil && components.password == nil && components.port == nil
            && components.query == nil && components.fragment == nil
            && components.path == path
    }
}

enum GitHubReleaseError: Error, LocalizedError, Equatable {
    case rateLimited
    case unavailable(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "GitHub's update check limit has been reached. Please try again later."
        case .unavailable:
            return "GitHub is unavailable right now. Please try again later."
        case .invalidResponse:
            return "GitHub returned an update response that could not be verified."
        }
    }
}

struct GitHubReleaseClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatestRelease() async throws -> AppRelease? {
        let endpoint = URL(string: "https://api.github.com/repos/usmslm102/mac-app-origins/releases/latest")!
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AppOrigins", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GitHubReleaseError.invalidResponse }
        switch response.statusCode {
        case 200:
            break
        case 404:
            return nil
        case 429:
            throw GitHubReleaseError.rateLimited
        case 403 where response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0":
            throw GitHubReleaseError.rateLimited
        default:
            throw GitHubReleaseError.unavailable(statusCode: response.statusCode)
        }

        let payload: ReleasePayload
        do {
            payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        } catch {
            throw GitHubReleaseError.invalidResponse
        }
        guard !payload.draft, !payload.prerelease,
              let version = ReleaseVersion(payload.tagName), !version.isPrerelease else { return nil }
        guard let releaseURL = URL(string: payload.htmlURL),
              let release = AppRelease(tagName: payload.tagName, releaseURL: releaseURL) else {
            throw GitHubReleaseError.invalidResponse
        }
        // A release without a completed DMG upload can still offer release notes.
        // Untrusted or unrelated asset URLs are omitted from the download action.
        let asset = payload.assets.first { $0.name == "AppOrigins.dmg" && $0.state == "uploaded" }
        guard let asset, let downloadURL = URL(string: asset.browserDownloadURL),
              let downloadableRelease = AppRelease(tagName: payload.tagName, releaseURL: releaseURL, downloadURL: downloadURL) else {
            return release
        }
        return downloadableRelease
    }
}

private struct ReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [AssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease, assets
    }
}

private struct AssetPayload: Decodable {
    let name: String
    let state: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name, state
        case browserDownloadURL = "browser_download_url"
    }
}
