import Darwin
import Foundation
import SwiftUI

enum CleanupCategory: String, CaseIterable, Codable, Sendable {
    case application
    case service
    case sharedComponent
    case settings
    case cache
    case log
    case userData

    var title: String {
        switch self {
        case .application: L10n.text("Alkalmazások", "Applications")
        case .service: L10n.text("Háttérszolgáltatások", "Background services")
        case .sharedComponent: L10n.text("Közös Adobe-összetevők", "Shared Adobe components")
        case .settings: L10n.text("Beállítások", "Settings")
        case .cache: L10n.text("Gyorsítótárak", "Caches")
        case .log: L10n.text("Naplók", "Logs")
        case .userData: L10n.text("Személyes tartalom", "Personal content")
        }
    }

    var symbol: String {
        switch self {
        case .application: "square.grid.2x2.fill"
        case .service: "gearshape.2.fill"
        case .sharedComponent: "shippingbox.fill"
        case .settings: "slider.horizontal.3"
        case .cache: "bolt.horizontal.circle.fill"
        case .log: "doc.text.fill"
        case .userData: "person.crop.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .application: .purple
        case .service: .orange
        case .sharedComponent: .blue
        case .settings: .indigo
        case .cache: .green
        case .log: .gray
        case .userData: .pink
        }
    }

    var defaultSelected: Bool {
        self == .cache || self == .log
    }
}

enum RiskLevel: Int, Codable, Comparable, Sendable {
    case low
    case medium
    case high

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .low: L10n.text("Újragenerálható", "Regenerable")
        case .medium: L10n.text("Ellenőrizendő", "Review")
        case .high: L10n.text("Személyes adat lehet", "May contain personal data")
        }
    }

    var color: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }
}

enum ComponentScope: String, Codable, Sendable {
    case adobeProduct
    case creativeCloudInfrastructure
    case protectedUserContent
}

struct FileIdentity: Codable, Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct CleanupItem: Identifiable, Hashable, Codable, Sendable {
    let path: String
    let category: CleanupCategory
    let risk: RiskLevel
    let size: Int64
    let reason: String
    let bundleIdentifier: String?
    let scope: ComponentScope
    let sourceIdentity: FileIdentity?

    init(
        path: String,
        category: CleanupCategory,
        risk: RiskLevel,
        size: Int64,
        reason: String,
        bundleIdentifier: String?,
        scope: ComponentScope,
        sourceIdentity: FileIdentity? = nil
    ) {
        self.path = path
        self.category = category
        self.risk = risk
        self.size = size
        self.reason = reason
        self.bundleIdentifier = bundleIdentifier
        self.scope = scope
        self.sourceIdentity = sourceIdentity
    }

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { url.lastPathComponent }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct CleanupSession: Codable, Sendable {
    let createdAt: Date
    let quarantinePath: String
    let items: [CleanupItem]
    let logPath: String?
    let hostsCleanup: HostsCleanupRecord?

    init(
        createdAt: Date,
        quarantinePath: String,
        items: [CleanupItem],
        logPath: String?,
        hostsCleanup: HostsCleanupRecord? = nil
    ) {
        self.createdAt = createdAt
        self.quarantinePath = quarantinePath
        self.items = items
        self.logPath = logPath
        self.hostsCleanup = hostsCleanup
    }
}

struct QuarantineRecord: Identifiable, Sendable {
    let session: CleanupSession
    let availableItemCount: Int
    let hostsBackupAvailable: Bool

    var id: String { session.quarantinePath }
    var restorableItemCount: Int { availableItemCount + (hostsBackupAvailable ? 1 : 0) }
    var hasRestorableContent: Bool { restorableItemCount > 0 }
}

struct CleanupProgressState: Codable, Sendable {
    let completed: Int
    let total: Int
    let currentPath: String
    let stage: String
}

struct CleanupRunContext: Sendable {
    let directory: URL
    let statusURL: URL
    let cancelURL: URL
    let logURL: URL

    static func create(
        items: [CleanupItem],
        hostsCleanup: HostsCleanupPlan? = nil,
        fileManager: FileManager = .default,
        temporaryDirectory: URL? = nil,
        logDirectory: URL? = nil
    ) throws -> CleanupRunContext {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let identifier = String(UUID().uuidString.prefix(6))
        // `FileManager.temporaryDirectory` is normally returned below `/var`.
        // On macOS `/var` is the system-owned alias of `/private/var`, while
        // privileged path validation intentionally rejects symlinked parents.
        // Resolve that trusted system alias before creating the run directory.
        let temporaryRoot = try canonicalTemporaryDirectory(
            temporaryDirectory ?? fileManager.temporaryDirectory
        )
        let directory = temporaryRoot
            .appendingPathComponent("AbeSweep-\(identifier)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let resolvedLogDirectory = logDirectory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AbeSweep", isDirectory: true)
        try fileManager.createDirectory(at: resolvedLogDirectory, withIntermediateDirectories: true)
        let logURL = resolvedLogDirectory.appendingPathComponent("AbeSweep-\(stamp)-\(identifier).log")
        let header = """
        \(L10n.text("AbeSweep eltávolítási napló", "AbeSweep removal log"))
        \(L10n.text("Kezdés", "Started")): \(Date().formatted(date: .long, time: .standard))
        \(L10n.text("Kijelölt elemek", "Selected items")): \(items.count + (hostsCleanup == nil ? 0 : 1))
        \(L10n.text("A felhasználó a művelet előtt elfogadta a felelősségi tájékoztatót.", "The user accepted the disclaimer before starting the operation."))
        \(String(repeating: "-", count: 72))
        \(items.map { "\(L10n.text("TERV", "PLANNED")) | \($0.path) | \($0.formattedSize)" }.joined(separator: "\n"))
        \(hostsCleanup.map { "\(L10n.text("TERV", "PLANNED")) | /etc/hosts | \($0.matchedHostnames.count) Adobe hostname(s)" } ?? "")
        \(String(repeating: "-", count: 72))

        """
        try Data(header.utf8).write(to: logURL, options: .atomic)

        return CleanupRunContext(
            directory: directory,
            statusURL: directory.appendingPathComponent("status.json"),
            cancelURL: directory.appendingPathComponent("cancel"),
            logURL: logURL
        )
    }

    private static func canonicalTemporaryDirectory(_ url: URL) throws -> URL {
        var resolvedPath = [CChar](repeating: 0, count: Int(PATH_MAX))
        let wasResolved = resolvedPath.withUnsafeMutableBufferPointer { buffer in
            url.path.withCString { path in
                realpath(path, buffer.baseAddress) != nil
            }
        }
        guard wasResolved else {
            throw CocoaError(.fileNoSuchFile)
        }
        let end = resolvedPath.firstIndex(of: 0) ?? resolvedPath.endIndex
        let path = String(decoding: resolvedPath[..<end].map(UInt8.init(bitPattern:)), as: UTF8.self)
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

enum SelectionPreset: String, CaseIterable, Identifiable {
    case safe
    case creativeCloud
    case full
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safe: L10n.text("Csak ideiglenes fájlok", "Temporary files only")
        case .creativeCloud: L10n.text("Csak Creative Cloud", "Creative Cloud only")
        case .full: L10n.text("Teljes Adobe-eltávolítás", "Full Adobe removal")
        case .custom: L10n.text("Egyéni kijelölés", "Custom selection")
        }
    }
}
