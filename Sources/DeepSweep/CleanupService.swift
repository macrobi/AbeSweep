import AppKit
import CryptoKit
import Darwin
import Foundation

enum CleanupError: LocalizedError {
    case noItems
    case processesStillRunning(String)
    case authorizationCancelled
    case commandFailed(String)
    case manifestFailed
    case operationCancelled
    case invalidQuarantinePath
    case appDataAccessDenied(String)
    case invalidItemPath(String)
    case invalidManifestItem(String)
    case sourceChanged(String)
    case crossVolumeMove(String)

    var errorDescription: String? {
        switch self {
        case .processesStillRunning(let names): L10n.text(
            "Mentsd el a munkádat, majd zárd be az alábbi alkalmazásokat, és próbáld újra. Az AbeSweep nem kényszeríti a bezárásukat.\n\n\(names)",
            "Save your work, close the following applications, then try again. AbeSweep will not force them to quit.\n\n\(names)"
        )
        case .noItems: L10n.text("Nincs kijelölt elem.", "No items are selected.")
        case .authorizationCancelled: L10n.text("A rendszergazdai engedélyezés megszakadt.", "Administrator authorization was cancelled.")
        case .commandFailed(let message): L10n.text("A takarítás nem fejeződött be: \(message)", "Cleanup could not be completed: \(message)")
        case .manifestFailed: L10n.text("A visszaállításhoz szükséges jegyzék nem hozható létre.", "The manifest required for restore could not be created.")
        case .operationCancelled: L10n.text("A művelet megszakadt, a módosítások visszaálltak.", "The operation was cancelled and all changes were rolled back.")
        case .invalidQuarantinePath: L10n.text(
            "A karantén biztonságos útvonala nem hozható létre, vagy időközben megváltozott, ezért a művelet leállt.",
            "The secure quarantine path could not be created or changed unexpectedly, so the operation was stopped."
        )
        case .appDataAccessDenied(let path): L10n.text(
            "A macOS nem engedélyezte az Adobe alkalmazásadatainak elérését. Add hozzá az AbeSweepet a Teljes lemezhozzáférés listájához, majd az alkalmazás újraindítása után próbáld újra. A beállítás közvetlenül megnyitható ebből az ablakból vagy a Súgó menüből.\n\nÉrintett elem: \(path)",
            "macOS did not allow access to Adobe application data. Add AbeSweep to Full Disk Access, restart the application, then try again. You can open the setting directly from this alert or the Help menu.\n\nAffected item: \(path)"
        )
        case .invalidItemPath(let path): L10n.text(
            "Az elem útvonala nem biztonságos vagy nem ellenőrzött Adobe-útvonal: \(path)",
            "The item path is unsafe or is not a validated Adobe path: \(path)"
        )
        case .invalidManifestItem(let path): L10n.text(
            "A karanténjegyzék érvénytelen vagy módosított elemet tartalmaz: \(path)",
            "The quarantine manifest contains an invalid or modified item: \(path)"
        )
        case .sourceChanged(let path): L10n.text(
            "Az elem a vizsgálat óta megváltozott vagy lecserélődött: \(path)",
            "The item changed or was replaced after the scan: \(path)"
        )
        case .crossVolumeMove(let path): L10n.text(
            "Az elem és az AbeSweep karanténja külön köteten van, ezért a biztonságos visszagörgetés nem garantálható. Egy kijelölt elem sem lett áthelyezve: \(path)",
            "The item and the AbeSweep quarantine are on different volumes, so safe rollback cannot be guaranteed. No selected item was moved: \(path)"
        )
        }
    }
}

struct CleanupService: @unchecked Sendable {
    typealias TeamIdentifierProvider = @Sendable (String) -> String?

    private let fileManager: FileManager
    private let pathPolicy: AdobePathPolicy
    private let logDirectory: URL
    private let quarantineBaseOverrides: [URL]?
    private let teamIdentifierProvider: TeamIdentifierProvider

    init(
        fileManager: FileManager = .default,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL = URL(fileURLWithPath: "/Library"),
        applicationRoots: [URL]? = nil,
        quarantineBaseURLs: [URL]? = nil,
        teamIdentifierProvider: @escaping TeamIdentifierProvider = CodeSigningIdentity.validTeamIdentifier
    ) {
        self.fileManager = fileManager
        self.logDirectory = home.appendingPathComponent("Library/Logs/AbeSweep", isDirectory: true)
        self.pathPolicy = AdobePathPolicy(
            fileManager: fileManager,
            home: home,
            systemLibrary: systemLibrary,
            applicationRoots: applicationRoots
        )
        self.quarantineBaseOverrides = quarantineBaseURLs
        self.teamIdentifierProvider = teamIdentifierProvider
    }

    var quarantineBaseURL: URL {
        if let override = quarantineBaseOverrides?.first { return override }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AbeSweep/Quarantine", isDirectory: true)
    }

    private var allowedQuarantineBaseURLs: [URL] {
        quarantineBaseOverrides ?? [
            quarantineBaseURL,
            URL(fileURLWithPath: "/Users/Shared/AbeSweep Quarantine", isDirectory: true)
        ]
    }

    func discoverQuarantineSessions(in baseURLs: [URL]? = nil) -> [CleanupSession] {
        discoverQuarantineRecords(in: baseURLs).map(\.session)
    }

    func discoverQuarantineRecords(in baseURLs: [URL]? = nil) -> [QuarantineRecord] {
        let trustedBases = baseURLs ?? [
            quarantineBaseURL,
            URL(fileURLWithPath: "/Users/Shared/AbeSweep Quarantine", isDirectory: true)
        ]
        var records: [QuarantineRecord] = []

        for base in trustedBases {
            guard let children = try? fileManager.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                let root = child
                guard root.deletingLastPathComponent().path == base.path,
                      let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      rootValues.isDirectory == true,
                      rootValues.isSymbolicLink != true
                else { continue }

                let manifest = root.appendingPathComponent("manifest.json")
                guard let manifestValues = try? manifest.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      manifestValues.isRegularFile == true,
                      manifestValues.isSymbolicLink != true,
                      let data = try? Data(contentsOf: manifest),
                      data.count <= 10_000_000,
                      let session = decodeSessionManifest(data),
                      session.quarantinePath == root.path,
                      let validatedSession = try? validateRestoreSession(
                          session,
                          quarantineBaseURLs: trustedBases,
                          requirePayload: false
                      )
                else { continue }

                records.append(quarantineRecord(for: validatedSession))
            }
        }

        return records.sorted { $0.session.createdAt > $1.session.createdAt }
    }

    func validatedLogURL(_ path: String?) -> URL? {
        guard let path, pathPolicy.isAbsoluteNormalizedPath(path) else { return nil }
        let url = URL(fileURLWithPath: path)
        guard url.deletingLastPathComponent().path == logDirectory.path,
              url.lastPathComponent.hasPrefix("AbeSweep-"), url.pathExtension == "log",
              pathPolicy.hasSafeParentPath(url), isRegularFileWithoutFollowingSymlinks(url)
        else { return nil }
        return url
    }

    func quarantineRecord(for session: CleanupSession) -> QuarantineRecord {
        let root = URL(fileURLWithPath: session.quarantinePath, isDirectory: true)
        let availableItemCount = session.items.reduce(into: 0) { count, item in
            let url = quarantineURL(for: item, destination: root)
            if entryExists(at: url) { count += 1 }
        }
        let hostsBackup = root.appendingPathComponent("hosts/original")
        return QuarantineRecord(
            session: session,
            availableItemCount: availableItemCount,
            hostsBackupAvailable: session.hostsCleanup != nil && entryExists(at: hostsBackup)
        )
    }

    private func decodeSessionManifest(_ data: Data) -> CleanupSession? {
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        if let session = try? isoDecoder.decode(CleanupSession.self, from: data) {
            return session
        }
        return try? JSONDecoder().decode(CleanupSession.self, from: data)
    }

    func validateRestoreSession(
        _ session: CleanupSession,
        quarantineBaseURLs: [URL]? = nil,
        requirePayload: Bool = true
    ) throws -> CleanupSession {
        let bases = quarantineBaseURLs ?? allowedQuarantineBaseURLs
        let root = try validatedQuarantineRoot(session.quarantinePath, allowedBases: bases)
        let payloadRoot = root.appendingPathComponent("payload", isDirectory: true)
        guard pathPolicy.isSafeContainer(payloadRoot) else {
            throw CleanupError.invalidQuarantinePath
        }
        if let hostsCleanup = session.hostsCleanup,
           !isValidSHA256(hostsCleanup.originalSHA256) || !isValidSHA256(hostsCleanup.cleanedSHA256) {
            throw CleanupError.invalidManifestItem("/etc/hosts")
        }

        var validatedItems: [CleanupItem] = []
        for item in session.items {
            guard pathPolicy.isAbsoluteNormalizedPath(item.path) else {
                throw CleanupError.invalidManifestItem(item.path)
            }
            let source = quarantineURL(for: item, destination: root)
            let sourceExists = entryExists(at: source)
            if requirePayload && !sourceExists { continue }
            guard source.path.hasPrefix(payloadRoot.path + "/") else {
                throw CleanupError.invalidManifestItem(item.path)
            }
            if sourceExists,
               !pathPolicy.isSafeContainer(source.deletingLastPathComponent()) {
                throw CleanupError.invalidManifestItem(item.path)
            }
            if sourceExists {
                guard let sourceIdentity = pathPolicy.identity(at: source.path),
                      let destinationIdentity = pathPolicy.nearestExistingParentIdentity(
                          for: item.path
                      )
                else { throw CleanupError.invalidManifestItem(item.path) }
                try validateSameVolumeMove(
                    sourceIdentity: sourceIdentity,
                    destinationIdentity: destinationIdentity,
                    path: item.path
                )
            }
            validatedItems.append(try pathPolicy.validatedManifestItem(
                item,
                sourceURL: sourceExists ? source : nil
            ))
        }

        return CleanupSession(
            createdAt: session.createdAt,
            quarantinePath: root.path,
            items: validatedItems,
            logPath: validatedLogURL(session.logPath)?.path,
            hostsCleanup: requirePayload && !entryExists(at: root.appendingPathComponent("hosts/original"))
                ? nil : session.hostsCleanup
        )
    }

    private func validatedQuarantineRoot(_ path: String, allowedBases: [URL]) throws -> URL {
        guard pathPolicy.isAbsoluteNormalizedPath(path)
        else { throw CleanupError.invalidQuarantinePath }

        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard allowedBases.contains(where: {
            root.deletingLastPathComponent().path == $0.path && root.path != $0.path
        }), pathPolicy.isSafeContainer(root)
        else { throw CleanupError.invalidQuarantinePath }
        return root
    }

    func quarantine(
        _ items: [CleanupItem],
        hostsCleanup: HostsCleanupPlan? = nil,
        context: CleanupRunContext
    ) async throws -> CleanupSession {
        guard !items.isEmpty || hostsCleanup != nil else { throw CleanupError.noItems }
        let validatedItems = try validateItemsForQuarantine(items)
        try prepareQuarantineBase(for: validatedItems)
        if fileManager.fileExists(atPath: context.cancelURL.path) || Task.isCancelled {
            throw CleanupError.operationCancelled
        }

        if !validatedItems.isEmpty {
            let report = await AdobeProcessController().stopRelevantProcesses(
                includesOfficePDFMaker: validatedItems.contains {
                    AdobeScanner.isAdobeOfficeAddInFilename(URL(fileURLWithPath: $0.path).lastPathComponent)
                }
            )
            for process in report.requested {
                appendLog(
                    L10n.text("LEÁLLÍTÁS KÉRVE", "TERMINATION REQUESTED")
                        + " | \(process.name) | PID \(process.processIdentifier)",
                    context: context
                )
            }
            for process in report.remaining {
                appendLog(
                    L10n.text("FIGYELMEZTETÉS | A folyamat továbbra is fut", "WARNING | Process is still running")
                        + " | \(process.name) | PID \(process.processIdentifier)",
                    context: context
                )
            }
            // Root-owned launch services may need the later administrator
            // bootout. A document application's refusal to quit always stops us.
            let remainingApplications = report.remaining.filter(\.isUserApplication)
            guard remainingApplications.isEmpty else {
                throw CleanupError.processesStillRunning(
                    Array(Set(remainingApplications.map(\.name))).sorted().joined(separator: ", ")
                )
            }
        }
        if fileManager.fileExists(atPath: context.cancelURL.path) || Task.isCancelled {
            throw CleanupError.operationCancelled
        }

        let preparedHostsURL = context.directory.appendingPathComponent("hosts-cleaned")
        if let hostsCleanup {
            try Data(hostsCleanup.cleanedContent.utf8).write(to: preparedHostsURL, options: .atomic)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let destination = quarantineBaseURL
            .appendingPathComponent(formatter.string(from: Date()) + "-" + UUID().uuidString.prefix(6))
        guard pathPolicy.isSafeContainer(quarantineBaseURL),
              destination.deletingLastPathComponent().path == quarantineBaseURL.path
        else { throw CleanupError.invalidQuarantinePath }
        let session = CleanupSession(
            createdAt: Date(),
            quarantinePath: destination.path,
            items: validatedItems,
            logPath: context.logURL.path,
            hostsCleanup: hostsCleanup?.record
        )

        let temporaryManifest = fileManager.temporaryDirectory
            .appendingPathComponent("AbeSweep-\(UUID().uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { throw CleanupError.manifestFailed }
        try data.write(to: temporaryManifest, options: .atomic)
        defer { try? fileManager.removeItem(at: temporaryManifest) }

        let appDataItems = validatedItems.filter { requiresAppDataAuthorization(path: $0.path) }
        let administratorItems = validatedItems.filter { !requiresAppDataAuthorization(path: $0.path) }
        var directlyMoved: [CleanupItem] = []

        do {
            // Always let the signed user process create the base and session.
            // Otherwise an administrator-only run could leave the shared parent
            // owned by root and break a later application-container cleanup.
            try fileManager.createDirectory(
                at: destination.appendingPathComponent("payload", isDirectory: true),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(
                at: temporaryManifest,
                to: destination.appendingPathComponent("manifest.json")
            )
            if hostsCleanup != nil {
                try fileManager.createDirectory(
                    at: destination.appendingPathComponent("hosts", isDirectory: true),
                    withIntermediateDirectories: false
                )
            }

            for item in appDataItems {
                if fileManager.fileExists(atPath: context.cancelURL.path) {
                    throw CleanupError.operationCancelled
                }
                try writeProgress(
                    completed: directlyMoved.count,
                    total: validatedItems.count,
                    currentPath: item.path,
                    stage: "working",
                    context: context
                )
                appendLog(L10n.text("FELDOLGOZÁS", "PROCESSING") + " | " + item.path, context: context)

                guard entryExists(at: item.url) else {
                    appendLog(
                        L10n.text("KIHAGYVA, MÁR NEM TALÁLHATÓ", "SKIPPED, NO LONGER FOUND") + " | " + item.path,
                        context: context
                    )
                    directlyMoved.append(item)
                    continue
                }

                let target = quarantineURL(for: item, destination: destination)
                guard pathPolicy.isSafeContainer(target.deletingLastPathComponent()) else {
                    throw CleanupError.invalidQuarantinePath
                }
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try pathPolicy.validateUnchanged(item)
                guard pathPolicy.isSafeContainer(target.deletingLastPathComponent()) else {
                    throw CleanupError.invalidQuarantinePath
                }
                do {
                    try fileManager.moveItem(at: item.url, to: target)
                } catch {
                    try pathPolicy.validateUnchanged(item)
                    guard pathPolicy.isSafeContainer(target.deletingLastPathComponent()) else {
                        throw CleanupError.sourceChanged(item.path)
                    }
                    throw CleanupError.appDataAccessDenied(item.path)
                }
                directlyMoved.append(item)
                appendLog(L10n.text("KARANTÉNBA HELYEZVE", "QUARANTINED") + " | " + item.path, context: context)
                try writeProgress(
                    completed: directlyMoved.count,
                    total: validatedItems.count,
                    currentPath: item.path,
                    stage: "working",
                    context: context
                )
            }

            if !administratorItems.isEmpty || hostsCleanup != nil {
                let command = try buildQuarantineCommand(
                    items: administratorItems,
                    hostsCleanup: hostsCleanup,
                    preparedHostsFile: hostsCleanup == nil ? nil : preparedHostsURL,
                    destination: destination,
                    manifest: temporaryManifest,
                    uid: getuid(),
                    gid: getgid(),
                    context: context,
                    progressOffset: appDataItems.count,
                    progressTotal: validatedItems.count + (hostsCleanup == nil ? 0 : 1)
                )
                try await runAsAdministrator(command)
            } else {
                if fileManager.fileExists(atPath: context.cancelURL.path) || Task.isCancelled {
                    throw CleanupError.operationCancelled
                }
                appendLog(L10n.text("SIKERES | A takarítás befejeződött", "SUCCESS | Cleanup completed"), context: context)
                try writeProgress(
                    completed: validatedItems.count,
                    total: validatedItems.count,
                    currentPath: L10n.text("Kész", "Done"),
                    stage: "finished",
                    context: context
                )
            }
            return session
        } catch {
            let rollbackError = rollbackDirectlyMoved(
                directlyMoved,
                destination: destination,
                context: context
            )
            if rollbackError == nil {
                removeFailedSessionIfEmpty(session)
            }
            if let rollbackError {
                throw CleanupError.commandFailed(
                    L10n.text(
                        "Az alkalmazásadatok visszaállítása sem sikerült: \(rollbackError.localizedDescription)",
                        "Application data could not be restored either: \(rollbackError.localizedDescription)"
                    )
                )
            }
            throw error
        }
    }

    func restore(_ session: CleanupSession) async throws {
        let session = try validateRestoreSession(session)
        let appDataItems = session.items.filter { requiresAppDataAuthorization(path: $0.path) }
        let administratorItems = session.items.filter { !requiresAppDataAuthorization(path: $0.path) }

        for item in session.items {
            let source = quarantineURL(for: item, destination: URL(fileURLWithPath: session.quarantinePath))
            guard entryExists(at: source) else { continue }
            if entryExists(at: item.url) {
                throw CleanupError.commandFailed(
                    L10n.text("A cél már létezik: ", "Destination already exists: ") + item.path
                )
            }
        }

        var directlyRestored: [CleanupItem] = []
        do {
            for item in appDataItems {
                let source = quarantineURL(for: item, destination: URL(fileURLWithPath: session.quarantinePath))
                guard entryExists(at: source) else { continue }
                try pathPolicy.validateRestoreMove(
                    source: source,
                    destinationPath: item.path,
                    expectedIdentity: item.sourceIdentity
                )
                try fileManager.createDirectory(at: item.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try pathPolicy.validateRestoreMove(
                    source: source,
                    destinationPath: item.path,
                    expectedIdentity: item.sourceIdentity
                )
                do {
                    try fileManager.moveItem(at: source, to: item.url)
                } catch {
                    try pathPolicy.validateRestoreMove(
                        source: source,
                        destinationPath: item.path,
                        expectedIdentity: item.sourceIdentity
                    )
                    throw CleanupError.appDataAccessDenied(item.path)
                }
                directlyRestored.append(item)
            }

            if !administratorItems.isEmpty || session.hostsCleanup != nil {
                let administratorSession = CleanupSession(
                    createdAt: session.createdAt,
                    quarantinePath: session.quarantinePath,
                    items: administratorItems,
                    logPath: session.logPath,
                    hostsCleanup: session.hostsCleanup
                )
                let command = try buildRestoreCommand(session: administratorSession, uid: getuid())
                try await runAsAdministrator(command)
            }
        } catch {
            if let rollbackError = rollbackDirectlyRestored(
                directlyRestored,
                destination: URL(fileURLWithPath: session.quarantinePath)
            ) {
                throw CleanupError.commandFailed(
                    L10n.text(
                        "A visszaállítás visszagörgetése sem sikerült: \(rollbackError.localizedDescription)",
                        "Restore rollback could not be completed either: \(rollbackError.localizedDescription)"
                    )
                )
            }
            throw error
        }
    }

    func validateItemsForQuarantine(_ items: [CleanupItem]) throws -> [CleanupItem] {
        let validatedItems = try items.map(pathPolicy.validatedItemForQuarantine)
        for item in validatedItems where pathPolicy.isValidatedLaunchServicePath(item) {
            guard validatedLaunchService(for: item, plistURL: item.url, quarantineRoot: nil) != nil else {
                throw CleanupError.invalidItemPath(item.path)
            }
        }
        return validatedItems
    }

    private func prepareQuarantineBase(for items: [CleanupItem]) throws {
        guard pathPolicy.isSafeContainer(quarantineBaseURL) else {
            throw CleanupError.invalidQuarantinePath
        }
        try fileManager.createDirectory(at: quarantineBaseURL, withIntermediateDirectories: true)
        guard pathPolicy.isSafeContainer(quarantineBaseURL),
              let quarantineIdentity = pathPolicy.identity(at: quarantineBaseURL.path)
        else { throw CleanupError.invalidQuarantinePath }
        try validateSameVolumeMoves(items, quarantineIdentity: quarantineIdentity)
    }

    func validateSameVolumeMoves(
        _ items: [CleanupItem],
        quarantineIdentity: FileIdentity
    ) throws {
        for item in items {
            guard let sourceIdentity = item.sourceIdentity else {
                throw CleanupError.sourceChanged(item.path)
            }
            try validateSameVolumeMove(
                sourceIdentity: sourceIdentity,
                destinationIdentity: quarantineIdentity,
                path: item.path
            )
        }
    }

    func validateSameVolumeMove(
        sourceIdentity: FileIdentity,
        destinationIdentity: FileIdentity,
        path: String
    ) throws {
        guard sourceIdentity.device == destinationIdentity.device else {
            throw CleanupError.crossVolumeMove(path)
        }
    }

    func permanentlyDeleteQuarantine(_ session: CleanupSession) async throws {
        let command = try buildPermanentDeleteCommand(session: session)
        try await runAsAdministrator(command)
    }

    func buildQuarantineCommand(
        items: [CleanupItem],
        hostsCleanup: HostsCleanupPlan? = nil,
        preparedHostsFile: URL? = nil,
        destination: URL,
        manifest: URL,
        uid: uid_t,
        gid: gid_t,
        context: CleanupRunContext? = nil,
        progressOffset: Int = 0,
        progressTotal: Int? = nil
    ) throws -> String {
        let root = destination.path
        let base = destination.deletingLastPathComponent()
        let payload = destination.appendingPathComponent("payload", isDirectory: true)
        let storedManifest = destination.appendingPathComponent("manifest.json")
        guard destination.deletingLastPathComponent().path == base.path,
              pathPolicy.isSafeContainer(base),
              pathPolicy.isSafeContainer(destination),
              pathPolicy.isSafeContainer(payload),
              let baseIdentity = pathPolicy.identity(at: base.path),
              let rootIdentity = pathPolicy.identity(at: root),
              let payloadIdentity = pathPolicy.identity(at: payload.path),
              let manifestIdentity = pathPolicy.identity(at: storedManifest.path),
              isRegularFileWithoutFollowingSymlinks(storedManifest),
              isRegularFileWithoutFollowingSymlinks(manifest),
              let sourceManifestData = try? Data(contentsOf: manifest, options: .mappedIfSafe),
              let storedManifestData = try? Data(contentsOf: storedManifest, options: .mappedIfSafe),
              sha256(sourceManifestData) == sha256(storedManifestData)
        else { throw CleanupError.invalidQuarantinePath }

        let manifestHash = sha256(storedManifestData)
        var quarantineParentIdentities: [String: FileIdentity] = [:]
        for item in items {
            let target = quarantineURL(for: item, destination: destination)
            let parent = target.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            guard pathPolicy.isSafeContainer(parent),
                  let identity = pathPolicy.identity(at: parent.path)
            else { throw CleanupError.invalidQuarantinePath }
            quarantineParentIdentities[item.path] = identity
        }
        let validatedLaunchServices = items.compactMap {
            validatedLaunchService(for: $0, plistURL: $0.url, quarantineRoot: nil)
        }
        let reportedTotal = progressTotal ?? items.count
        var lines = ["set -e"]
        lines.append(contentsOf: shellPathValidationFunctions())
        lines.append("assert_session_layout() { assert_directory_identity \(shellQuote(base.path)) \(shellQuote(shellIdentity(baseIdentity))) && assert_directory_identity \(shellQuote(root)) \(shellQuote(shellIdentity(rootIdentity))) && assert_directory_identity \(shellQuote(payload.path)) \(shellQuote(shellIdentity(payloadIdentity))); }")
        lines.append("assert_session_layout || { echo \(shellQuote(L10n.text("A karantén útvonala megváltozott.", "The quarantine path changed."))) >&2; exit 45; }")
        lines.append("assert_regular_file_identity_hash \(shellQuote(storedManifest.path)) \(shellQuote(shellIdentity(manifestIdentity))) \(shellQuote(manifestHash)) || { echo \(shellQuote(L10n.text("A karanténjegyzék megváltozott.", "The quarantine manifest changed."))) >&2; exit 45; }")
        if hostsCleanup != nil {
            lines.append("hosts_modified=0")
            lines.append("hosts_backup_identity=''")
        }

        if let context {
            guard pathPolicy.isSafeContainer(context.directory),
                  pathPolicy.hasSafeParentPath(context.logURL),
                  let contextIdentity = pathPolicy.identity(at: context.directory.path),
                  let logIdentity = pathPolicy.identity(at: context.logURL.path),
                  isRegularFileWithoutFollowingSymlinks(context.logURL)
            else { throw CleanupError.invalidQuarantinePath }
            lines.append("assert_context_layout() { assert_directory_identity \(shellQuote(context.directory.path)) \(shellQuote(shellIdentity(contextIdentity))) && assert_regular_file_identity \(shellQuote(context.logURL.path)) \(shellQuote(shellIdentity(logIdentity))); }")
            lines.append("write_progress() { assert_context_layout || return 1; status_tmp=$(/usr/bin/mktemp \(shellQuote(context.directory.appendingPathComponent("status.XXXXXX").path))) || return 1; /usr/bin/printf '%s' \"$1\" > \"$status_tmp\" && assert_context_layout && /bin/mv -f \"$status_tmp\" \(shellQuote(context.statusURL.path)); status_result=$?; [ \"$status_result\" -eq 0 ] || /bin/rm -f \"$status_tmp\" 2>/dev/null || true; return \"$status_result\"; }")
            lines.append("append_log() { assert_context_layout || return 1; /usr/bin/printf '%s | %s\\n' \"$(/bin/date '+%Y-%m-%d %H:%M:%S')\" \"$1\" >> \(shellQuote(context.logURL.path)); }")
            lines.append("write_progress \(shellQuote(progressJSON(completed: progressOffset, total: reportedTotal, currentPath: L10n.text("Rendszergazdai jóváhagyás", "Administrator authorization"), stage: "preparing")))")
            lines.append("append_log \(shellQuote(L10n.text("ELŐKÉSZÍTÉS | Rendszergazdai művelet indítása", "PREPARING | Starting administrator operation")))")
        }
        for index in items.indices {
            lines.append("moved_\(index)=0")
        }

        lines.append(contentsOf: [
            "rollback() {",
            "status=$?",
            "set +e",
            "rollback_failed=0",
            "trap - EXIT",
            "if [ \"$status\" -ne 0 ]; then"
        ])

        if context != nil {
            lines.append("append_log \(shellQuote(L10n.text("VISSZAÁLLÍTÁS | A félbemaradt művelet visszagörgetése", "ROLLBACK | Reverting an incomplete operation"))) || true")
            lines.append("write_progress \(shellQuote(progressJSON(completed: progressOffset, total: reportedTotal, currentPath: L10n.text("A módosítások visszaállítása", "Rolling back changes"), stage: "rollback"))) || true")
        }

        if let hostsCleanup {
            let hostsBackup = root + "/hosts/original"
            let restoredLog = context == nil ? "" : "; append_log \(shellQuote(L10n.text("VISSZAÁLLÍTVA", "RESTORED") + " | /etc/hosts")) || true"
            let rollbackFailure = shellQuote(L10n.text(
                "A hosts fájl visszaállítása nem sikerült.",
                "The hosts file rollback failed."
            ))
            lines.append("if [ \"$hosts_modified\" -eq 1 ]; then hosts_rollback_tmp=''; if assert_session_layout && [ -n \"$hosts_backup_identity\" ] && assert_regular_file_identity_hash \(shellQuote(hostsBackup)) \"$hosts_backup_identity\" \(shellQuote(hostsCleanup.originalSHA256)) && hosts_rollback_tmp=$(/usr/bin/mktemp /private/etc/hosts.abesweep.rollback.XXXXXX) && /bin/cp -p \(shellQuote(hostsBackup)) \"$hosts_rollback_tmp\" && [ \"$(/usr/bin/shasum -a 256 \"$hosts_rollback_tmp\" | /usr/bin/awk '{print $1}')\" = \(shellQuote(hostsCleanup.originalSHA256)) ] && assert_hosts_hash \(shellQuote(hostsCleanup.cleanedSHA256)) && /bin/mv -f \"$hosts_rollback_tmp\" /etc/hosts; then /usr/bin/dscacheutil -flushcache 2>/dev/null || true; /usr/bin/killall -HUP mDNSResponder 2>/dev/null || true\(restoredLog); else rollback_failed=1; echo \(rollbackFailure) >&2; fi; fi")
            lines.append("if [ -n \"${hosts_tmp:-}\" ]; then /bin/rm -f \"$hosts_tmp\" 2>/dev/null || true; fi")
            lines.append("if [ -n \"${hosts_backup_tmp:-}\" ]; then /bin/rm -f \"$hosts_backup_tmp\" 2>/dev/null || true; fi")
            lines.append("if [ -n \"${hosts_rollback_tmp:-}\" ]; then /bin/rm -f \"$hosts_rollback_tmp\" 2>/dev/null || true; fi")
        }

        for index in items.indices.reversed() {
            let item = items[index]
            let relative = item.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let quarantined = root + "/payload/" + relative
            let parent = (item.path as NSString).deletingLastPathComponent
            let identity = shellIdentity(item.sourceIdentity)
            let quarantineParent = (quarantined as NSString).deletingLastPathComponent
            let quarantineParentIdentity = shellIdentity(quarantineParentIdentities[item.path])
            lines.append("if [ \"$moved_\(index)\" -eq 1 ]; then if assert_session_layout && assert_directory_identity \(shellQuote(quarantineParent)) \(shellQuote(quarantineParentIdentity)) && assert_no_symlink_parents \(shellQuote(item.path)) && assert_identity \(shellQuote(quarantined)) \(shellQuote(identity)); then mkdir -p \(shellQuote(parent)); if assert_session_layout && assert_directory_identity \(shellQuote(quarantineParent)) \(shellQuote(quarantineParentIdentity)) && assert_no_symlink_parents \(shellQuote(item.path)) && assert_identity \(shellQuote(quarantined)) \(shellQuote(identity)); then move_without_replacing \(shellQuote(quarantined)) \(shellQuote(item.path)) || rollback_failed=1; else rollback_failed=1; fi; else rollback_failed=1; fi; fi")
            if context != nil {
                lines.append("if [ \"$moved_\(index)\" -eq 1 ] && [ ! -e \(shellQuote(quarantined)) ] && [ ! -L \(shellQuote(quarantined)) ] && assert_identity \(shellQuote(item.path)) \(shellQuote(identity)); then append_log \(shellQuote(L10n.text("VISSZAÁLLÍTVA", "RESTORED") + " | " + item.path)) || true; fi")
            }
        }
        for service in validatedLaunchServices {
            let validation = shellLaunchServiceValidation(service, plistPath: service.item.path)
            if service.item.path.hasPrefix("/Library/LaunchDaemons/") {
                lines.append("if [ \"$rollback_failed\" -eq 0 ] && \(validation); then /bin/launchctl bootstrap system \(shellQuote(service.item.path)) 2>/dev/null || true; fi")
            } else {
                lines.append("if [ \"$rollback_failed\" -eq 0 ] && \(validation); then /bin/launchctl bootstrap gui/\(uid) \(shellQuote(service.item.path)) 2>/dev/null || true; fi")
            }
        }
        if let context {
            lines.append("if [ \"$rollback_failed\" -ne 0 ]; then write_progress \(shellQuote(progressJSON(completed: progressOffset, total: reportedTotal, currentPath: L10n.text("A visszagörgetés nem teljes; ellenőrizd a karantént", "Rollback incomplete; check quarantine"), stage: "failed"))) || true; append_log ABESWEEP_ROLLBACK_FAILED || true; elif [ \"$status\" -eq 130 ]; then write_progress \(shellQuote(progressJSON(completed: progressOffset, total: reportedTotal, currentPath: L10n.text("Megszakítva - minden visszaállt", "Cancelled - all changes rolled back"), stage: "cancelled"))) || true; append_log \(shellQuote(L10n.text("MEGSZAKÍTVA | Minden áthelyezett elem visszaállt", "CANCELLED | All moved items were restored"))) || true; else write_progress \(shellQuote(progressJSON(completed: progressOffset, total: reportedTotal, currentPath: L10n.text("Hiba - a módosítások visszaálltak", "Error - changes were rolled back"), stage: "failed"))) || true; append_log \(shellQuote(L10n.text("HIBA | A módosítások visszaálltak", "ERROR | Changes were rolled back"))) || true; fi")
            lines.append("chown \(uid):\(gid) \(shellQuote(context.logURL.path)) 2>/dev/null || true")
        }
        lines.append(contentsOf: ["fi", "if [ \"$rollback_failed\" -ne 0 ]; then echo ABESWEEP_ROLLBACK_FAILED >&2; exit 52; fi", "exit \"$status\"", "}", "trap rollback EXIT"])

        // Disable selected launch jobs before touching their files so Creative
        // Cloud cannot immediately relaunch CCXProcess or CoreSync. The
        // rollback handler above re-enables them if any later step fails.
        for service in validatedLaunchServices {
            let item = service.item
            let validation = shellPreMoveValidation(item: item, path: item.path)
            let launchValidation = shellLaunchServiceValidation(service, plistPath: item.path)
            if item.path.hasPrefix("/Library/LaunchDaemons/") {
                lines.append("if [ -e \(shellQuote(item.path)) ] || [ -L \(shellQuote(item.path)) ]; then \(validation); if \(launchValidation); then /bin/launchctl bootout system \(shellQuote(item.path)) 2>/dev/null || true; fi; fi")
            } else {
                lines.append("if [ -e \(shellQuote(item.path)) ] || [ -L \(shellQuote(item.path)) ]; then \(validation); if \(launchValidation); then /bin/launchctl bootout gui/\(uid) \(shellQuote(item.path)) 2>/dev/null || true; fi; fi")
            }
        }

        if let hostsCleanup {
            let hostsBackup = root + "/hosts/original"
            let hostsDirectory = destination.appendingPathComponent("hosts", isDirectory: true)
            guard let preparedHostsFile,
                  pathPolicy.isSafeContainer(hostsDirectory),
                  let hostsDirectoryIdentity = pathPolicy.identity(at: hostsDirectory.path),
                  isRegularFileWithoutFollowingSymlinks(preparedHostsFile),
                  let preparedIdentity = pathPolicy.identity(at: preparedHostsFile.path)
            else { throw CleanupError.invalidQuarantinePath }
            lines.append("if [ -L /etc/hosts ] || [ ! -f /etc/hosts ]; then echo \(shellQuote(L10n.text("A hosts fájl nem szabályos fájl; a módosítás leállt.", "The hosts file is not a regular file; modification was stopped."))) >&2; exit 46; fi")
            lines.append("hosts_hash=$(/usr/bin/shasum -a 256 /etc/hosts | /usr/bin/awk '{print $1}')")
            lines.append("if [ \"$hosts_hash\" != \(shellQuote(hostsCleanup.originalSHA256)) ]; then echo \(shellQuote(L10n.text("A hosts fájl a vizsgálat óta megváltozott. Indíts új vizsgálatot.", "The hosts file changed since the scan. Start a new scan."))) >&2; exit 47; fi")
            lines.append("assert_regular_file_identity_hash \(shellQuote(preparedHostsFile.path)) \(shellQuote(shellIdentity(preparedIdentity))) \(shellQuote(hostsCleanup.cleanedSHA256)) || { echo \(shellQuote(L10n.text("A hosts előkészített példányának ellenőrzése sikertelen.", "The prepared hosts file failed verification."))) >&2; exit 51; }")
            lines.append("assert_session_layout && assert_directory_identity \(shellQuote(hostsDirectory.path)) \(shellQuote(shellIdentity(hostsDirectoryIdentity))) || exit 45")
            lines.append("hosts_backup_tmp=$(/usr/bin/mktemp /private/etc/hosts.abesweep.backup.XXXXXX)")
            lines.append("/bin/cp -p /etc/hosts \"$hosts_backup_tmp\"")
            lines.append("[ \"$(/usr/bin/shasum -a 256 \"$hosts_backup_tmp\" | /usr/bin/awk '{print $1}')\" = \(shellQuote(hostsCleanup.originalSHA256)) ] || exit 47")
            lines.append("assert_session_layout && assert_directory_identity \(shellQuote(hostsDirectory.path)) \(shellQuote(shellIdentity(hostsDirectoryIdentity))) || exit 45")
            lines.append("/bin/mv -f \"$hosts_backup_tmp\" \(shellQuote(hostsBackup))")
            lines.append("hosts_backup_identity=$(/usr/bin/stat -f '%d:%i' \(shellQuote(hostsBackup)))")
            lines.append("assert_regular_file_identity_hash \(shellQuote(hostsBackup)) \"$hosts_backup_identity\" \(shellQuote(hostsCleanup.originalSHA256)) || exit 45")
        }

        for (index, item) in items.enumerated() {
            if let context {
                lines.append("if [ -e \(shellQuote(context.cancelURL.path)) ]; then append_log \(shellQuote(L10n.text("MEGSZAKÍTÁS KÉRVE", "CANCELLATION REQUESTED") + " | " + item.path)) || true; echo ABESWEEP_OPERATION_CANCELLED >&2; exit 130; fi")
                lines.append("write_progress \(shellQuote(progressJSON(completed: progressOffset + index, total: reportedTotal, currentPath: item.path, stage: "working")))")
                lines.append("append_log \(shellQuote(L10n.text("FELDOLGOZÁS", "PROCESSING") + " | " + item.path))")
                if items.count <= 20 {
                    lines.append("/bin/sleep 0.15")
                } else if items.count <= 50 {
                    lines.append("/bin/sleep 0.06")
                }
            }
            let relative = item.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let target = root + "/payload/" + relative
            let targetParent = (target as NSString).deletingLastPathComponent
            guard let targetParentIdentity = quarantineParentIdentities[item.path] else {
                throw CleanupError.invalidQuarantinePath
            }
            let validation = shellPreMoveValidation(item: item, path: item.path)
            lines.append("assert_session_layout || { echo \(shellQuote(L10n.text("A karantén útvonala megváltozott.", "The quarantine path changed."))) >&2; exit 45; }")
            lines.append("assert_directory_identity \(shellQuote(targetParent)) \(shellQuote(shellIdentity(targetParentIdentity))) || { echo \(shellQuote(L10n.text("A karantén célútvonala hivatkozást tartalmaz.", "The quarantine destination contains a symbolic link."))) >&2; exit 45; }")
            lines.append("assert_session_layout && assert_directory_identity \(shellQuote(targetParent)) \(shellQuote(shellIdentity(targetParentIdentity))) || { echo \(shellQuote(L10n.text("A karantén célútvonala időközben megváltozott.", "The quarantine destination changed before the move."))) >&2; exit 45; }")
            if context != nil {
                lines.append("if [ -e \(shellQuote(item.path)) ] || [ -L \(shellQuote(item.path)) ]; then \(validation); move_without_replacing \(shellQuote(item.path)) \(shellQuote(target)); moved_\(index)=1; append_log \(shellQuote(L10n.text("KARANTÉNBA HELYEZVE", "QUARANTINED") + " | " + item.path)); else append_log \(shellQuote(L10n.text("KIHAGYVA, MÁR NEM TALÁLHATÓ", "SKIPPED, NO LONGER FOUND") + " | " + item.path)); fi")
                lines.append("write_progress \(shellQuote(progressJSON(completed: progressOffset + index + 1, total: reportedTotal, currentPath: item.path, stage: "working")))")
            } else {
                lines.append("if [ -e \(shellQuote(item.path)) ] || [ -L \(shellQuote(item.path)) ]; then \(validation); move_without_replacing \(shellQuote(item.path)) \(shellQuote(target)); moved_\(index)=1; fi")
            }
        }

        if let hostsCleanup {
            guard let preparedHostsFile,
                  let preparedIdentity = pathPolicy.identity(at: preparedHostsFile.path)
            else { throw CleanupError.invalidQuarantinePath }
            let hostsProgress = progressOffset + items.count
            if let context {
                lines.append("if [ -e \(shellQuote(context.cancelURL.path)) ]; then append_log \(shellQuote(L10n.text("MEGSZAKÍTÁS KÉRVE", "CANCELLATION REQUESTED") + " | /etc/hosts")) || true; echo ABESWEEP_OPERATION_CANCELLED >&2; exit 130; fi")
                lines.append("write_progress \(shellQuote(progressJSON(completed: hostsProgress, total: reportedTotal, currentPath: "/etc/hosts", stage: "working")))")
                lines.append("append_log \(shellQuote(L10n.text("FELDOLGOZÁS", "PROCESSING") + " | /etc/hosts | " + String(hostsCleanup.matchedHostnames.count) + " Adobe hostname(s)"))")
            }
            lines.append("hosts_tmp=$(/usr/bin/mktemp /private/etc/hosts.abesweep.XXXXXX)")
            lines.append("/bin/cp -p /etc/hosts \"$hosts_tmp\"")
            lines.append("assert_regular_file_identity_hash \(shellQuote(preparedHostsFile.path)) \(shellQuote(shellIdentity(preparedIdentity))) \(shellQuote(hostsCleanup.cleanedSHA256)) || exit 51")
            lines.append("/bin/cat \(shellQuote(preparedHostsFile.path)) > \"$hosts_tmp\"")
            lines.append("[ \"$(/usr/bin/shasum -a 256 \"$hosts_tmp\" | /usr/bin/awk '{print $1}')\" = \(shellQuote(hostsCleanup.cleanedSHA256)) ] || exit 51")
            lines.append("assert_hosts_hash \(shellQuote(hostsCleanup.originalSHA256)) || exit 47")
            lines.append("/bin/mv -f \"$hosts_tmp\" /etc/hosts")
            lines.append("hosts_modified=1")
            lines.append("/usr/bin/dscacheutil -flushcache 2>/dev/null || true")
            lines.append("/usr/bin/killall -HUP mDNSResponder 2>/dev/null || true")
            if context != nil {
                lines.append("append_log \(shellQuote(L10n.text("HOSTS KITAKARÍTVA", "HOSTS CLEANED") + " | " + hostsCleanup.matchedHostnames.joined(separator: ", ")))")
                lines.append("write_progress \(shellQuote(progressJSON(completed: hostsProgress + 1, total: reportedTotal, currentPath: "/etc/hosts", stage: "working")))")
            }
        }

        // Keep unselected parent directories, including their ownership and ACLs.
        // Recreating a user's empty Adobe directory as root would change access.

        if let context {
            lines.append("if [ -e \(shellQuote(context.cancelURL.path)) ]; then append_log \(shellQuote(L10n.text("MEGSZAKÍTÁS KÉRVE | A befejezés előtt", "CANCELLATION REQUESTED | Before finalization"))) || true; echo ABESWEEP_OPERATION_CANCELLED >&2; exit 130; fi")
        }

        // Moving preserves every item's original owner. Only the session folder
        // itself is handed to the current user; recursively changing ownership
        // would make restored system services unsafe.
        lines.append("assert_session_layout || exit 45")
        lines.append("chown \(uid):\(gid) \(shellQuote(root))")
        lines.append("trap - EXIT")
        if let context {
            lines.append("append_log \(shellQuote(L10n.text("SIKERES | A takarítás befejeződött", "SUCCESS | Cleanup completed"))) || true")
            lines.append("write_progress \(shellQuote(progressJSON(completed: reportedTotal, total: reportedTotal, currentPath: L10n.text("Kész", "Done"), stage: "finished"))) || true")
            lines.append("chown \(uid):\(gid) \(shellQuote(context.logURL.path)) 2>/dev/null || true")
        }
        return lines.joined(separator: "\n")
    }

    private func progressJSON(completed: Int, total: Int, currentPath: String, stage: String) -> String {
        let state = CleanupProgressState(
            completed: completed,
            total: total,
            currentPath: currentPath,
            stage: stage
        )
        let data = try? JSONEncoder().encode(state)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    func buildRestoreCommand(session: CleanupSession, uid: uid_t) throws -> String {
        let session = try validateRestoreSession(session, requirePayload: false)
        let root = session.quarantinePath
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let baseURL = rootURL.deletingLastPathComponent()
        let payloadURL = rootURL.appendingPathComponent("payload", isDirectory: true)
        guard pathPolicy.isSafeContainer(baseURL),
              pathPolicy.isSafeContainer(rootURL),
              pathPolicy.isSafeContainer(payloadURL),
              let baseIdentity = pathPolicy.identity(at: baseURL.path),
              let rootIdentity = pathPolicy.identity(at: root),
              let payloadIdentity = pathPolicy.identity(at: payloadURL.path)
        else { throw CleanupError.invalidQuarantinePath }

        var validatedLaunchServices: [ValidatedLaunchService] = []
        var payloadParentIdentities: [String: FileIdentity] = [:]
        for item in session.items {
            let source = quarantineURL(for: item, destination: rootURL)
            if entryExists(at: source) {
                let parent = source.deletingLastPathComponent()
                guard pathPolicy.isSafeContainer(parent),
                      let identity = pathPolicy.identity(at: parent.path)
                else { throw CleanupError.invalidQuarantinePath }
                payloadParentIdentities[item.path] = identity
            }
            guard entryExists(at: source), pathPolicy.isValidatedLaunchServicePath(item) else {
                continue
            }
            guard let service = validatedLaunchService(
                for: item,
                plistURL: source,
                quarantineRoot: rootURL
            ) else {
                throw CleanupError.invalidManifestItem(item.path)
            }
            validatedLaunchServices.append(service)
        }
        var lines = ["set -e"]
        lines.append(contentsOf: shellPathValidationFunctions())
        lines.append("assert_session_layout() { assert_directory_identity \(shellQuote(baseURL.path)) \(shellQuote(shellIdentity(baseIdentity))) && assert_directory_identity \(shellQuote(root)) \(shellQuote(shellIdentity(rootIdentity))) && assert_directory_identity \(shellQuote(payloadURL.path)) \(shellQuote(shellIdentity(payloadIdentity))); }")
        lines.append("assert_session_layout || { echo \(shellQuote(L10n.text("A karantén útvonala megváltozott.", "The quarantine path changed."))) >&2; exit 45; }")

        var validatedHostsBackup: (identity: FileIdentity, expectedSHA256: String, cleanedSHA256: String)?
        if let hostsCleanup = session.hostsCleanup {
            let hostsBackup = root + "/hosts/original"
            guard isRegularFileWithoutFollowingSymlinks(URL(fileURLWithPath: hostsBackup)),
                  let hostsBackupIdentity = pathPolicy.identity(at: hostsBackup)
            else { throw CleanupError.invalidManifestItem(hostsBackup) }
            try validateHostsBackup(
                at: URL(fileURLWithPath: hostsBackup),
                expectedIdentity: hostsBackupIdentity,
                expectedSHA256: hostsCleanup.originalSHA256
            )
            validatedHostsBackup = (hostsBackupIdentity, hostsCleanup.originalSHA256, hostsCleanup.cleanedSHA256)
            lines.append("assert_session_layout && assert_regular_file_identity_hash \(shellQuote(hostsBackup)) \(shellQuote(shellIdentity(hostsBackupIdentity))) \(shellQuote(hostsCleanup.originalSHA256)) || { echo \(shellQuote(L10n.text("A hosts biztonsági mentése megváltozott, ezért a visszaállítás leállt.", "The hosts backup changed, so restore was stopped."))) >&2; exit 53; }")
            lines.append("hosts_hash=$(/usr/bin/shasum -a 256 /etc/hosts | /usr/bin/awk '{print $1}')")
            lines.append("if [ \"$hosts_hash\" != \(shellQuote(hostsCleanup.cleanedSHA256)) ]; then echo \(shellQuote(L10n.text("A hosts fájl a takarítás óta megváltozott, ezért az AbeSweep nem írja felül. A többi elem sem változott.", "The hosts file changed after cleanup, so AbeSweep will not overwrite it. No other item was changed."))) >&2; exit 49; fi")
        }

        // Check every destination before moving anything, so a newly created
        // file can never leave a restore operation half-finished.
        for item in session.items.sorted(by: { $0.path.count < $1.path.count }) {
            let relative = item.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let source = root + "/payload/" + relative
            lines.append("if { [ -e \(shellQuote(source)) ] || [ -L \(shellQuote(source)) ]; } && { [ -e \(shellQuote(item.path)) ] || [ -L \(shellQuote(item.path)) ]; }; then echo \(shellQuote(L10n.text("A cél már létezik: ", "Destination already exists: ") + item.path)) >&2; exit 42; fi")
        }
        for index in session.items.indices {
            lines.append("restored_\(index)=0")
        }
        lines.append(contentsOf: [
            "rollback() {",
            "status=$?",
            "set +e",
            "rollback_failed=0",
            "trap - EXIT",
            "if [ \"$status\" -ne 0 ]; then"
        ])
        for index in session.items.indices.reversed() {
            let item = session.items[index]
            let relative = item.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let source = root + "/payload/" + relative
            let sourceParent = (source as NSString).deletingLastPathComponent
            let identity = shellIdentity(item.sourceIdentity)
            let sourceParentIdentity = shellIdentity(payloadParentIdentities[item.path])
            lines.append("if [ \"$restored_\(index)\" -eq 1 ]; then if assert_session_layout && assert_directory_identity \(shellQuote(sourceParent)) \(shellQuote(sourceParentIdentity)) && assert_no_symlink_parents \(shellQuote(item.path)) && assert_identity \(shellQuote(item.path)) \(shellQuote(identity)); then if assert_session_layout && assert_directory_identity \(shellQuote(sourceParent)) \(shellQuote(sourceParentIdentity)) && assert_no_symlink_parents \(shellQuote(item.path)) && assert_identity \(shellQuote(item.path)) \(shellQuote(identity)); then move_without_replacing \(shellQuote(item.path)) \(shellQuote(source)) || rollback_failed=1; else rollback_failed=1; fi; else rollback_failed=1; fi; fi")
        }
        lines.append("if [ -n \"${hosts_tmp:-}\" ]; then /bin/rm -f \"$hosts_tmp\" 2>/dev/null || true; fi")
        lines.append(contentsOf: [
            "fi",
            "if [ \"$rollback_failed\" -ne 0 ]; then echo ABESWEEP_ROLLBACK_FAILED >&2; echo \(shellQuote(L10n.text("A visszaállítás visszagörgetése nem fejeződött be.", "Restore rollback did not complete."))) >&2; exit 52; fi",
            "exit \"$status\"",
            "}",
            "trap rollback EXIT"
        ])
        let orderedRestoreItems = session.items.enumerated().sorted { $0.element.path.count < $1.element.path.count }
        for (index, item) in orderedRestoreItems {
            let relative = item.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let source = root + "/payload/" + relative
            let parent = (item.path as NSString).deletingLastPathComponent
            let identity = shellIdentity(item.sourceIdentity)
            let sourceParent = (source as NSString).deletingLastPathComponent
            let sourceParentIdentity = shellIdentity(payloadParentIdentities[item.path])
            lines.append("if [ -e \(shellQuote(source)) ] || [ -L \(shellQuote(source)) ]; then assert_session_layout && assert_directory_identity \(shellQuote(sourceParent)) \(shellQuote(sourceParentIdentity)) && assert_no_symlink_parents \(shellQuote(item.path)) && assert_identity \(shellQuote(source)) \(shellQuote(identity)) || { echo \(shellQuote(L10n.text("A visszaállítandó elem megváltozott.", "The quarantined item changed before restore."))) >&2; exit 45; }; mkdir -p \(shellQuote(parent)); assert_session_layout && assert_directory_identity \(shellQuote(sourceParent)) \(shellQuote(sourceParentIdentity)) && assert_no_symlink_parents \(shellQuote(item.path)) && assert_identity \(shellQuote(source)) \(shellQuote(identity)) || exit 45; move_without_replacing \(shellQuote(source)) \(shellQuote(item.path)); restored_\(index)=1; fi")
        }

        if let validatedHostsBackup {
            let hostsBackup = root + "/hosts/original"
            lines.append("hosts_tmp=$(/usr/bin/mktemp /private/etc/hosts.abesweep.restore.XXXXXX)")
            lines.append("assert_session_layout && assert_regular_file_identity_hash \(shellQuote(hostsBackup)) \(shellQuote(shellIdentity(validatedHostsBackup.identity))) \(shellQuote(validatedHostsBackup.expectedSHA256)) || { /bin/rm -f \"$hosts_tmp\" 2>/dev/null || true; echo \(shellQuote(L10n.text("A hosts biztonsági mentése a használat előtt megváltozott.", "The hosts backup changed immediately before use."))) >&2; exit 53; }")
            lines.append("/bin/cp -p \(shellQuote(hostsBackup)) \"$hosts_tmp\"")
            lines.append("[ \"$(/usr/bin/shasum -a 256 \"$hosts_tmp\" | /usr/bin/awk '{print $1}')\" = \(shellQuote(validatedHostsBackup.expectedSHA256)) ] || { /bin/rm -f \"$hosts_tmp\"; exit 53; }")
            lines.append("assert_hosts_hash \(shellQuote(validatedHostsBackup.cleanedSHA256)) || exit 49")
            lines.append("/bin/mv -f \"$hosts_tmp\" /etc/hosts")
            lines.append("/usr/bin/dscacheutil -flushcache 2>/dev/null || true")
            lines.append("/usr/bin/killall -HUP mDNSResponder 2>/dev/null || true")
        }
        // No fallible data operation follows this commit. Failure to archive
        // metadata must not roll back files after hosts was already restored.
        lines.append("trap - EXIT")
        for service in validatedLaunchServices {
            let item = service.item
            let launchValidation = shellLaunchServiceValidation(service, plistPath: item.path)
            if item.path.hasPrefix("/Library/LaunchDaemons/") {
                lines.append("if \(launchValidation); then /bin/launchctl bootstrap system \(shellQuote(item.path)) 2>/dev/null || true; fi")
            } else {
                lines.append("if \(launchValidation); then /bin/launchctl bootstrap gui/\(uid) \(shellQuote(item.path)) 2>/dev/null || true; fi")
            }
        }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        if isRegularFileWithoutFollowingSymlinks(manifestURL),
           let manifestIdentity = pathPolicy.identity(at: manifestURL.path),
           let manifestData = try? Data(contentsOf: manifestURL, options: .mappedIfSafe) {
            let restoredManifest = rootURL.appendingPathComponent("restored-manifest.json")
            lines.append("if assert_session_layout && assert_regular_file_identity_hash \(shellQuote(manifestURL.path)) \(shellQuote(shellIdentity(manifestIdentity))) \(shellQuote(sha256(manifestData))) && [ ! -e \(shellQuote(restoredManifest.path)) ] && [ ! -L \(shellQuote(restoredManifest.path)) ]; then /bin/mv -n \(shellQuote(manifestURL.path)) \(shellQuote(restoredManifest.path)) || true; fi")
        }
        return lines.joined(separator: "\n")
    }

    func requiresAppDataAuthorization(path: String) -> Bool {
        let library = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        let protectedRoots = [
            library.appendingPathComponent("Containers", isDirectory: true).path,
            library.appendingPathComponent("Group Containers", isDirectory: true).path
        ]
        return protectedRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func quarantineURL(for item: CleanupItem, destination: URL) -> URL {
        destination
            .appendingPathComponent("payload", isDirectory: true)
            .appendingPathComponent(item.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func entryExists(at url: URL) -> Bool {
        if fileManager.fileExists(atPath: url.path) { return true }
        return (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func isValidSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
    }

    private struct ValidatedLaunchService {
        let item: CleanupItem
        let executablePath: String
        let plistSHA256: String
    }

    private func validatedLaunchService(
        for item: CleanupItem,
        plistURL: URL,
        quarantineRoot: URL?
    ) -> ValidatedLaunchService? {
        guard pathPolicy.isValidatedLaunchServicePath(item),
              isRegularFileWithoutFollowingSymlinks(plistURL),
              pathPolicy.hasSafeParentPath(plistURL),
              let data = try? Data(contentsOf: plistURL, options: .mappedIfSafe),
              data.count <= 1_000_000,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let label = dictionary["Label"] as? String,
              label.lowercased().hasPrefix("com.adobe."),
              label.caseInsensitiveCompare(
                  item.url.deletingPathExtension().lastPathComponent
              ) == .orderedSame,
              !containsUnsafeLaunchdKeys(dictionary)
        else { return nil }

        let program = dictionary["Program"] as? String
        let arguments: [String]?
        if let rawArguments = dictionary["ProgramArguments"] {
            guard let parsedArguments = rawArguments as? [String],
                  !parsedArguments.isEmpty,
                  parsedArguments.count <= 128,
                  parsedArguments.allSatisfy({ !$0.contains("\0") && $0.count <= 16_384 })
            else { return nil }
            arguments = parsedArguments
        } else {
            arguments = nil
        }

        guard program != nil || arguments != nil else { return nil }
        if let program, let firstArgument = arguments?.first,
           program != firstArgument {
            return nil
        }
        guard let executablePath = program ?? arguments?.first,
              pathPolicy.isAllowedAdobeExecutablePath(executablePath)
        else { return nil }

        let installedExecutable = URL(fileURLWithPath: executablePath)
        let quarantinedExecutable = quarantineRoot.map {
            $0.appendingPathComponent("payload", isDirectory: true)
                .appendingPathComponent(
                    executablePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                )
        }
        let signingCandidate = ([installedExecutable] + [quarantinedExecutable].compactMap { $0 })
            .first {
                isRegularFileWithoutFollowingSymlinks($0)
                    && pathPolicy.hasSafeParentPath($0)
                    && teamIdentifierProvider($0.path) == CodeSigningIdentity.adobeTeamIdentifier
            }
        guard signingCandidate != nil else { return nil }

        return ValidatedLaunchService(
            item: item,
            executablePath: executablePath,
            plistSHA256: sha256(data)
        )
    }

    private func containsUnsafeLaunchdKeys(_ dictionary: [String: Any]) -> Bool {
        let unsafeKeys: Set<String> = [
            "EnvironmentVariables",
            "RootDirectory",
            "WorkingDirectory",
            "StandardInPath",
            "StandardOutPath",
            "StandardErrorPath",
            "UserName",
            "GroupName",
            "InitGroups",
            "SoftResourceLimits",
            "HardResourceLimits",
            "Sockets"
        ]
        return !unsafeKeys.isDisjoint(with: dictionary.keys)
    }

    private func isRegularFileWithoutFollowingSymlinks(_ url: URL) -> Bool {
        var information = stat()
        let result = url.path.withCString { Darwin.lstat($0, &information) }
        return result == 0 && information.st_mode & S_IFMT == S_IFREG
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func validateHostsBackup(
        at url: URL,
        expectedIdentity: FileIdentity,
        expectedSHA256: String
    ) throws {
        guard pathPolicy.hasSafeParentPath(url),
              isRegularFileWithoutFollowingSymlinks(url),
              pathPolicy.identity(at: url.path) == expectedIdentity,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              sha256(data) == expectedSHA256
        else { throw CleanupError.sourceChanged(url.path) }
    }

    private func writeProgress(
        completed: Int,
        total: Int,
        currentPath: String,
        stage: String,
        context: CleanupRunContext
    ) throws {
        let state = CleanupProgressState(
            completed: completed,
            total: total,
            currentPath: currentPath,
            stage: stage
        )
        try JSONEncoder().encode(state).write(to: context.statusURL, options: .atomic)
    }

    private func appendLog(_ message: String, context: CleanupRunContext) {
        guard let handle = try? FileHandle(forWritingTo: context.logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            let line = "\(Date().formatted(date: .numeric, time: .standard)) | \(message)\n"
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            return
        }
    }

    private func rollbackDirectlyMoved(
        _ items: [CleanupItem],
        destination: URL,
        context: CleanupRunContext
    ) -> Error? {
        guard !items.isEmpty else { return nil }
        appendLog(
            L10n.text("VISSZAÁLLÍTÁS | Az alkalmazásadatok visszagörgetése", "ROLLBACK | Reverting application data"),
            context: context
        )
        var firstError: Error?
        for item in items.reversed() {
            let source = quarantineURL(for: item, destination: destination)
            guard entryExists(at: source) else { continue }
            do {
                guard !entryExists(at: item.url) else {
                    throw CleanupError.commandFailed(L10n.text("A cél már létezik: ", "Destination already exists: ") + item.path)
                }
                try pathPolicy.validateRestoreMove(
                    source: source,
                    destinationPath: item.path,
                    expectedIdentity: item.sourceIdentity
                )
                try fileManager.createDirectory(at: item.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try pathPolicy.validateRestoreMove(
                    source: source,
                    destinationPath: item.path,
                    expectedIdentity: item.sourceIdentity
                )
                try fileManager.moveItem(at: source, to: item.url)
                appendLog(L10n.text("VISSZAÁLLÍTVA", "RESTORED") + " | " + item.path, context: context)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        return firstError
    }

    private func rollbackDirectlyRestored(
        _ items: [CleanupItem],
        destination: URL
    ) -> Error? {
        var firstError: Error?
        for item in items.reversed() {
            let target = quarantineURL(for: item, destination: destination)
            guard entryExists(at: item.url) else { continue }
            do {
                guard !entryExists(at: target) else {
                    throw CleanupError.commandFailed(L10n.text("A cél már létezik: ", "Destination already exists: ") + target.path)
                }
                try pathPolicy.validateRestoreMove(
                    source: item.url,
                    destinationPath: target.path,
                    expectedIdentity: item.sourceIdentity
                )
                guard pathPolicy.isSafeContainer(target.deletingLastPathComponent()) else {
                    throw CleanupError.invalidQuarantinePath
                }
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try pathPolicy.validateRestoreMove(
                    source: item.url,
                    destinationPath: target.path,
                    expectedIdentity: item.sourceIdentity
                )
                guard pathPolicy.isSafeContainer(target.deletingLastPathComponent()) else {
                    throw CleanupError.invalidQuarantinePath
                }
                try fileManager.moveItem(at: item.url, to: target)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        return firstError
    }

    private func removeFailedSessionIfEmpty(_ session: CleanupSession) {
        guard !quarantineRecord(for: session).hasRestorableContent else { return }
        let root = URL(fileURLWithPath: session.quarantinePath).standardizedFileURL
        let base = quarantineBaseURL.standardizedFileURL
        guard root.deletingLastPathComponent().path == base.path,
              root.path != base.path
        else { return }
        try? fileManager.removeItem(at: root)
    }

    func buildPermanentDeleteCommand(session: CleanupSession) throws -> String {
        let rootURL = try validatedQuarantineRoot(session.quarantinePath, allowedBases: allowedQuarantineBaseURLs)
        let baseURL = rootURL.deletingLastPathComponent()
        guard let baseIdentity = pathPolicy.identity(at: baseURL.path),
              let rootIdentity = pathPolicy.identity(at: rootURL.path),
              (try? rootURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { throw CleanupError.invalidQuarantinePath }
        return (["set -e"] + shellPathValidationFunctions() + [
            "assert_directory_identity \(shellQuote(baseURL.path)) \(shellQuote(shellIdentity(baseIdentity))) && assert_directory_identity \(shellQuote(rootURL.path)) \(shellQuote(shellIdentity(rootIdentity))) || { echo \(shellQuote(L10n.text("A karantén útvonala megváltozott; a törlés leállt.", "The quarantine path changed; deletion was stopped."))) >&2; exit 43; }",
            "/bin/rm -rf -- \(shellQuote(rootURL.path))"
        ]).joined(separator: "\n")
    }

    func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func shellPathValidationFunctions() -> [String] {
        [
            "assert_hosts_hash() { [ -f /etc/hosts ] && [ ! -L /etc/hosts ] && [ \"$(/usr/bin/shasum -a 256 /etc/hosts | /usr/bin/awk '{print $1}')\" = \"$1\" ]; }",
            "move_without_replacing() { [ \"${1##*/}\" = \"${2##*/}\" ] && [ ! -e \"$2\" ] && [ ! -L \"$2\" ] || return 1; /bin/mv -n \"$1\" \"${2%/*}/\" || return 1; [ ! -e \"$1\" ] && [ ! -L \"$1\" ]; }",
            "assert_no_symlink_parents() { candidate=${1%/*}; [ -n \"$candidate\" ] || candidate=/; while [ \"$candidate\" != / ]; do [ ! -L \"$candidate\" ] || return 1; candidate=${candidate%/*}; [ -n \"$candidate\" ] || candidate=/; done; }",
            "assert_identity() { actual=$(/usr/bin/stat -f '%d:%i' \"$1\" 2>/dev/null) || return 1; [ \"$actual\" = \"$2\" ]; }",
            "assert_directory_identity() { [ -d \"$1\" ] && [ ! -L \"$1\" ] && assert_no_symlink_parents \"$1\" && assert_identity \"$1\" \"$2\"; }",
            "assert_regular_file_identity() { [ -f \"$1\" ] && [ ! -L \"$1\" ] && assert_no_symlink_parents \"$1\" && assert_identity \"$1\" \"$2\"; }",
            "assert_regular_file_identity_hash() { assert_regular_file_identity \"$1\" \"$2\" || return 1; actual_hash=$(/usr/bin/shasum -a 256 \"$1\" 2>/dev/null | /usr/bin/awk '{print $1}') || return 1; [ \"$actual_hash\" = \"$3\" ]; }",
            "assert_adobe_signed() { [ -f \"$1\" ] && [ ! -L \"$1\" ] && assert_no_symlink_parents \"$1\" && /usr/bin/codesign --verify --strict \"$1\" >/dev/null 2>&1 && /usr/bin/codesign -dv --verbose=4 \"$1\" 2>&1 | /usr/bin/grep -Fqx 'TeamIdentifier=\(CodeSigningIdentity.adobeTeamIdentifier)'; }"
        ]
    }

    private func shellIdentity(_ identity: FileIdentity?) -> String {
        guard let identity else { return "missing" }
        return "\(identity.device):\(identity.inode)"
    }

    private func shellPreMoveValidation(item: CleanupItem, path: String) -> String {
        let message = shellQuote(L10n.text(
            "Az elem a vizsgálat óta megváltozott vagy az útvonala hivatkozást tartalmaz.",
            "The item changed after the scan or its path contains a symbolic link."
        ))
        return "assert_no_symlink_parents \(shellQuote(path)) && assert_identity \(shellQuote(path)) \(shellQuote(shellIdentity(item.sourceIdentity))) || { echo \(message) >&2; exit 45; }"
    }

    private func shellLaunchServiceValidation(
        _ service: ValidatedLaunchService,
        plistPath: String
    ) -> String {
        "assert_regular_file_identity_hash \(shellQuote(plistPath)) \(shellQuote(shellIdentity(service.item.sourceIdentity))) \(shellQuote(service.plistSHA256)) && assert_adobe_signed \(shellQuote(service.executablePath))"
    }

    private func runAsAdministrator(_ command: String) async throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    process.arguments = ["-e", script]
                    process.standardOutput = FileHandle.nullDevice
                    let errorPipe = Pipe()
                    process.standardError = errorPipe
                    try process.run()
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if process.terminationStatus != 0 {
                        let message = String(data: data, encoding: .utf8) ?? ""
                        throw Self.administratorError(message: message)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func administratorError(message: String) -> CleanupError {
        if message.contains("ABESWEEP_ROLLBACK_FAILED") || message.contains("(52)") {
            return .commandFailed(L10n.text(
                "A visszagörgetés nem fejeződött be. A karanténban maradt adatokat őrizd meg, és ellenőrizd a naplót.",
                "Rollback did not complete. Keep the remaining quarantine data and check the log."
            ))
        }
        if message.contains("ABESWEEP_OPERATION_CANCELLED") { return .operationCancelled }
        if message.contains("(-128)") { return .authorizationCancelled }
        return .commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
