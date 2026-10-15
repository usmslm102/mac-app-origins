import Foundation
import Testing
@testable import AppOrigins

@Suite(.serialized)
struct GitHubReleaseClientTests {
    @Test func comparesNumericComponentsAndEquivalentVersions() throws {
        let oneTwo = try #require(ReleaseVersion("1.2"))
        let oneTwoZero = try #require(ReleaseVersion("v1.2.0"))
        #expect(oneTwo == oneTwoZero)
        #expect(Set([oneTwo, oneTwoZero]).count == 1)
        #expect(try #require(ReleaseVersion("1.10.0")) > #require(ReleaseVersion("1.9.9")))
        #expect(try #require(ReleaseVersion("2")) > #require(ReleaseVersion("1.999999999999999999999999999999")))
        #expect(try #require(ReleaseVersion("1.0.1000000000000000000000000000000")) > #require(ReleaseVersion("1.0.999999999999999999999999999999")))
    }

    @Test func followsSemVerPrereleaseOrderingAndIgnoresBuildMetadata() throws {
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        let versions = try ordered.map { try #require(ReleaseVersion($0)) }
        for (older, newer) in zip(versions, versions.dropFirst()) {
            #expect(older < newer)
        }
        #expect(try #require(ReleaseVersion("v1.2.3+build.5")) == #require(ReleaseVersion("1.2.3+other")))
        #expect(versions.first?.isPrerelease == true)
        #expect(versions.last?.isPrerelease == false)
    }

    @Test func rejectsMalformedVersions() {
        for value in ["", "v", "V1.2.3", " 1.2.3", "1.2.3 ", "release-1.2.3", "1..2", "1.2.3.4", "01.2.3", "1.-1.2", "1.2.3-", "1.2.3-01", "1.2.3-alpha..1", "1.2.3+", "1.2.3+a+b", "1.2.3-β", "1.2.3/foo", "1.2.3\n"] {
            #expect(ReleaseVersion(value) == nil, "Accepted invalid version: \(value)")
        }
    }

    @Test func fetchesStableReleaseWithCompletedDMGAndExpectedRequest() async throws {
        let client = client { request in
            #expect(request.url?.absoluteString == "https://api.github.com/repos/usmslm102/mac-app-origins/releases/latest")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
            #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "AppOrigins")
            #expect(request.timeoutInterval == 15)
            return response(request, json: payload())
        }
        let release = try #require(await client.fetchLatestRelease())
        #expect(release.version == ReleaseVersion("1.2.3"))
        #expect(release.tagName == "v1.2.3")
        #expect(release.releaseURL.absoluteString == "https://github.com/usmslm102/mac-app-origins/releases/tag/v1.2.3")
        #expect(release.downloadURL?.absoluteString == "https://github.com/usmslm102/mac-app-origins/releases/download/v1.2.3/AppOrigins.dmg")
    }

    @Test func noPublishedReleaseIsNotAnError() async throws {
        let client = client { request in response(request, status: 404) }
        #expect(try await client.fetchLatestRelease() == nil)
    }

    @Test func skipsDraftPrereleaseAndMalformedTags() async throws {
        for json in [payload(draft: true), payload(prerelease: true), payload(tag: "v1.2.3-beta.1"), payload(tag: "latest")] {
            let client = client { request in response(request, json: json) }
            #expect(try await client.fetchLatestRelease() == nil)
        }
    }

    @Test func preservesOfficialReleaseWithoutUsableDMG() async throws {
        for asset in ["", asset(state: "new"), asset(name: "SomethingElse.dmg"), asset(url: "https://example.com/AppOrigins.dmg"), asset(url: "https://github.com/usmslm102/other/releases/download/v1.2.3/AppOrigins.dmg"), asset(url: "https://github.com/usmslm102/mac-app-origins/releases/download/v1.2.2/AppOrigins.dmg")] {
            let client = client { request in response(request, json: payload(assets: asset)) }
            let release = try #require(await client.fetchLatestRelease())
            #expect(release.downloadURL == nil)
            #expect(release.version == ReleaseVersion("1.2.3"))
        }
    }

    @Test func rejectsForeignOrAmbiguousReleaseLinks() async throws {
        for url in [
            "http://github.com/usmslm102/mac-app-origins/releases/tag/v1.2.3",
            "https://github.com.evil.example/usmslm102/mac-app-origins/releases/tag/v1.2.3",
            "https://github.com/usmslm102/other/releases/tag/v1.2.3",
            "https://github.com/usmslm102/mac-app-origins/releases/tag/v9.0.0",
            "https://user@github.com/usmslm102/mac-app-origins/releases/tag/v1.2.3",
            "https://github.com:443/usmslm102/mac-app-origins/releases/tag/v1.2.3",
            "https://github.com/usmslm102/mac-app-origins/releases/tag/v1.2.3?next=evil",
            "https://github.com/usmslm102/mac-app-origins/releases/tag/v1.2.3#unverified"
        ] {
            let client = client { request in response(request, json: payload(releaseURL: url)) }
            do {
                _ = try await client.fetchLatestRelease()
                Issue.record("Accepted unsafe release URL: \(url)")
            } catch {
                #expect(error as? GitHubReleaseError == .invalidResponse)
            }
        }
    }

    @Test func distinguishesRateLimitsUnavailableAndMalformedResponses() async throws {
        let cases: [(Int, [String: String], String, GitHubReleaseError)] = [
            (403, ["X-RateLimit-Remaining": "0"], "{}", .rateLimited),
            (429, [:], "{}", .rateLimited),
            (403, [:], "{}", .unavailable(statusCode: 403)),
            (500, [:], "{}", .unavailable(statusCode: 500)),
            (200, [:], "not json", .invalidResponse),
            (200, [:], "{}", .invalidResponse)
        ]
        for (status, headers, json, expected) in cases {
            let client = client { request in response(request, status: status, headers: headers, json: json) }
            do {
                _ = try await client.fetchLatestRelease()
                Issue.record("Expected \(expected)")
            } catch {
                #expect(error as? GitHubReleaseError == expected)
            }
        }
    }

    @Test func releaseCacheRoundTripsAndRejectsUnsafeOrPrereleaseEntries() throws {
        let release = try #require(AppRelease(tagName: "v1.2.3", releaseURL: URL(string: "https://github.com/usmslm102/mac-app-origins/releases/tag/v1.2.3")!))
        let data = try JSONEncoder().encode(release)
        #expect(try JSONDecoder().decode(AppRelease.self, from: data) == release)

        for json in [
            #"{"tagName":"v1.2.3","releaseURL":"https://evil.example/update"}"#,
            #"{"tagName":"v1.2.3-beta","releaseURL":"https://github.com/usmslm102/mac-app-origins/releases/tag/v1.2.3-beta"}"#,
            #"{"tagName":"v1.2.3","releaseURL":"https://github.com/usmslm102/mac-app-origins/releases/tag/v1.2.3","downloadURL":"https://evil.example/AppOrigins.dmg"}"#
        ] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(AppRelease.self, from: Data(json.utf8))
            }
        }
    }

    private func client(handler: @escaping GitHubURLProtocolStub.Handler) -> GitHubReleaseClient {
        GitHubURLProtocolStub.store.set(handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GitHubURLProtocolStub.self]
        return GitHubReleaseClient(session: URLSession(configuration: configuration))
    }
}

private func response(_ request: URLRequest, status: Int = 200, headers: [String: String] = [:], json: String = "{}") -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, Data(json.utf8))
}

private func payload(tag: String = "v1.2.3", draft: Bool = false, prerelease: Bool = false, releaseURL: String = "https://github.com/usmslm102/mac-app-origins/releases/tag/v1.2.3", assets: String = asset()) -> String {
    """
    {"tag_name":"\(tag)","html_url":"\(releaseURL)","draft":\(draft),"prerelease":\(prerelease),"assets":[\(assets)]}
    """
}

private func asset(name: String = "AppOrigins.dmg", state: String = "uploaded", url: String = "https://github.com/usmslm102/mac-app-origins/releases/download/v1.2.3/AppOrigins.dmg") -> String {
    """
    {"name":"\(name)","state":"\(state)","browser_download_url":"\(url)"}
    """
}

private final class GitHubURLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    static let store = HandlerStore()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.store.get()(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    final class HandlerStore: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func set(_ handler: @escaping Handler) {
            lock.lock()
            defer { lock.unlock() }
            self.handler = handler
        }

        func get() -> Handler {
            lock.lock()
            defer { lock.unlock() }
            return handler ?? { _ in throw URLError(.unknown) }
        }
    }
}
