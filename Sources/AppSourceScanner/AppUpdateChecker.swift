import AppKit
import Foundation
import SwiftUI

enum UpdateCheckState: Equatable {
    case notChecked, checking, upToDate, updateAvailable, noRelease, unversioned, failed
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    static let releasesURL = URL(string: "https://github.com/usmslm102/mac-app-origins/releases")!

    private enum DefaultsKey {
        static let automaticChecks = "updates.automaticChecks"
        static let cachedCheck = "updates.cachedCheck.v1"
        static let lastAutomaticAttempt = "updates.lastAutomaticAttempt"
    }

    private struct CachedCheck: Codable {
        let date: Date
        let release: AppRelease?
    }

    private let defaults: UserDefaults
    private let currentVersion: ReleaseVersion?
    private let now: @Sendable () -> Date
    private let fetchLatestRelease: @Sendable () async throws -> AppRelease?
    private var lastAutomaticAttempt: Date?
    let installedVersion: String?

    @Published private(set) var state: UpdateCheckState = .notChecked
    @Published private(set) var availableRelease: AppRelease?
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastCheckError: String?
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            defaults.set(automaticallyChecksForUpdates, forKey: DefaultsKey.automaticChecks)
        }
    }

    init(
        currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        fetchLatestRelease: @escaping @Sendable () async throws -> AppRelease? = {
            try await GitHubReleaseClient().fetchLatestRelease()
        }
    ) {
        self.defaults = defaults
        self.now = now
        self.fetchLatestRelease = fetchLatestRelease
        let versionString = currentVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        installedVersion = versionString?.isEmpty == false ? versionString : nil
        self.currentVersion = installedVersion.flatMap(ReleaseVersion.init)
        automaticallyChecksForUpdates = defaults.object(forKey: DefaultsKey.automaticChecks) as? Bool ?? true
        lastAutomaticAttempt = defaults.object(forKey: DefaultsKey.lastAutomaticAttempt) as? Date

        guard let currentVersion = self.currentVersion else {
            state = .unversioned
            return
        }
        if let data = defaults.data(forKey: DefaultsKey.cachedCheck),
           let cache = try? JSONDecoder().decode(CachedCheck.self, from: data) {
            lastCheckedAt = cache.date
            apply(release: cache.release, installed: currentVersion)
        }
    }

    func checkIfNeeded() async {
        guard automaticallyChecksForUpdates, !isChecking, !Task.isCancelled else { return }
        guard currentVersion != nil else { return }
        let attemptedAt = now()
        if let lastCheckedAt {
            let age = attemptedAt.timeIntervalSince(lastCheckedAt)
            // Recheck after a clock correction rather than deferring indefinitely.
            if age >= 0, age < 24 * 60 * 60 { return }
        }
        if let lastAutomaticAttempt {
            let age = attemptedAt.timeIntervalSince(lastAutomaticAttempt)
            if age >= 0, age < 24 * 60 * 60 { return }
        }
        // Failed checks also count as attempts, so reactivating the app cannot
        // repeatedly hit GitHub while offline or rate limited. Manual checks bypass this.
        let previousAttempt = lastAutomaticAttempt
        lastAutomaticAttempt = attemptedAt
        defaults.set(attemptedAt, forKey: DefaultsKey.lastAutomaticAttempt)
        await checkForUpdates()
        if Task.isCancelled {
            lastAutomaticAttempt = previousAttempt
            defaults.set(previousAttempt, forKey: DefaultsKey.lastAutomaticAttempt)
        }
    }

    func checkForUpdates() async {
        guard !isChecking, !Task.isCancelled else { return }
        guard let currentVersion else {
            state = .unversioned
            return
        }

        let previousState = state
        let previousError = lastCheckError
        isChecking = true
        state = .checking
        lastCheckError = nil
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            guard !Task.isCancelled else {
                state = previousState
                lastCheckError = previousError
                return
            }
            let checkedAt = now()
            apply(release: release, installed: currentVersion)
            lastCheckedAt = checkedAt
            if let data = try? JSONEncoder().encode(CachedCheck(date: checkedAt, release: release)) {
                defaults.set(data, forKey: DefaultsKey.cachedCheck)
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                state = previousState
                lastCheckError = previousError
                return
            }
            // Keep a previously discovered update usable when a later check fails.
            state = .failed
            if error is URLError {
                lastCheckError = "Couldn’t reach GitHub. Check your connection and try again."
            } else {
                lastCheckError = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn’t check for updates. Try again later."
            }
        }
    }

    func openReleasePage() {
        guard let release = availableRelease else { return }
        open(release.releaseURL)
    }

    func openDownload() {
        guard let release = availableRelease else { return }
        open(release.downloadURL ?? release.releaseURL)
    }

    private func open(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            lastCheckError = "Couldn’t open your browser. Try opening the release from GitHub."
            state = .failed
        }
    }

    private func apply(release: AppRelease?, installed: ReleaseVersion) {
        availableRelease = release.flatMap { $0.version > installed ? $0 : nil }
        if availableRelease != nil {
            state = .updateAvailable
        } else {
            state = release == nil ? .noRelease : .upToDate
        }
    }
}
