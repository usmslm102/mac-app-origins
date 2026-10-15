import Foundation

struct ScanScope: Codable, Equatable, Sendable {
    let includeSystemApplications: Bool
    let includeUserApplications: Bool
    let includeExternalVolumes: Bool
}

/// The durable inventory records metadata, excluding volatile measurements such as size.
struct ScanSnapshot: Codable, Equatable, Sendable {
    let date: Date
    let scope: ScanScope
    let items: [ScanSnapshotItem]

    init(apps: [ScannedApp], scope: ScanScope, date: Date = Date()) {
        self.date = date
        self.scope = scope
        items = Self.canonicalItems(apps.map(ScanSnapshotItem.init))
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        scope = try container.decode(ScanScope.self, forKey: .scope)
        items = Self.canonicalItems(try container.decode([ScanSnapshotItem].self, forKey: .items))
    }

    private static func canonicalItems(_ items: [ScanSnapshotItem]) -> [ScanSnapshotItem] {
        var byPath: [String: ScanSnapshotItem] = [:]
        byPath.reserveCapacity(items.count)

        for item in items {
            if let existing = byPath[item.path] {
                // Overlapping scan roots can report a path more than once. Choose consistently
                // even when the order of concurrent scanner results changes.
                if item.canonicalSortKey.lexicographicallyPrecedes(existing.canonicalSortKey) {
                    byPath[item.path] = item
                }
            } else {
                byPath[item.path] = item
            }
        }

        return byPath.values.sorted(by: ScanSnapshotItem.displayPrecedes)
    }

    private enum CodingKeys: String, CodingKey {
        case date, scope, items
    }
}

struct ScanSnapshotItem: Codable, Equatable, Identifiable, Sendable {
    let name: String
    let kind: InstallKind
    let bundleIdentifier: String
    let version: String
    let securityStatus: SecurityStatus
    let path: String
    let source: AppSource

    var id: String { path }

    init(app: ScannedApp) {
        name = app.name
        kind = app.kind
        bundleIdentifier = app.bundleIdentifier
        version = app.version
        securityStatus = app.securityStatus
        path = app.path
        source = app.source
    }

    fileprivate var canonicalSortKey: [String] {
        [name, kind.rawValue, bundleIdentifier, version, securityStatus.rawValue, source.rawValue]
    }

    fileprivate static func displayPrecedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let leftName = lhs.name.lowercased()
        let rightName = rhs.name.lowercased()
        if leftName != rightName {
            return leftName < rightName
        }
        if lhs.path != rhs.path {
            return lhs.path < rhs.path
        }
        return lhs.name < rhs.name
    }
}

struct ScanChange: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case added, removed, changed
    }

    enum Field: String, CaseIterable, Codable, Sendable {
        case name, kind, bundleIdentifier, version, securityStatus, source

        var label: String {
            switch self {
            case .name: "Name"
            case .kind: "Type"
            case .bundleIdentifier: "Identifier"
            case .version: "Version"
            case .securityStatus: "Security"
            case .source: "Source"
            }
        }

        fileprivate func value(in item: ScanSnapshotItem) -> String {
            switch self {
            case .name: item.name
            case .kind: item.kind.rawValue
            case .bundleIdentifier: item.bundleIdentifier
            case .version: item.version
            case .securityStatus: item.securityStatus.rawValue
            case .source: item.source.rawValue
            }
        }
    }

    let kind: Kind
    let previous: ScanSnapshotItem?
    let current: ScanSnapshotItem?

    var id: String { app.path }

    // Construction and decoding guarantee that at least one item exists.
    var app: ScanSnapshotItem { current ?? previous! }

    var changedFields: [Field] {
        guard let previous, let current else { return [] }
        return Field.allCases.filter { $0.value(in: previous) != $0.value(in: current) }
    }

    var detail: String {
        switch kind {
        case .added:
            return "Added since the previous scan"
        case .removed:
            return "No longer present in this scan"
        case .changed:
            guard let previous, let current else { return "Metadata changed" }
            return changedFields.map {
                "\($0.label): \($0.value(in: previous)) → \($0.value(in: current))"
            }.joined(separator: " · ")
        }
    }

    var summary: String { detail }

    fileprivate init(kind: Kind, previous: ScanSnapshotItem?, current: ScanSnapshotItem?) {
        self.kind = kind
        self.previous = previous
        self.current = current
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        previous = try container.decodeIfPresent(ScanSnapshotItem.self, forKey: .previous)
        current = try container.decodeIfPresent(ScanSnapshotItem.self, forKey: .current)

        let isValid: Bool
        switch kind {
        case .added:
            isValid = previous == nil && current != nil
        case .removed:
            isValid = previous != nil && current == nil
        case .changed:
            isValid = previous != nil && current != nil && previous?.path == current?.path && previous != current
        }
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Scan change items do not match the change kind."
            ))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, previous, current
    }
}

struct ScanComparison: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case initialBaseline, scopeChanged, compared
    }

    let previousDate: Date?
    let currentDate: Date
    let scope: ScanScope
    let changes: [ScanChange]
    let state: State

    /// Whether this scan could be compared with an earlier scan of the same locations.
    var hasBaseline: Bool { state == .compared }

    init(previous: ScanSnapshot?, current: ScanSnapshot) {
        previousDate = previous?.date
        currentDate = current.date
        scope = current.scope

        guard let previous else {
            state = .initialBaseline
            changes = []
            return
        }
        guard previous.scope == current.scope else {
            state = .scopeChanged
            changes = []
            return
        }

        state = .compared
        let previousByPath = previous.items.reduce(into: [String: ScanSnapshotItem]()) { $0[$1.path] = $1 }
        let currentByPath = current.items.reduce(into: [String: ScanSnapshotItem]()) { $0[$1.path] = $1 }
        let paths = Set(previousByPath.keys).union(currentByPath.keys)

        changes = paths.compactMap { path -> ScanChange? in
            let before = previousByPath[path]
            let after = currentByPath[path]
            switch (before, after) {
            case (nil, .some):
                return ScanChange(kind: .added, previous: nil, current: after)
            case (.some, nil):
                return ScanChange(kind: .removed, previous: before, current: nil)
            case let (.some(before), .some(after)) where before != after:
                return ScanChange(kind: .changed, previous: before, current: after)
            default:
                return nil
            }
        }.sorted { ScanSnapshotItem.displayPrecedes($0.app, $1.app) }
    }
}
