import Foundation
import Testing
@testable import AppOrigins

@Suite @MainActor
struct AppUpdateCheckerTests {
    @Test func comparesNumericVersionsAndIgnoresTrailingZeroComponents() async throws {
        let cases = [
            (installed: "1.9", latest: "1.10", update: true),
            (installed: "1.10", latest: "1.9", update: false),
            (installed: "2.0", latest: "2.0.0", update: false),
            (installed: "2.0.0", latest: "2.0", update: false),
            (installed: "2.0.9", latest: "2.0.10", update: true),
            (installed: "10.0", latest: "2.0", update: false)
        ]

        for scenario in cases {
            let (defaults, suite) = isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: suite) }
            let release = try makeRelease(scenario.latest)
            let checker = AppUpdateChecker(
                currentVersion: scenario.installed,
                defaults: defaults,
                fetchLatestRelease: { release }
            )

            await checker.checkForUpdates()

            #expect((checker.availableRelease != nil) == scenario.update,
                    "Installed \(scenario.installed), latest \(scenario.latest)")
            #expect(checker.state == (scenario.update ? .updateAvailable : .upToDate))
            #expect(!checker.isChecking)
            #expect(checker.lastCheckError == nil)
        }
    }

    @Test func successfulCheckIsCachedAndDailyThrottleSurvivesRelaunch() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let release = try makeRelease("2.0")
        let counter = UpdateFetchCounter()
        let first = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { checkedAt },
            fetchLatestRelease: { await counter.record(); return release }
        )

        await first.checkIfNeeded()
        #expect(first.lastCheckedAt == checkedAt)
        #expect(first.state == .updateAvailable)

        let later = checkedAt.addingTimeInterval(23 * 60 * 60)
        let relaunched = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { later },
            fetchLatestRelease: { await counter.record(); return release }
        )
        #expect(relaunched.availableRelease != nil)
        #expect(relaunched.state == .updateAvailable)
        #expect(relaunched.lastCheckedAt == checkedAt)

        await relaunched.checkIfNeeded()

        #expect(await counter.count == 1)
        #expect(relaunched.lastCheckedAt == checkedAt)
    }

    @Test func cachedReleaseIsComparedAgainAfterInstallingTheUpdate() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let release = try makeRelease("2.0")
        let first = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults,
            fetchLatestRelease: { release }
        )
        await first.checkForUpdates()
        #expect(first.availableRelease != nil)

        let updated = AppUpdateChecker(
            currentVersion: "2.0.0", defaults: defaults,
            fetchLatestRelease: { release }
        )

        #expect(updated.availableRelease == nil)
        #expect(updated.state == .upToDate)
        #expect(updated.lastCheckedAt == first.lastCheckedAt)
    }

    @Test func automaticChecksResumeAfterADayAndRecoverFromAFutureTimestamp() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let release = try makeRelease("2.0")
        let counter = UpdateFetchCounter()
        let initial = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { checkedAt },
            fetchLatestRelease: { await counter.record(); return release }
        )
        await initial.checkIfNeeded()

        let nextDay = checkedAt.addingTimeInterval(24 * 60 * 60)
        let expired = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { nextDay },
            fetchLatestRelease: { await counter.record(); return release }
        )
        await expired.checkIfNeeded()
        #expect(await counter.count == 2)
        #expect(expired.lastCheckedAt == nextDay)

        let clockMovedBack = checkedAt.addingTimeInterval(-60)
        let futureTimestamp = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { clockMovedBack },
            fetchLatestRelease: { await counter.record(); return release }
        )
        await futureTimestamp.checkIfNeeded()
        #expect(await counter.count == 3)
        #expect(futureTimestamp.lastCheckedAt == clockMovedBack)
    }

    @Test func disablingAutomaticChecksPersistsAndManualChecksStillWork() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let release = try makeRelease("2.0")
        let counter = UpdateFetchCounter()
        let first = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults,
            fetchLatestRelease: { await counter.record(); return release }
        )
        first.automaticallyChecksForUpdates = false

        let relaunched = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults,
            fetchLatestRelease: { await counter.record(); return release }
        )
        #expect(!relaunched.automaticallyChecksForUpdates)
        await relaunched.checkIfNeeded()
        #expect(await counter.count == 0)

        await relaunched.checkForUpdates()
        await relaunched.checkForUpdates()

        #expect(await counter.count == 2)
        #expect(relaunched.state == .updateAvailable)
    }

    @Test func noPublishedReleaseClearsAnEarlierUpdateAndRecordsSuccess() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let release = try makeRelease("2.0")
        let first = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults,
            fetchLatestRelease: { release }
        )
        await first.checkForUpdates()
        #expect(first.availableRelease != nil)

        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let noRelease = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { checkedAt },
            fetchLatestRelease: { nil }
        )
        await noRelease.checkForUpdates()

        #expect(noRelease.availableRelease == nil)
        #expect(noRelease.state == .noRelease)
        #expect(noRelease.lastCheckedAt == checkedAt)
        #expect(noRelease.lastCheckError == nil)

        let relaunched = AppUpdateChecker(currentVersion: "1.0", defaults: defaults)
        #expect(relaunched.availableRelease == nil)
        #expect(relaunched.lastCheckedAt == checkedAt)
    }

    @Test func transientFailureRetainsTheCachedUpdateAndSuccessfulTimestamp() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let release = try makeRelease("2.0")
        let first = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { checkedAt },
            fetchLatestRelease: { release }
        )
        await first.checkForUpdates()

        let later = checkedAt.addingTimeInterval(60)
        let failed = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { later },
            fetchLatestRelease: { throw UpdateFetchFailure.unavailable }
        )
        await failed.checkForUpdates()

        #expect(failed.state == .failed)
        #expect(failed.availableRelease != nil)
        #expect(failed.lastCheckedAt == checkedAt)
        #expect(failed.lastCheckError?.isEmpty == false)
        #expect(!failed.isChecking)

        let relaunched = AppUpdateChecker(currentVersion: "1.0", defaults: defaults)
        #expect(relaunched.availableRelease != nil)
        #expect(relaunched.lastCheckedAt == checkedAt)
    }

    @Test func failuresAreThrottledAcrossRelaunchButManualRetryIsAllowed() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let attemptedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let counter = UpdateFetchCounter()
        let first = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { attemptedAt },
            fetchLatestRelease: {
                await counter.record()
                throw UpdateFetchFailure.unavailable
            }
        )

        await first.checkIfNeeded()

        #expect(await counter.count == 1)
        #expect(first.state == .failed)
        #expect(first.lastCheckedAt == nil)

        let later = attemptedAt.addingTimeInterval(60 * 60)
        let relaunched = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { later },
            fetchLatestRelease: {
                await counter.record()
                throw UpdateFetchFailure.unavailable
            }
        )

        await relaunched.checkIfNeeded()

        #expect(await counter.count == 1)
        #expect(relaunched.lastCheckedAt == nil)

        await relaunched.checkForUpdates()

        #expect(await counter.count == 2)
        #expect(relaunched.state == .failed)
        #expect(relaunched.lastCheckedAt == nil)
    }

    @Test func missingOrInvalidInstalledVersionAvoidsNetworkRequests() async {
        let versions: [String?] = [nil, "", "unknown", "1..0"]
        for version in versions {
            let (defaults, suite) = isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: suite) }
            let counter = UpdateFetchCounter()
            let checker = AppUpdateChecker(
                currentVersion: version, defaults: defaults,
                fetchLatestRelease: { await counter.record(); return nil }
            )

            await checker.checkIfNeeded()
            await checker.checkForUpdates()

            #expect(checker.state == .unversioned)
            #expect(checker.availableRelease == nil)
            #expect(checker.lastCheckedAt == nil)
            #expect(!checker.isChecking)
            #expect(await counter.count == 0)
        }
    }

    @Test func cancellationRetainsSuccessfulMetadataWithoutShowingAnError() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let release = try makeRelease("2.0")
        let first = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { checkedAt },
            fetchLatestRelease: { release }
        )
        await first.checkForUpdates()

        let later = checkedAt.addingTimeInterval(60)
        let cancelled = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults, now: { later },
            fetchLatestRelease: { throw CancellationError() }
        )
        await cancelled.checkForUpdates()

        #expect(cancelled.availableRelease != nil)
        #expect(cancelled.lastCheckedAt == checkedAt)
        #expect(cancelled.lastCheckError == nil)
        #expect(cancelled.state == .updateAvailable)
        #expect(!cancelled.isChecking)
    }

    @Test func concurrentChecksShareTheAlreadyRunningFetch() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let release = try makeRelease("2.0")
        let latch = UpdateFetchLatch()
        let checker = AppUpdateChecker(
            currentVersion: "1.0", defaults: defaults,
            fetchLatestRelease: { await latch.fetch(release) }
        )

        let firstCheck = Task { await checker.checkForUpdates() }
        await latch.waitUntilStarted()
        #expect(checker.isChecking)
        #expect(checker.state == .checking)

        await checker.checkForUpdates()
        #expect(await latch.count == 1)
        #expect(checker.isChecking)

        await latch.finishFetch()
        await firstCheck.value

        #expect(checker.state == .updateAvailable)
        #expect(checker.availableRelease != nil)
        #expect(!checker.isChecking)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "AppOriginsUpdateTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func makeRelease(_ version: String) throws -> AppRelease {
        try #require(AppRelease(
            tagName: "v\(version)",
            releaseURL: URL(string: "https://github.com/usmslm102/mac-app-origins/releases/tag/v\(version)")!
        ))
    }
}

private actor UpdateFetchCounter {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

private enum UpdateFetchFailure: Error {
    case unavailable
}

private actor UpdateFetchLatch {
    private(set) var count = 0
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var fetchWaiter: CheckedContinuation<Void, Never>?

    func fetch(_ release: AppRelease) async -> AppRelease? {
        count += 1
        // An unexpected second request returns immediately so a broken guard fails
        // the test instead of leaving the test suspended.
        guard count == 1 else { return release }
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { fetchWaiter = $0 }
        return release
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finishFetch() {
        fetchWaiter?.resume()
        fetchWaiter = nil
    }
}
