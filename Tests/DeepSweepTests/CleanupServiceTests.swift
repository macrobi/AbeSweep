import Darwin
import Foundation
import Testing
@testable import AbeSweep

func makeTestFixtureRoot(_ name: String, filePath: String = #filePath) throws -> URL {
    let repositoryRoot = URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixtures = repositoryRoot
        .appendingPathComponent("Output/verification/TestFixtures", isDirectory: true)
    try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
    let root = fixtures.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
}

struct CleanupServiceTests {
    @Test func runContextResolvesSystemStyleTemporaryDirectorySymlink() throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("TemporaryAlias")
        defer { try? fileManager.removeItem(at: testRoot) }
        let realTemporaryDirectory = testRoot.appendingPathComponent("private-temporary")
        let temporaryAlias = testRoot.appendingPathComponent("var-style-alias")
        let logDirectory = testRoot.appendingPathComponent("logs")
        try fileManager.createDirectory(at: realTemporaryDirectory, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: temporaryAlias,
            withDestinationURL: realTemporaryDirectory
        )

        let context = try CleanupRunContext.create(
            items: [],
            fileManager: fileManager,
            temporaryDirectory: temporaryAlias,
            logDirectory: logDirectory
        )
        #expect(context.directory.deletingLastPathComponent().path == realTemporaryDirectory.path)

        let destination = testRoot.appendingPathComponent("Quarantine/session")
        let manifest = testRoot.appendingPathComponent("manifest.json")
        try prepareQuarantineLayout(destination: destination, manifest: manifest)
        let command = try CleanupService(
            home: testRoot,
            quarantineBaseURLs: [testRoot.appendingPathComponent("Quarantine")]
        ).buildQuarantineCommand(
            items: [],
            destination: destination,
            manifest: manifest,
            uid: getuid(),
            gid: getgid(),
            context: context
        )

        #expect(command.contains("assert_context_layout"))
    }

    @Test func hostsCleanupCommandBacksUpValidatesAndRewritesAtomically() throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("HostsCommand")
        defer { try? fileManager.removeItem(at: testRoot) }
        let plan = try #require(HostsFileService().plan(content: "127.0.0.1 localhost\n0.0.0.0 activate.adobe.com\n"))
        let destination = testRoot.appendingPathComponent("Quarantine/session")
        let manifest = testRoot.appendingPathComponent("manifest.json")
        let preparedHosts = testRoot.appendingPathComponent("hosts-cleaned")
        try fileManager.createDirectory(at: testRoot, withIntermediateDirectories: true)
        try Data(plan.cleanedContent.utf8).write(to: preparedHosts)
        try prepareQuarantineLayout(
            destination: destination,
            manifest: manifest,
            needsHostsDirectory: true
        )
        let command = try CleanupService(
            home: testRoot,
            quarantineBaseURLs: [testRoot.appendingPathComponent("Quarantine")]
        ).buildQuarantineCommand(
            items: [],
            hostsCleanup: plan,
            preparedHostsFile: preparedHosts,
            destination: destination,
            manifest: manifest,
            uid: 501,
            gid: 20,
            progressTotal: 1
        )

        #expect(command.contains(plan.originalSHA256))
        #expect(command.contains("/hosts/original"))
        #expect(command.contains("mktemp /private/etc/hosts.abesweep.XXXXXX"))
        #expect(command.contains("mktemp /private/etc/hosts.abesweep.rollback.XXXXXX"))
        #expect(command.contains("/bin/cat \(CleanupService().shellQuote(preparedHosts.path)) > \"$hosts_tmp\""))
        #expect(command.contains("assert_hosts_hash \(CleanupService().shellQuote(plan.originalSHA256)) || exit 47"))
        #expect(command.contains("dscacheutil -flushcache"))
        #expect(command.contains("rollback_failed=1"))
        #expect(!command.contains("/bin/cp -p '\(URL(fileURLWithPath: "/tmp/AbeSweep-Hosts-Test/hosts/original").path)' /etc/hosts || true"))
    }

    @Test func hostsRestoreRefusesToOverwriteLaterChanges() throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("HostsRestore")
        defer { try? fileManager.removeItem(at: testRoot) }
        let plan = try #require(HostsFileService().plan(content: "0.0.0.0 activate.adobe.com\n"))
        let quarantineBase = testRoot.appendingPathComponent("Quarantine")
        let quarantine = quarantineBase.appendingPathComponent("session")
        let backup = quarantine.appendingPathComponent("hosts/original")
        try fileManager.createDirectory(
            at: quarantine.appendingPathComponent("payload"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(plan.originalContent.utf8).write(to: backup)
        let session = CleanupSession(
            createdAt: Date(),
            quarantinePath: quarantine.path,
            items: [],
            logPath: nil,
            hostsCleanup: plan.record
        )

        let command = try CleanupService(
            home: testRoot,
            quarantineBaseURLs: [quarantineBase]
        ).buildRestoreCommand(session: session, uid: 501)
        #expect(command.contains(plan.cleanedSHA256))
        #expect(command.contains("assert_regular_file_identity_hash"))
        #expect(command.contains(plan.originalSHA256))
        #expect(command.contains("exit 53"))
        #expect(command.contains("exit 49"))
        #expect(command.contains("hosts.abesweep.restore.XXXXXX"))
    }

    @Test func manifestRestoreRejectsMalformedHostsHashes() throws {
        let service = CleanupService(
            quarantineBaseURLs: [URL(fileURLWithPath: "/private/tmp")]
        )
        let session = CleanupSession(
            createdAt: Date(),
            quarantinePath: "/private/tmp/AbeSweep-Invalid-Hosts-Manifest",
            items: [],
            logPath: nil,
            hostsCleanup: HostsCleanupRecord(
                originalSHA256: "not-a-digest",
                cleanedSHA256: String(repeating: "0", count: 64),
                removedHostnames: []
            )
        )

        #expect(throws: CleanupError.self) {
            try service.validateRestoreSession(session, requirePayload: false)
        }
    }

    @Test func olderSessionManifestWithoutHostsFieldStillDecodes() throws {
        let json = """
        {"createdAt":0,"items":[],"logPath":null,"quarantinePath":"/tmp/old-session"}
        """
        let session = try JSONDecoder().decode(CleanupSession.self, from: Data(json.utf8))
        #expect(session.hostsCleanup == nil)
    }

    @Test func shellQuotingHandlesApostrophes() {
        let service = CleanupService()
        #expect(service.shellQuote("/tmp/Adobe's file") == "'/tmp/Adobe'\\''s file'")
    }

    @Test func commandPreservesAbsoluteDirectoryStructure() throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("CommandStructure")
        defer { try? fileManager.removeItem(at: testRoot) }
        let source = testRoot.appendingPathComponent("Library/Preferences/com.adobe.test.plist")
        try fileManager.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test".utf8).write(to: source)
        let destination = testRoot.appendingPathComponent("Quarantine/session")
        let manifest = testRoot.appendingPathComponent("manifest.json")
        try prepareQuarantineLayout(destination: destination, manifest: manifest)
        let service = CleanupService(
            home: testRoot,
            systemLibrary: testRoot.appendingPathComponent("Library"),
            quarantineBaseURLs: [testRoot.appendingPathComponent("Quarantine")]
        )
        let item = try #require(service.validateItemsForQuarantine([CleanupItem(
            path: source.path,
            category: .settings,
            risk: .medium,
            size: 12,
            reason: "Test",
            bundleIdentifier: nil,
            scope: .adobeProduct
        )]).first)
        let command = try service.buildQuarantineCommand(
            items: [item],
            destination: destination,
            manifest: manifest,
            uid: 501,
            gid: 20
        )
        #expect(command.contains("payload/" + source.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        #expect(command.contains("chown 501:20"))
        #expect(!command.contains("chown -R"))
    }

    @Test func administratorCommandDisablesOnlyValidatedLaunchJobsWithoutNameOnlyProcessKills() throws {
        let fixture = try makeLaunchServiceFixture(teamIdentifier: CodeSigningIdentity.adobeTeamIdentifier)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let item = try #require(fixture.service.validateItemsForQuarantine([CleanupItem(
            path: fixture.plist.path,
            category: .service,
            risk: .medium,
            size: 12,
            reason: "Test",
            bundleIdentifier: nil,
            scope: .creativeCloudInfrastructure
        )]).first)
        let command = try fixture.service.buildQuarantineCommand(
            items: [item],
            destination: fixture.sessionRoot,
            manifest: fixture.manifest,
            uid: 501,
            gid: 20
        )

        let bootout = try #require(command.range(of: "launchctl bootout gui/501"))
        let move = try #require(command.range(of: "move_without_replacing \(fixture.service.shellQuote(fixture.plist.path))"))
        #expect(bootout.lowerBound < move.lowerBound)
        #expect(!command.contains("pkill"))
    }

    @Test func creativeCloudProcessesAreRecognizedOutsideRunningApplications() {
        let controller = AdobeProcessController { path in
            path.contains("/Adobe/") ? CodeSigningIdentity.adobeTeamIdentifier : nil
        }
        let snapshots = [
            AdobeProcessSnapshot(
                processIdentifier: 101,
                name: "CCXProcess",
                executablePath: "/Library/Application Support/Adobe/CCXProcess/CCXProcess.app/Contents/MacOS/CCXProcess",
                bundleIdentifier: nil
            ),
            AdobeProcessSnapshot(
                processIdentifier: 102,
                name: "CoreSync",
                executablePath: nil,
                bundleIdentifier: nil
            ),
            AdobeProcessSnapshot(
                processIdentifier: 103,
                name: "Preview",
                executablePath: "/System/Applications/Preview.app/Contents/MacOS/Preview",
                bundleIdentifier: "com.apple.Preview"
            )
        ]

        let relevant = controller.relevantProcesses(
            from: snapshots,
            includesOfficePDFMaker: false
        )
        #expect(relevant.map(\.processIdentifier) == [101])
    }

    @Test func nonAdobeProcessWithAdobeProcessNameIsNotTerminated() {
        let impostor = AdobeProcessSnapshot(
            processIdentifier: 104,
            name: "CCXProcess",
            executablePath: "/Applications/Example.app/Contents/MacOS/CCXProcess",
            bundleIdentifier: "com.example.ccxprocess"
        )

        let nonAdobeSigner: AdobeProcessController.TeamIdentifierProvider = { _ in "NOT-ADOBE" }
        let isRelevant = AdobeProcessController.isRelevant(
            impostor,
            includesOfficePDFMaker: false,
            teamIdentifierProvider: nonAdobeSigner
        )
        #expect(!isRelevant)
    }

    @Test func adobeBundleIdentifiersAndOfficePDFMakerHostsAreRecognized() {
        let adobe = AdobeProcessSnapshot(
            processIdentifier: 201,
            name: "Unusual helper name",
            executablePath: "/private/tmp/AdobeHelper",
            bundleIdentifier: "com.adobe.ccxprocess"
        )
        let word = AdobeProcessSnapshot(
            processIdentifier: 202,
            name: "Microsoft Word",
            executablePath: "/private/tmp/MicrosoftWord",
            bundleIdentifier: "com.microsoft.Word"
        )

        let adobeSigner: AdobeProcessController.TeamIdentifierProvider = {
            _ in CodeSigningIdentity.adobeTeamIdentifier
        }
        let microsoftSigner: AdobeProcessController.TeamIdentifierProvider = {
            _ in CodeSigningIdentity.microsoftTeamIdentifier
        }
        let adobeIsRelevant = AdobeProcessController.isRelevant(
            adobe,
            includesOfficePDFMaker: false,
            teamIdentifierProvider: adobeSigner
        )
        let wordWithoutPDFMakerIsRelevant = AdobeProcessController.isRelevant(
            word,
            includesOfficePDFMaker: false,
            teamIdentifierProvider: microsoftSigner
        )
        let wordWithPDFMakerIsRelevant = AdobeProcessController.isRelevant(
            word,
            includesOfficePDFMaker: true,
            teamIdentifierProvider: microsoftSigner
        )
        #expect(adobeIsRelevant)
        #expect(!wordWithoutPDFMakerIsRelevant)
        #expect(wordWithPDFMakerIsRelevant)
    }

    @Test func spoofedAdobeBundleIdentifierAndPathAreRejectedWithoutAdobeSigningIdentity() {
        let spoofedBundle = AdobeProcessSnapshot(
            processIdentifier: 203,
            name: "Helper",
            executablePath: "/Applications/Example.app/Contents/MacOS/Helper",
            bundleIdentifier: "com.adobe.ccxprocess"
        )
        let spoofedPath = AdobeProcessSnapshot(
            processIdentifier: 204,
            name: "CCXProcess",
            executablePath: "/Library/Application Support/Adobe/CCXProcess/CCXProcess",
            bundleIdentifier: nil
        )

        let attackerSigner: AdobeProcessController.TeamIdentifierProvider = { _ in "ATTACKERTEAM" }
        for process in [spoofedBundle, spoofedPath] {
            let isRelevant = AdobeProcessController.isRelevant(
                process,
                includesOfficePDFMaker: false,
                teamIdentifierProvider: attackerSigner
            )
            #expect(!isRelevant)
        }
    }

    @Test func protectedApplicationContainersAreHandledByTheAppProcess() {
        let service = CleanupService()
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        #expect(service.requiresAppDataAuthorization(
            path: home + "/Library/Containers/com.adobe.ContextMenuExtension"
        ))
        #expect(service.requiresAppDataAuthorization(
            path: home + "/Library/Group Containers/UBF8T346G9.Office/User Content/Startup/PDFMaker.dotm"
        ))
        #expect(!service.requiresAppDataAuthorization(
            path: home + "/Library/Caches/Adobe/CoreSync"
        ))
        #expect(!service.requiresAppDataAuthorization(
            path: "/Library/Application Support/Adobe"
        ))
    }

    @Test func administratorProgressContinuesAfterApplicationData() throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("Progress")
        defer { try? fileManager.removeItem(at: testRoot) }
        let source = testRoot.appendingPathComponent("Library/Preferences/com.adobe.test.plist")
        try fileManager.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test".utf8).write(to: source)
        let item = CleanupItem(
            path: source.path,
            category: .settings,
            risk: .medium,
            size: 12,
            reason: "Test",
            bundleIdentifier: nil,
            scope: .adobeProduct
        )
        let destination = testRoot.appendingPathComponent("Quarantine/session")
        let manifest = testRoot.appendingPathComponent("manifest.json")
        let context = CleanupRunContext(
            directory: testRoot.appendingPathComponent("run"),
            statusURL: testRoot.appendingPathComponent("run/status.json"),
            cancelURL: testRoot.appendingPathComponent("run/cancel"),
            logURL: testRoot.appendingPathComponent("run/operation.log")
        )
        try prepareQuarantineLayout(destination: destination, manifest: manifest, context: context)
        let service = CleanupService(
            home: testRoot,
            systemLibrary: testRoot.appendingPathComponent("Library"),
            quarantineBaseURLs: [testRoot.appendingPathComponent("Quarantine")]
        )
        let validatedItem = try #require(service.validateItemsForQuarantine([item]).first)
        let command = try service.buildQuarantineCommand(
            items: [validatedItem],
            destination: destination,
            manifest: manifest,
            uid: 501,
            gid: 20,
            context: context,
            progressOffset: 2,
            progressTotal: 3
        )

        #expect(command.contains("\"completed\":2"))
        #expect(command.contains("\"completed\":3"))
        #expect(command.contains("\"total\":3"))
    }

    @Test func restoreRefusesToOverwriteAndRestartsService() throws {
        let fixture = try makeLaunchServiceFixture(teamIdentifier: CodeSigningIdentity.adobeTeamIdentifier)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let scannedItem = CleanupItem(
            path: fixture.plist.path,
            category: .service,
            risk: .medium,
            size: 12,
            reason: "Test",
            bundleIdentifier: nil,
            scope: .creativeCloudInfrastructure
        )
        let item = try #require(fixture.service.validateItemsForQuarantine([scannedItem]).first)
        let stored = fixture.sessionRoot.appendingPathComponent("payload")
            .appendingPathComponent(item.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        try FileManager.default.createDirectory(at: stored.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: fixture.plist, to: stored)
        let session = CleanupSession(
            createdAt: Date(),
            quarantinePath: fixture.sessionRoot.path,
            items: [item],
            logPath: nil
        )
        let command = try fixture.service.buildRestoreCommand(session: session, uid: 501)
        #expect(command.contains(L10n.text("A cél már létezik", "Destination already exists")))
        #expect(command.contains("exit 42"))
        #expect(command.contains("launchctl bootstrap gui/501"))
        #expect(command.contains("trap rollback EXIT"))
        #expect(command.contains("trap - EXIT"))
    }

    @Test func quarantineRejectsValidLookingAdobePlistWithNonAdobeExecutableBeforeMovement() throws {
        let fixture = try makeLaunchServiceFixture(teamIdentifier: "ATTACKERTEAM")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let scannedItem = CleanupItem(
            path: fixture.plist.path,
            category: .service,
            risk: .medium,
            size: 12,
            reason: "Test",
            bundleIdentifier: nil,
            scope: .creativeCloudInfrastructure
        )
        #expect(throws: CleanupError.self) {
            try fixture.service.validateItemsForQuarantine([scannedItem])
        }
        #expect(FileManager.default.fileExists(atPath: fixture.plist.path))
        #expect(try FileManager.default.contentsOfDirectory(
            at: fixture.sessionRoot.appendingPathComponent("payload"),
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test func quarantineRejectsLaunchServiceWithMissingExecutableBeforeAnyItemMoves() throws {
        let fixture = try makeLaunchServiceFixture(teamIdentifier: CodeSigningIdentity.adobeTeamIdentifier)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.executable)

        let preference = fixture.root.appendingPathComponent("Library/Preferences/com.adobe.example.plist")
        try FileManager.default.createDirectory(
            at: preference.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("preference".utf8).write(to: preference)
        let items = [
            CleanupItem(
                path: fixture.plist.path,
                category: .service,
                risk: .medium,
                size: 12,
                reason: "Test",
                bundleIdentifier: nil,
                scope: .creativeCloudInfrastructure
            ),
            CleanupItem(
                path: preference.path,
                category: .settings,
                risk: .medium,
                size: 10,
                reason: "Test",
                bundleIdentifier: nil,
                scope: .adobeProduct
            )
        ]

        #expect(throws: CleanupError.self) {
            try fixture.service.validateItemsForQuarantine(items)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.plist.path))
        #expect(try String(contentsOf: preference, encoding: .utf8) == "preference")
        #expect(try FileManager.default.contentsOfDirectory(
            at: fixture.sessionRoot.appendingPathComponent("payload"),
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test func permanentDeleteTargetsOnlyOneAbeSweepSession() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = CleanupSession(
            createdAt: Date(), quarantinePath: fixture.sessionRoot.path,
            items: [], logPath: fixture.root.appendingPathComponent("kept.log").path
        )
        let sibling = fixture.sessionRoot.deletingLastPathComponent().appendingPathComponent("kept")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let command = try fixture.service.buildPermanentDeleteCommand(session: session)
        #expect(!command.contains("kept.log"))
        #expect(try runShell(command) == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.sessionRoot.path))
        #expect(FileManager.default.fileExists(atPath: sibling.path))
    }

    @Test func newQuarantineIsInsideTheCurrentUsersWritableApplicationSupport() throws {
        let service = CleanupService()
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AbeSweep/Quarantine", isDirectory: true)
        #expect(service.quarantineBaseURL.standardizedFileURL.path == expected.standardizedFileURL.path)

        let session = CleanupSession(
            createdAt: Date(),
            quarantinePath: expected.appendingPathComponent("nonexistent-\(UUID().uuidString)").path,
            items: [],
            logPath: nil
        )
        // A plausible path alone is insufficient: the session must exist.
        #expect(throws: CleanupError.self) {
            try service.buildPermanentDeleteCommand(session: session)
        }
    }

    @Test func existingQuarantineSessionsAreRecoveredFromTrustedManifests() throws {
        let fileManager = FileManager.default
        let base = try makeTestFixtureRoot("Discovery")
        defer { try? fileManager.removeItem(at: base) }
        let olderRoot = base.appendingPathComponent("older")
        let newerRoot = base.appendingPathComponent("newer")
        try fileManager.createDirectory(at: olderRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: newerRoot, withIntermediateDirectories: true)

        let older = CleanupSession(
            createdAt: Date(timeIntervalSince1970: 100),
            quarantinePath: olderRoot.path,
            items: [],
            logPath: nil
        )
        let newer = CleanupSession(
            createdAt: Date(timeIntervalSince1970: 200),
            quarantinePath: newerRoot.path,
            items: [],
            logPath: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(older).write(to: olderRoot.appendingPathComponent("manifest.json"))
        try encoder.encode(newer).write(to: newerRoot.appendingPathComponent("manifest.json"))

        let sessions = CleanupService().discoverQuarantineSessions(in: [base])

        #expect(sessions.map(\.quarantinePath) == [newerRoot.path, olderRoot.path])

        let records = CleanupService().discoverQuarantineRecords(in: [base])
        #expect(records.count == 2)
        #expect(records.allSatisfy { !$0.hasRestorableContent })
    }

    @Test func quarantineRecordCountsOnlyContentThatActuallyStillExists() throws {
        let fileManager = FileManager.default
        let base = try makeTestFixtureRoot("Contents")
        defer { try? fileManager.removeItem(at: base) }
        let root = base.appendingPathComponent("session")
        let originalPath = "/Library/Application Support/Adobe/example.dat"
        let stored = root.appendingPathComponent("payload/Library/Application Support/Adobe/example.dat")
        try fileManager.createDirectory(at: stored.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test".utf8).write(to: stored)

        let session = CleanupSession(
            createdAt: Date(),
            quarantinePath: root.path,
            items: [CleanupItem(
                path: originalPath,
                category: .sharedComponent,
                risk: .medium,
                size: 4,
                reason: "test",
                bundleIdentifier: nil,
                scope: .adobeProduct
            )],
            logPath: "/tmp/separate.log"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(session).write(to: root.appendingPathComponent("manifest.json"))

        let record = try #require(CleanupService().discoverQuarantineRecords(in: [base]).first)
        #expect(record.availableItemCount == 1)
        #expect(record.restorableItemCount == 1)
        #expect(record.hasRestorableContent)

        try fileManager.removeItem(at: stored)
        let metadataOnly = CleanupService().quarantineRecord(for: session)
        #expect(!metadataOnly.hasRestorableContent)
    }

    @Test func discoveryKeepsSessionWhenBundleIdentifiedApplicationPayloadIsMissing() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let applications = fixture.root.appendingPathComponent("Applications")
        let application = applications.appendingPathComponent("Acrobat.app")
        let infoPlist = application.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(
            at: infoPlist.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": "com.adobe.Acrobat",
                "CFBundlePackageType": "APPL"
            ],
            format: .xml,
            options: 0
        ).write(to: infoPlist)

        let preference = fixture.systemLibrary
            .appendingPathComponent("Preferences/com.adobe.remaining.plist")
        try FileManager.default.createDirectory(
            at: preference.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("remaining".utf8).write(to: preference)

        let items = try fixture.service.validateItemsForQuarantine([
            CleanupItem(
                path: application.path,
                category: .application,
                risk: .medium,
                size: 1,
                reason: "Test",
                bundleIdentifier: "com.adobe.Acrobat",
                scope: .adobeProduct
            ),
            CleanupItem(
                path: preference.path,
                category: .settings,
                risk: .medium,
                size: 9,
                reason: "Test",
                bundleIdentifier: nil,
                scope: .adobeProduct
            )
        ])
        let preferenceItem = try #require(items.first { $0.path == preference.path })
        let storedPreference = fixture.sessionRoot.appendingPathComponent("payload")
            .appendingPathComponent(String(preference.path.dropFirst()))
        try FileManager.default.createDirectory(
            at: storedPreference.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: preference, to: storedPreference)
        try FileManager.default.removeItem(at: application)

        let session = CleanupSession(
            createdAt: Date(),
            quarantinePath: fixture.sessionRoot.path,
            items: items,
            logPath: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(session).write(
            to: fixture.sessionRoot.appendingPathComponent("manifest.json")
        )

        let record = try #require(
            fixture.service.discoverQuarantineRecords(
                in: [fixture.sessionRoot.deletingLastPathComponent()]
            ).first
        )
        #expect(record.availableItemCount == 1)
        #expect(record.hasRestorableContent)
        #expect(record.session.items.count == 2)
        #expect(record.session.items.first { $0.path == application.path }?.sourceIdentity == nil)
        #expect(record.session.items.first { $0.path == preferenceItem.path }?.sourceIdentity != nil)
    }

    @Test func quarantineDiscoveryRejectsManifestPointingOutsideItsTrustedFolder() throws {
        let fileManager = FileManager.default
        let base = try makeTestFixtureRoot("DiscoverySafety")
        defer { try? fileManager.removeItem(at: base) }
        let root = base.appendingPathComponent("session")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let forged = CleanupSession(
            createdAt: Date(),
            quarantinePath: "/Users/Shared/not-an-abesweep-session",
            items: [],
            logPath: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(forged).write(to: root.appendingPathComponent("manifest.json"))

        #expect(CleanupService().discoverQuarantineSessions(in: [base]).isEmpty)
    }

    @Test func manifestRestoreRejectsRelativeTraversalAndOutOfScopePaths() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let unsafePaths = [
            "Library/LaunchDaemons/com.adobe.relative.plist",
            fixture.systemLibrary.path + "/LaunchDaemons/../Preferences/com.adobe.traversal.plist",
            fixture.root.appendingPathComponent("Documents/unrelated.txt").path,
            "/etc/hosts"
        ]

        for path in unsafePaths {
            let session = manifestSession(
                root: fixture.sessionRoot,
                item: CleanupItem(
                    path: path,
                    category: .service,
                    risk: .medium,
                    size: 1,
                    reason: "Forged manifest",
                    bundleIdentifier: nil,
                    scope: .adobeProduct
                )
            )
            #expect(throws: CleanupError.self) {
                try fixture.service.validateRestoreSession(session, requirePayload: false)
            }
        }
    }

    @Test func manifestRestoreRejectsCategoryMismatch() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let item = CleanupItem(
            path: fixture.systemLibrary.appendingPathComponent("LaunchDaemons/com.adobe.valid.plist").path,
            category: .cache,
            risk: .low,
            size: 1,
            reason: "Forged category",
            bundleIdentifier: nil,
            scope: .adobeProduct
        )

        #expect(throws: CleanupError.self) {
            try fixture.service.validateRestoreSession(
                manifestSession(root: fixture.sessionRoot, item: item),
                requirePayload: false
            )
        }
    }

    @Test func manifestRestoreRejectsScopeMismatch() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let item = CleanupItem(
            path: fixture.systemLibrary.appendingPathComponent("LaunchAgents/com.adobe.ccxprocess.plist").path,
            category: .service,
            risk: .medium,
            size: 1,
            reason: "Forged scope",
            bundleIdentifier: nil,
            scope: .adobeProduct
        )

        #expect(throws: CleanupError.self) {
            try fixture.service.validateRestoreSession(
                manifestSession(root: fixture.sessionRoot, item: item),
                requirePayload: false
            )
        }
    }

    @Test func restoreNeverBootstrapsAdobeHelpersOutsideLaunchDirectories() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let item = CleanupItem(
            path: fixture.systemLibrary.appendingPathComponent("PrivilegedHelperTools/com.adobe.helper").path,
            category: .service,
            risk: .medium,
            size: 1,
            reason: "Adobe helper",
            bundleIdentifier: nil,
            scope: .adobeProduct
        )

        let command = try fixture.service.buildRestoreCommand(
            session: manifestSession(root: fixture.sessionRoot, item: item),
            uid: 501
        )
        #expect(!command.contains("launchctl bootstrap"))
    }

    @Test func scanThenReplaceIsRejectedBeforeQuarantine() async throws {
        let fileManager = FileManager.default
        let home = try makeTestFixtureRoot("Replace")
        defer { try? fileManager.removeItem(at: home) }
        let source = home.appendingPathComponent("Library/Caches/com.adobe.swap")
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        let scanned = try #require(await AdobeScanner(
            fileManager: FileManager(),
            home: home,
            systemLibrary: home.appendingPathComponent("SystemLibrary"),
            applicationRoots: [home.appendingPathComponent("Applications")]
        ).scan().first { $0.path == source.path })

        try fileManager.moveItem(at: source, to: source.appendingPathExtension("original"))
        try Data("replacement".utf8).write(to: source)
        let service = CleanupService(
            home: home,
            systemLibrary: home.appendingPathComponent("SystemLibrary"),
            applicationRoots: [home.appendingPathComponent("Applications")]
        )

        #expect(throws: CleanupError.self) {
            try service.validateItemsForQuarantine([scanned])
        }
    }

    @Test func privilegedQuarantineRejectsPayloadDirectoryReplacedBySymlink() throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("PayloadSwap")
        defer { try? fileManager.removeItem(at: testRoot) }
        let source = testRoot.appendingPathComponent("Library/Caches/Adobe/CCXProcess")
        let destination = testRoot.appendingPathComponent("Quarantine/session")
        let manifest = testRoot.appendingPathComponent("manifest.json")
        let external = testRoot.appendingPathComponent("external")
        try fileManager.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: source)
        try prepareQuarantineLayout(destination: destination, manifest: manifest)
        let service = CleanupService(
            home: testRoot,
            systemLibrary: testRoot.appendingPathComponent("SystemLibrary"),
            quarantineBaseURLs: [testRoot.appendingPathComponent("Quarantine")]
        )
        let item = try #require(service.validateItemsForQuarantine([CleanupItem(
            path: source.path,
            category: .cache,
            risk: .low,
            size: 6,
            reason: "Test",
            bundleIdentifier: nil,
            scope: .creativeCloudInfrastructure
        )]).first)
        let command = try service.buildQuarantineCommand(
            items: [item],
            destination: destination,
            manifest: manifest,
            uid: getuid(),
            gid: getgid()
        )

        let payload = destination.appendingPathComponent("payload")
        try fileManager.removeItem(at: payload)
        try fileManager.createSymbolicLink(at: payload, withDestinationURL: external)

        #expect(try runShell(command) == 45)
        #expect(fileManager.fileExists(atPath: source.path))
        #expect((try fileManager.contentsOfDirectory(atPath: external.path)).isEmpty)
    }

    @Test func privilegedQuarantineRejectsSessionDirectoryReplacedBySymlink() throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("SessionSwap")
        defer { try? fileManager.removeItem(at: testRoot) }
        let source = testRoot.appendingPathComponent("Library/Caches/Adobe/CCXProcess")
        let destination = testRoot.appendingPathComponent("Quarantine/session")
        let displaced = testRoot.appendingPathComponent("displaced-session")
        let manifest = testRoot.appendingPathComponent("manifest.json")
        let external = testRoot.appendingPathComponent("external")
        try fileManager.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: source)
        try prepareQuarantineLayout(destination: destination, manifest: manifest)
        let service = CleanupService(
            home: testRoot,
            systemLibrary: testRoot.appendingPathComponent("SystemLibrary"),
            quarantineBaseURLs: [testRoot.appendingPathComponent("Quarantine")]
        )
        let item = try #require(service.validateItemsForQuarantine([CleanupItem(
            path: source.path,
            category: .cache,
            risk: .low,
            size: 6,
            reason: "Test",
            bundleIdentifier: nil,
            scope: .creativeCloudInfrastructure
        )]).first)
        let command = try service.buildQuarantineCommand(
            items: [item],
            destination: destination,
            manifest: manifest,
            uid: getuid(),
            gid: getgid()
        )

        try fileManager.moveItem(at: destination, to: displaced)
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: external)

        #expect(try runShell(command) == 45)
        #expect(fileManager.fileExists(atPath: source.path))
        #expect((try fileManager.contentsOfDirectory(atPath: external.path)).isEmpty)
    }

    @Test func hostsBackupReplacementIsRejectedAtPointOfUseValidation() throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("HostsSwap")
        defer { try? fileManager.removeItem(at: testRoot) }
        let backup = testRoot.appendingPathComponent("session/hosts/original")
        let displaced = testRoot.appendingPathComponent("original-displaced")
        let plan = try #require(HostsFileService().plan(content: "0.0.0.0 activate.adobe.com\n"))
        try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(plan.originalContent.utf8).write(to: backup)
        let identity = try fileIdentity(at: backup)
        let service = CleanupService(home: testRoot)
        try service.validateHostsBackup(
            at: backup,
            expectedIdentity: identity,
            expectedSHA256: plan.originalSHA256
        )

        try fileManager.moveItem(at: backup, to: displaced)
        try Data(plan.originalContent.utf8).write(to: backup)

        #expect(throws: CleanupError.self) {
            try service.validateHostsBackup(
                at: backup,
                expectedIdentity: identity,
                expectedSHA256: plan.originalSHA256
            )
        }
    }

    @Test func permanentDeleteRejectsPathsOutsideAbeSweepQuarantine() {
        let unsafePaths = [
            "/Users/Shared/AbeSweep Quarantine",
            CleanupService().quarantineBaseURL.path,
            "/Users/example/Documents",
            "/"
        ]

        for path in unsafePaths {
            let session = CleanupSession(
                createdAt: Date(),
                quarantinePath: path,
                items: [],
                logPath: nil
            )
            #expect(throws: CleanupError.self) {
                try CleanupService().buildPermanentDeleteCommand(session: session)
            }
        }
    }

    @Test func quarantineAndRestoreRoundTrip() throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("RoundTrip")
        defer { try? fileManager.removeItem(at: testRoot) }
        let source = testRoot.appendingPathComponent("Library/Caches/Adobe/CoreSync")
        let sourceFile = source.appendingPathComponent("test.dat")
        let quarantineBase = testRoot.appendingPathComponent("Quarantine")
        let quarantine = quarantineBase.appendingPathComponent("session")
        let manifest = testRoot.appendingPathComponent("source-manifest.json")
        let runDirectory = testRoot.appendingPathComponent("run")
        let log = testRoot.appendingPathComponent("operation.log")
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try Data("sample".utf8).write(to: sourceFile)
        try Data("{}".utf8).write(to: manifest)
        try Data().write(to: log)
        let context = CleanupRunContext(
            directory: runDirectory,
            statusURL: runDirectory.appendingPathComponent("status.json"),
            cancelURL: runDirectory.appendingPathComponent("cancel"),
            logURL: log
        )

        let unvalidatedItem = CleanupItem(
            path: source.path,
            category: .cache,
            risk: .low,
            size: 6,
            reason: "Test",
            bundleIdentifier: nil,
            scope: .creativeCloudInfrastructure
        )
        let service = CleanupService(home: testRoot, quarantineBaseURLs: [quarantineBase])
        let item = try #require(service.validateItemsForQuarantine([unvalidatedItem]).first)
        try prepareQuarantineLayout(destination: quarantine, manifest: manifest)
        let quarantineCommand = try service.buildQuarantineCommand(
            items: [item],
            destination: quarantine,
            manifest: manifest,
            uid: getuid(),
            gid: getgid(),
            context: context
        )
        #expect(try runShell(quarantineCommand) == 0)
        #expect(!fileManager.fileExists(atPath: item.path))
        let progressData = try Data(contentsOf: context.statusURL)
        let progress = try JSONDecoder().decode(CleanupProgressState.self, from: progressData)
        #expect(progress.stage == "finished")
        #expect(progress.completed == 1)
        #expect(try String(contentsOf: log, encoding: .utf8).contains(L10n.text("SIKERES", "SUCCESS")))

        let session = CleanupSession(
            createdAt: Date(),
            quarantinePath: quarantine.path,
            items: [item],
            logPath: nil
        )
        #expect(try runShell(service.buildRestoreCommand(session: session, uid: getuid())) == 0)
        #expect(fileManager.fileExists(atPath: sourceFile.path))
    }

    @Test func quarantinePreflightRejectsDifferentVolumeBeforeMove() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.systemLibrary
            .appendingPathComponent("Preferences/com.adobe.cross-volume.plist")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("original".utf8).write(to: source)
        let validated = try #require(fixture.service.validateItemsForQuarantine([
            CleanupItem(
                path: source.path,
                category: .settings,
                risk: .medium,
                size: 8,
                reason: "Test",
                bundleIdentifier: nil,
                scope: .adobeProduct
            )
        ]).first)
        let sourceIdentity = try #require(validated.sourceIdentity)
        let mismatched = CleanupItem(
            path: validated.path,
            category: validated.category,
            risk: validated.risk,
            size: validated.size,
            reason: validated.reason,
            bundleIdentifier: validated.bundleIdentifier,
            scope: validated.scope,
            sourceIdentity: FileIdentity(
                device: sourceIdentity.device == UInt64.max ? 0 : sourceIdentity.device + 1,
                inode: sourceIdentity.inode
            )
        )

        #expect(throws: CleanupError.self) {
            try fixture.service.validateSameVolumeMoves(
                [mismatched],
                quarantineIdentity: try fileIdentity(at: fixture.sessionRoot)
            )
        }
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
        #expect(try FileManager.default.contentsOfDirectory(
            at: fixture.sessionRoot.appendingPathComponent("payload"),
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test func restorePreflightRejectsDifferentDestinationVolumeBeforeMove() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let destination = fixture.systemLibrary
            .appendingPathComponent("Preferences/com.adobe.cross-volume.plist")
        let stored = fixture.sessionRoot.appendingPathComponent("payload")
            .appendingPathComponent(String(destination.path.dropFirst()))
        try FileManager.default.createDirectory(
            at: stored.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stored".utf8).write(to: stored)
        let storedIdentity = try fileIdentity(at: stored)
        let actualDestinationParentIdentity = try #require(AdobePathPolicy(
            home: fixture.root,
            systemLibrary: fixture.systemLibrary,
            applicationRoots: [fixture.root.appendingPathComponent("Applications")]
        ).nearestExistingParentIdentity(for: destination.path))
        let expectedDestinationParentIdentity = try fileIdentity(at: fixture.root)
        #expect(actualDestinationParentIdentity == expectedDestinationParentIdentity)
        let mismatchedDestinationParentIdentity = FileIdentity(
            device: storedIdentity.device == UInt64.max ? 0 : storedIdentity.device + 1,
            inode: actualDestinationParentIdentity.inode
        )

        #expect(throws: CleanupError.self) {
            try fixture.service.validateSameVolumeMove(
                sourceIdentity: storedIdentity,
                destinationIdentity: mismatchedDestinationParentIdentity,
                path: destination.path
            )
        }
        #expect(try String(contentsOf: stored, encoding: .utf8) == "stored")
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func restoreIgnoresExistingDestinationWhenItsQuarantineSourceIsAlreadyGone() throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("PartialRestore")
        defer { try? fileManager.removeItem(at: testRoot) }
        let quarantineBase = testRoot.appendingPathComponent("Quarantine")
        let quarantine = quarantineBase.appendingPathComponent("session")
        let alreadyRestored = testRoot.appendingPathComponent("Library/Preferences/Adobe Already Restored")
        let stillQuarantined = testRoot.appendingPathComponent("Library/Preferences/Adobe Still Quarantined")
        let stored = quarantine
            .appendingPathComponent("payload")
            .appendingPathComponent(stillQuarantined.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        try fileManager.createDirectory(at: alreadyRestored.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: alreadyRestored)
        try fileManager.createDirectory(at: stored.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stored".utf8).write(to: stored)

        let items = [alreadyRestored, stillQuarantined].map {
            CleanupItem(
                path: $0.path,
                category: .settings,
                risk: .high,
                size: 1,
                reason: "Test",
                bundleIdentifier: nil,
                scope: .adobeProduct
            )
        }
        let session = CleanupSession(
            createdAt: Date(),
            quarantinePath: quarantine.path,
            items: items,
            logPath: nil
        )

        let service = CleanupService(home: testRoot, quarantineBaseURLs: [quarantineBase])
        #expect(try runShell(service.buildRestoreCommand(session: session, uid: getuid())) == 0)
        #expect(try String(contentsOf: alreadyRestored, encoding: .utf8) == "existing")
        #expect(try String(contentsOf: stillQuarantined, encoding: .utf8) == "stored")
    }

    @Test func cancellationIsReportedWithoutMovingSource() throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("Cancel")
        defer { try? fileManager.removeItem(at: testRoot) }
        let source = testRoot.appendingPathComponent("Library/Caches/com.adobe.cancel")
        let quarantine = testRoot.appendingPathComponent("Quarantine")
        let manifest = testRoot.appendingPathComponent("manifest.json")
        let runDirectory = testRoot.appendingPathComponent("run")
        let log = testRoot.appendingPathComponent("operation.log")
        try fileManager.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try Data("sample".utf8).write(to: source)
        try Data("{}".utf8).write(to: manifest)
        try Data().write(to: log)

        let context = CleanupRunContext(
            directory: runDirectory,
            statusURL: runDirectory.appendingPathComponent("status.json"),
            cancelURL: runDirectory.appendingPathComponent("cancel"),
            logURL: log
        )
        try Data().write(to: context.cancelURL)
        let unvalidatedItem = CleanupItem(
            path: source.path,
            category: .cache,
            risk: .low,
            size: 6,
            reason: "Test",
            bundleIdentifier: nil,
            scope: .adobeProduct
        )
        let service = CleanupService(home: testRoot)
        let item = try #require(service.validateItemsForQuarantine([unvalidatedItem]).first)
        try prepareQuarantineLayout(destination: quarantine, manifest: manifest)
        let command = try service.buildQuarantineCommand(
            items: [item],
            destination: quarantine,
            manifest: manifest,
            uid: getuid(),
            gid: getgid(),
            context: context
        )

        #expect(try runShell(command) == 130)
        #expect(fileManager.fileExists(atPath: source.path))
        let progress = try JSONDecoder().decode(
            CleanupProgressState.self,
            from: Data(contentsOf: context.statusURL)
        )
        #expect(progress.stage == "cancelled")
        #expect(try String(contentsOf: log, encoding: .utf8).contains(L10n.text("MEGSZAKÍTVA", "CANCELLED")))
    }

    @Test func rollbackFailureTakesPrecedenceOverCancellation() {
        let error = CleanupService.administratorError(
            message: "ABESWEEP_OPERATION_CANCELLED\nABESWEEP_ROLLBACK_FAILED (52)"
        )
        guard case .commandFailed = error else {
            Issue.record("Incomplete rollback was incorrectly reported as cancellation")
            return
        }
        guard case .authorizationCancelled = CleanupService.administratorError(message: "User canceled. (-128)") else {
            Issue.record("Authorization cancellation was not recognized")
            return
        }
        guard case .commandFailed = CleanupService.administratorError(message: "Could not move /cache/cancelled-file") else {
            Issue.record("A path containing cancel must not be treated as authorization cancellation")
            return
        }
    }

    @Test func permanentDeleteRejectsReplacedRootAfterCommandPreparation() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = CleanupSession(createdAt: Date(), quarantinePath: fixture.sessionRoot.path, items: [], logPath: nil)
        let command = try fixture.service.buildPermanentDeleteCommand(session: session)
        let saved = fixture.root.appendingPathComponent("saved")
        try FileManager.default.moveItem(at: fixture.sessionRoot, to: saved)
        try FileManager.default.createDirectory(at: fixture.sessionRoot, withIntermediateDirectories: false)
        let unrelated = fixture.sessionRoot.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        #expect(try runShell(command) == 43)
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
    }

    @Test func permanentDeleteRejectsSymlinkedAncestorAfterPreparation() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = CleanupSession(createdAt: Date(), quarantinePath: fixture.sessionRoot.path, items: [], logPath: nil)
        let command = try fixture.service.buildPermanentDeleteCommand(session: session)
        let base = fixture.sessionRoot.deletingLastPathComponent()
        let savedBase = fixture.root.appendingPathComponent("saved-base")
        try FileManager.default.moveItem(at: base, to: savedBase)
        try FileManager.default.createSymbolicLink(at: base, withDestinationURL: savedBase)
        #expect(throws: CleanupError.self) { try fixture.service.buildPermanentDeleteCommand(session: session) }
        #expect(try runShell(command) == 43)
        #expect(FileManager.default.fileExists(atPath: savedBase.appendingPathComponent("session").path))
    }

    @Test func missingHostsBackupDoesNotBlockRemainingPayload() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let item = CleanupItem(
            path: fixture.systemLibrary.appendingPathComponent("Preferences/com.adobe.example.plist").path,
            category: .settings, risk: .medium, size: 1, reason: "Test",
            bundleIdentifier: nil, scope: .adobeProduct
        )
        let stored = fixture.sessionRoot.appendingPathComponent("payload")
            .appendingPathComponent(String(item.path.dropFirst()))
        try FileManager.default.createDirectory(at: stored.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("settings".utf8).write(to: stored)
        let plan = try #require(HostsFileService().plan(content: "0.0.0.0 activate.adobe.com\n"))
        let session = CleanupSession(
            createdAt: Date(), quarantinePath: fixture.sessionRoot.path,
            items: [item], logPath: nil, hostsCleanup: plan.record
        )
        let validated = try fixture.service.validateRestoreSession(session)
        #expect(validated.items.count == 1)
        #expect(validated.hostsCleanup == nil)
        #expect(try runShell(fixture.service.buildRestoreCommand(session: validated, uid: getuid())) == 0)
        #expect(try String(contentsOfFile: item.path, encoding: .utf8) == "settings")
    }

    @Test func failedQuarantineRollbackPreservesNewDestination() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.systemLibrary.appendingPathComponent("Preferences/com.adobe.example.plist")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: source)
        let item = try #require(fixture.service.validateItemsForQuarantine([CleanupItem(
            path: source.path, category: .settings, risk: .medium, size: 8, reason: "Test",
            bundleIdentifier: nil, scope: .adobeProduct
        )]).first)
        let manifest = fixture.root.appendingPathComponent("manifest.json")
        try prepareQuarantineLayout(destination: fixture.sessionRoot, manifest: manifest)
        let command = try fixture.service.buildQuarantineCommand(
            items: [item], destination: fixture.sessionRoot, manifest: manifest, uid: getuid(), gid: getgid()
        ).replacingOccurrences(
            of: "moved_0=1;",
            with: "moved_0=1; /usr/bin/printf newer > \(fixture.service.shellQuote(source.path)); exit 1;"
        )
        #expect(try runShell(command) == 52)
        #expect(try String(contentsOf: source, encoding: .utf8) == "newer")
        let stored = fixture.sessionRoot.appendingPathComponent("payload").appendingPathComponent(String(source.path.dropFirst()))
        #expect(try String(contentsOf: stored, encoding: .utf8) == "original")
    }

    @Test func restoreRefusesDirectoryCreatedAfterPreflight() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.systemLibrary.appendingPathComponent("Preferences/com.adobe.example.plist")
        let stored = fixture.sessionRoot.appendingPathComponent("payload").appendingPathComponent(String(source.path.dropFirst()))
        try FileManager.default.createDirectory(at: stored.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: stored)
        let item = CleanupItem(path: source.path, category: .settings, risk: .medium, size: 8, reason: "Test", bundleIdentifier: nil, scope: .adobeProduct)
        let session = manifestSession(root: fixture.sessionRoot, item: item)
        let move = "move_without_replacing \(fixture.service.shellQuote(stored.path)) \(fixture.service.shellQuote(source.path))"
        let command = try fixture.service.buildRestoreCommand(session: session, uid: getuid())
            .replacingOccurrences(of: move, with: "mkdir -p \(fixture.service.shellQuote(source.path)); " + move)
        #expect(try runShell(command) != 0)
        #expect(try String(contentsOf: stored, encoding: .utf8) == "original")
        #expect(try FileManager.default.contentsOfDirectory(atPath: source.path).isEmpty)
    }

    @Test func commitReportingFailureDoesNotUndoQuarantine() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.systemLibrary.appendingPathComponent("Preferences/com.adobe.example.plist")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: source)
        let item = try #require(fixture.service.validateItemsForQuarantine([CleanupItem(
            path: source.path, category: .settings, risk: .medium, size: 8, reason: "Test", bundleIdentifier: nil, scope: .adobeProduct
        )]).first)
        let manifest = fixture.root.appendingPathComponent("manifest.json")
        let run = fixture.root.appendingPathComponent("run")
        let context = CleanupRunContext(directory: run, statusURL: run.appendingPathComponent("status.json"), cancelURL: run.appendingPathComponent("cancel"), logURL: fixture.root.appendingPathComponent("run.log"))
        try prepareQuarantineLayout(destination: fixture.sessionRoot, manifest: manifest, context: context)
        let command = try fixture.service.buildQuarantineCommand(
            items: [item], destination: fixture.sessionRoot, manifest: manifest, uid: getuid(), gid: getgid(), context: context
        ).replacingOccurrences(
            of: "chown \(getuid()):\(getgid()) \(fixture.service.shellQuote(fixture.sessionRoot.path))",
            with: "append_log() { return 1; }; write_progress() { return 1; }"
        )
        #expect(try runShell(command) == 0)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        let stored = fixture.sessionRoot.appendingPathComponent("payload").appendingPathComponent(String(source.path.dropFirst()))
        #expect(try String(contentsOf: stored, encoding: .utf8) == "original")
    }

    @Test func quarantinePreservesUnselectedParentDirectoryIdentityAndMode() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let parent = fixture.systemLibrary.appendingPathComponent("Application Support/Adobe")
        let source = parent.appendingPathComponent("Component")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        let parentIdentity = try fileIdentity(at: parent)
        try Data("original".utf8).write(to: source)
        let item = try #require(fixture.service.validateItemsForQuarantine([CleanupItem(
            path: source.path, category: .sharedComponent, risk: .high, size: 8, reason: "Test", bundleIdentifier: nil, scope: .adobeProduct
        )]).first)
        let manifest = fixture.root.appendingPathComponent("manifest.json")
        try prepareQuarantineLayout(destination: fixture.sessionRoot, manifest: manifest)
        let command = try fixture.service.buildQuarantineCommand(
            items: [item], destination: fixture.sessionRoot, manifest: manifest, uid: getuid(), gid: getgid()
        )
        #expect(try runShell(command) == 0)
        #expect(try fileIdentity(at: parent) == parentIdentity)
        #expect(try FileManager.default.attributesOfItem(atPath: parent.path)[.posixPermissions] as? Int == 0o700)
    }

    @Test func manifestLogCannotPointOutsideApplicationLogsOrThroughSymlinks() throws {
        let fixture = try makeManifestFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sensitive = fixture.root.appendingPathComponent("user-document.txt")
        try Data("keep".utf8).write(to: sensitive)
        let logs = fixture.root.appendingPathComponent("Home/Library/Logs/AbeSweep")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let valid = logs.appendingPathComponent("AbeSweep-test.log")
        try Data("log".utf8).write(to: valid)
        #expect(fixture.service.validatedLogURL(valid.path) == valid)
        #expect(fixture.service.validatedLogURL(sensitive.path) == nil)
        let session = CleanupSession(createdAt: Date(), quarantinePath: fixture.sessionRoot.path, items: [], logPath: sensitive.path)
        #expect(try fixture.service.validateRestoreSession(session).logPath == nil)
        try FileManager.default.removeItem(at: valid)
        try FileManager.default.createSymbolicLink(at: valid, withDestinationURL: sensitive)
        #expect(fixture.service.validatedLogURL(valid.path) == nil)
        #expect(try String(contentsOf: sensitive, encoding: .utf8) == "keep")
    }

    private func runShell(_ command: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func prepareQuarantineLayout(
        destination: URL,
        manifest: URL,
        context: CleanupRunContext? = nil,
        needsHostsDirectory: Bool = false
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.appendingPathComponent("payload", isDirectory: true),
            withIntermediateDirectories: true
        )
        if needsHostsDirectory {
            try fileManager.createDirectory(
                at: destination.appendingPathComponent("hosts", isDirectory: true),
                withIntermediateDirectories: false
            )
        }
        if !fileManager.fileExists(atPath: manifest.path) {
            try fileManager.createDirectory(
                at: manifest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("{}".utf8).write(to: manifest)
        }
        try fileManager.copyItem(
            at: manifest,
            to: destination.appendingPathComponent("manifest.json")
        )
        if let context {
            try fileManager.createDirectory(at: context.directory, withIntermediateDirectories: true)
            try Data().write(to: context.logURL)
        }
    }

    private func makeLaunchServiceFixture(teamIdentifier: String) throws -> (
        root: URL,
        plist: URL,
        executable: URL,
        sessionRoot: URL,
        manifest: URL,
        service: CleanupService
    ) {
        let fileManager = FileManager.default
        let root = try makeTestFixtureRoot("LaunchService")
        let home = root.appendingPathComponent("Home")
        let systemLibrary = root.appendingPathComponent("Library")
        let plist = systemLibrary.appendingPathComponent("LaunchDaemons/com.adobe.ccxprocess.plist")
        let executable = systemLibrary.appendingPathComponent("Application Support/Adobe/CCXProcess")
        let quarantineBase = root.appendingPathComponent("Quarantine")
        let sessionRoot = quarantineBase.appendingPathComponent("session")
        let manifest = root.appendingPathComponent("manifest.json")
        try fileManager.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("executable".utf8).write(to: executable)
        let plistObject: [String: Any] = [
            "Label": "com.adobe.ccxprocess",
            "Program": executable.path,
            "ProgramArguments": [executable.path, "--background"]
        ]
        try PropertyListSerialization.data(
            fromPropertyList: plistObject,
            format: .xml,
            options: 0
        ).write(to: plist)
        try prepareQuarantineLayout(destination: sessionRoot, manifest: manifest)
        let service = CleanupService(
            home: home,
            systemLibrary: systemLibrary,
            applicationRoots: [root.appendingPathComponent("Applications")],
            quarantineBaseURLs: [quarantineBase],
            teamIdentifierProvider: { path in
                path == executable.path ? teamIdentifier : nil
            }
        )
        return (root, plist, executable, sessionRoot, manifest, service)
    }

    private func fileIdentity(at url: URL) throws -> FileIdentity {
        var information = stat()
        let result = url.path.withCString { Darwin.lstat($0, &information) }
        guard result == 0 else { throw CleanupError.sourceChanged(url.path) }
        return FileIdentity(device: UInt64(information.st_dev), inode: UInt64(information.st_ino))
    }

    private func makeManifestFixture() throws -> (
        root: URL,
        systemLibrary: URL,
        sessionRoot: URL,
        service: CleanupService
    ) {
        let fileManager = FileManager.default
        let root = try makeTestFixtureRoot("Manifest")
        let home = root.appendingPathComponent("Home")
        let systemLibrary = root.appendingPathComponent("Library")
        let quarantineBase = root.appendingPathComponent("Quarantine")
        let sessionRoot = quarantineBase.appendingPathComponent("session")
        try fileManager.createDirectory(
            at: sessionRoot.appendingPathComponent("payload"),
            withIntermediateDirectories: true
        )
        return (
            root,
            systemLibrary,
            sessionRoot,
            CleanupService(
                home: home,
                systemLibrary: systemLibrary,
                applicationRoots: [root.appendingPathComponent("Applications")],
                quarantineBaseURLs: [quarantineBase]
            )
        )
    }

    private func manifestSession(root: URL, item: CleanupItem) -> CleanupSession {
        CleanupSession(
            createdAt: Date(),
            quarantinePath: root.path,
            items: [item],
            logPath: nil
        )
    }
}
