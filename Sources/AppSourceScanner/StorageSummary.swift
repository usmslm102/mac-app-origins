import Foundation

struct StorageSizeTotal: Equatable, Sendable {
    private(set) var itemCount = 0
    private(set) var unknownSizeCount = 0
    private(set) var sizeInBytes: Int64 = 0

    var knownSizeCount: Int {
        itemCount - unknownSizeCount
    }

    var sizeLabel: String {
        guard itemCount == 0 || knownSizeCount > 0 else {
            return "Unknown"
        }

        return ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }

    fileprivate mutating func include(sizeInBytes: Int64?) {
        itemCount += 1
        if let sizeInBytes {
            self.sizeInBytes += sizeInBytes
        } else {
            unknownSizeCount += 1
        }
    }
}

struct StorageSourceSize: Identifiable, Equatable, Sendable {
    let source: AppSource
    let total: StorageSizeTotal

    var id: AppSource { source }
}

struct StorageSummary: Equatable, Sendable {
    let total: StorageSizeTotal
    let bySource: [StorageSourceSize]
    let applications: StorageSizeTotal
    let cliTools: StorageSizeTotal
    let internalStorage: StorageSizeTotal
    let externalStorage: StorageSizeTotal

    init(apps: [ScannedApp]) {
        var total = StorageSizeTotal()
        var sourceTotals: [AppSource: StorageSizeTotal] = [:]
        var applications = StorageSizeTotal()
        var cliTools = StorageSizeTotal()
        var internalStorage = StorageSizeTotal()
        var externalStorage = StorageSizeTotal()

        for app in apps {
            total.include(sizeInBytes: app.sizeInBytes)
            sourceTotals[app.source, default: StorageSizeTotal()].include(sizeInBytes: app.sizeInBytes)

            switch app.kind {
            case .application:
                applications.include(sizeInBytes: app.sizeInBytes)
            case .cliTool:
                cliTools.include(sizeInBytes: app.sizeInBytes)
            }

            if app.isExternal {
                externalStorage.include(sizeInBytes: app.sizeInBytes)
            } else {
                internalStorage.include(sizeInBytes: app.sizeInBytes)
            }
        }

        self.total = total
        self.bySource = AppSource.allCases.map { source in
            StorageSourceSize(source: source, total: sourceTotals[source] ?? StorageSizeTotal())
        }
        self.applications = applications
        self.cliTools = cliTools
        self.internalStorage = internalStorage
        self.externalStorage = externalStorage
    }
}
