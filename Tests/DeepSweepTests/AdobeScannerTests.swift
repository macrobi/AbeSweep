import Foundation
import Testing
@testable import AbeSweep

struct AdobeScannerTests {
    @Test func wholeCoreSyncDirectoryCannotBeQuarantined() throws {
        let root = try makeTestFixtureRoot("CoreSync")
        defer { try? FileManager.default.removeItem(at: root) }
        let coreSync = root.appendingPathComponent("Library/Application Support/Adobe/CoreSync")
        try FileManager.default.createDirectory(at: coreSync.appendingPathComponent("cloudnative"), withIntermediateDirectories: true)
        let item = CleanupItem(path: coreSync.path, category: .userData, risk: .medium, size: 0, reason: "Test", bundleIdentifier: nil, scope: .creativeCloudInfrastructure)
        let policy = AdobePathPolicy(home: root)
        #expect(policy.secureScannedItem(item) == nil)
        #expect(throws: CleanupError.self) { try policy.validatedItemForQuarantine(item) }
        #expect(!policy.isAbsoluteNormalizedPath(coreSync.path + "\0suffix"))
    }

    @Test func productPreferencesAndAdobeDeviceStateAreDetectedNarrowly() async throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("Preferences")
        defer { try? fileManager.removeItem(at: testRoot) }

        let preferences = testRoot.appendingPathComponent("Library/Preferences")
        let photoshop = preferences.appendingPathComponent("Adobe Photoshop 2026 Settings")
        let indesign = preferences.appendingPathComponent("Adobe InDesign")
        let adobePlist = preferences.appendingPathComponent("com.adobe.Photoshop.plist")
        let adobeDeviceState = preferences.appendingPathComponent("Adobe/Device State")
        let creativeCloud = preferences.appendingPathComponent("Adobe Creative Cloud")
        let unrelatedDeviceState = preferences.appendingPathComponent("Other Vendor/Device State")
        let genericDeviceState = preferences.appendingPathComponent("Device State")
        let misleading = preferences.appendingPathComponent("Not Adobe Settings")
        let document = testRoot.appendingPathComponent("Documents/design.psd")

        for directory in [photoshop, indesign, adobeDeviceState, creativeCloud, unrelatedDeviceState, genericDeviceState, misleading] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("plist".utf8).write(to: adobePlist)
        try fileManager.createDirectory(at: document.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("work".utf8).write(to: document)

        let results = await AdobeScanner(
            fileManager: FileManager(),
            home: testRoot,
            systemLibrary: testRoot.appendingPathComponent("SystemLibrary"),
            applicationRoots: [testRoot.appendingPathComponent("Applications")]
        ).scan()
        let resultByPath = Dictionary(uniqueKeysWithValues: results.map {
            ($0.url.resolvingSymlinksInPath().path, $0)
        })

        for expected in [photoshop, indesign, adobePlist, adobeDeviceState, creativeCloud] {
            #expect(resultByPath[expected.resolvingSymlinksInPath().path] != nil)
        }
        #expect(resultByPath[adobeDeviceState.resolvingSymlinksInPath().path]?.category == .settings)
        #expect(resultByPath[adobeDeviceState.resolvingSymlinksInPath().path]?.risk == .high)
        #expect(resultByPath[photoshop.resolvingSymlinksInPath().path]?.scope == .adobeProduct)
        #expect(resultByPath[indesign.resolvingSymlinksInPath().path]?.scope == .adobeProduct)
        #expect(resultByPath[creativeCloud.resolvingSymlinksInPath().path]?.scope == .creativeCloudInfrastructure)
        #expect(resultByPath[unrelatedDeviceState.resolvingSymlinksInPath().path] == nil)
        #expect(resultByPath[genericDeviceState.resolvingSymlinksInPath().path] == nil)
        #expect(resultByPath[misleading.resolvingSymlinksInPath().path] == nil)
        #expect(resultByPath[document.resolvingSymlinksInPath().path] == nil)
    }

    @Test func deviceStateNameMatchingDoesNotAcceptSimilarNames() {
        #expect(AdobeScanner.isDeviceStateName("Device State"))
        #expect(AdobeScanner.isDeviceStateName("DeviceState"))
        #expect(AdobeScanner.isDeviceStateName("device_state"))
        #expect(!AdobeScanner.isDeviceStateName("Device State Backup"))
        #expect(!AdobeScanner.isDeviceStateName("MyDeviceState"))
    }

    @Test func detectedAdobePreferenceCanBeQuarantinedAndRestored() async throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("PreferenceRoundTrip")
        defer { try? fileManager.removeItem(at: testRoot) }

        let preference = testRoot.appendingPathComponent("Library/Preferences/Adobe InDesign")
        let settings = preference.appendingPathComponent("Version 21.0/en_US/InDesign Defaults")
        try fileManager.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("settings".utf8).write(to: settings)

        let expectedPreferencePath = preference.resolvingSymlinksInPath().path
        let item = try #require(await AdobeScanner(
            fileManager: FileManager(),
            home: testRoot,
            systemLibrary: testRoot.appendingPathComponent("SystemLibrary"),
            applicationRoots: [testRoot.appendingPathComponent("Applications")]
        ).scan().first { $0.url.resolvingSymlinksInPath().path == expectedPreferencePath })

        let quarantine = testRoot.appendingPathComponent("Quarantine/session")
        let sourceManifest = testRoot.appendingPathComponent("source-manifest.json")
        try Data("{}".utf8).write(to: sourceManifest)
        let service = CleanupService(
            home: testRoot,
            systemLibrary: testRoot.appendingPathComponent("SystemLibrary"),
            applicationRoots: [testRoot.appendingPathComponent("Applications")],
            quarantineBaseURLs: [testRoot.appendingPathComponent("Quarantine")]
        )
        try fileManager.createDirectory(
            at: quarantine.appendingPathComponent("payload"),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(
            at: sourceManifest,
            to: quarantine.appendingPathComponent("manifest.json")
        )
        let quarantineCommand = try service.buildQuarantineCommand(
            items: [item],
            destination: quarantine,
            manifest: sourceManifest,
            uid: getuid(),
            gid: getgid()
        )

        #expect(try runShell(quarantineCommand) == 0)
        #expect(!fileManager.fileExists(atPath: preference.path))

        let session = CleanupSession(
            createdAt: Date(),
            quarantinePath: quarantine.path,
            items: [item],
            logPath: nil
        )
        #expect(try runShell(service.buildRestoreCommand(session: session, uid: getuid())) == 0)
        #expect(fileManager.fileExists(atPath: settings.path))
    }

    @Test func adobeItemsInApplicationsUtilitiesAreDetectedWithoutTouchingOtherUtilities() async throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("Utilities")
        defer { try? fileManager.removeItem(at: testRoot) }

        let applications = testRoot.appendingPathComponent("Applications")
        let utilities = applications.appendingPathComponent("Utilities")
        let adobeInstallers = utilities.appendingPathComponent("Adobe Installers")
        let adobeGenuine = utilities.appendingPathComponent("Adobe Genuine Service")
        let adobeApp = utilities.appendingPathComponent("Adobe AIR Uninstaller.app")
        let unrelated = utilities.appendingPathComponent("Disk Utility.app")
        let misleading = utilities.appendingPathComponent("Not Adobe Utilities")
        let misleadingApplication = applications.appendingPathComponent("Not Adobe Helper.app")
        for directory in [adobeInstallers, adobeGenuine, adobeApp, unrelated, misleading, misleadingApplication] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let results = await AdobeScanner(
            fileManager: FileManager(),
            home: testRoot.appendingPathComponent("Home"),
            systemLibrary: testRoot.appendingPathComponent("Library"),
            applicationRoots: [applications]
        ).scan()
        let paths = Set(results.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path })

        #expect(paths.contains(adobeInstallers.resolvingSymlinksInPath().path))
        #expect(paths.contains(adobeGenuine.resolvingSymlinksInPath().path))
        #expect(paths.contains(adobeApp.resolvingSymlinksInPath().path))
        #expect(!paths.contains(unrelated.resolvingSymlinksInPath().path))
        #expect(!paths.contains(misleading.resolvingSymlinksInPath().path))
        #expect(!paths.contains(misleadingApplication.resolvingSymlinksInPath().path))
    }

    @Test func teamPrefixedAdobeGroupContainersAndApplicationScriptsAreDetected() async throws {
        let fileManager = FileManager.default
        let testHome = try makeTestFixtureRoot("AdobeGroups")
        defer { try? fileManager.removeItem(at: testHome) }

        let groupContainers = testHome.appendingPathComponent("Library/Group Containers")
        let applicationScripts = testHome.appendingPathComponent("Library/Application Scripts")
        let expected = [
            groupContainers.appendingPathComponent("Adobe-Hub-App"),
            groupContainers.appendingPathComponent("JQ525L2MZD.com.adobe.NGL"),
            groupContainers.appendingPathComponent("JQ525L2MZD.com.adobe.GrowthSDK"),
            groupContainers.appendingPathComponent("com.adobe.accmac.explinder"),
            applicationScripts.appendingPathComponent("JQ525L2MZD.com.adobe.CreativeCloudDesktop")
        ]
        let unrelated = groupContainers.appendingPathComponent("TEAMID.com.example.Editor")
        for directory in expected + [unrelated] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let results = await AdobeScanner(
            fileManager: FileManager(),
            home: testHome,
            systemLibrary: testHome.appendingPathComponent("SystemLibrary"),
            applicationRoots: [testHome.appendingPathComponent("Applications")]
        ).scan()
        let byPath = Dictionary(uniqueKeysWithValues: results.map {
            ($0.url.resolvingSymlinksInPath().path, $0)
        })

        for path in expected {
            let resolvedPath = path.resolvingSymlinksInPath().path
            #expect(byPath[resolvedPath] != nil)
            #expect(byPath[resolvedPath]?.scope == .creativeCloudInfrastructure)
        }
        #expect(byPath[unrelated.resolvingSymlinksInPath().path] == nil)
    }

    @Test func creativeCloudStateIsSeparatedFromProtectedSyncContent() async throws {
        let fileManager = FileManager.default
        let testHome = try makeTestFixtureRoot("Scanner")
        defer { try? fileManager.removeItem(at: testHome) }

        let adobeSupport = testHome.appendingPathComponent("Library/Application Support/Adobe")
        let oobe = adobeSupport.appendingPathComponent("OOBE/opm.db")
        let coreState = adobeSupport.appendingPathComponent("CoreSync/settings.db")
        let cloudNative = adobeSupport.appendingPathComponent("CoreSync/cloudnative/unsynced.dat")
        for file in [oobe, coreState, cloudNative] {
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("test".utf8).write(to: file)
        }

        let allResults = await AdobeScanner(fileManager: FileManager(), home: testHome).scan()
        let results = allResults.filter { $0.path.contains(testHome.lastPathComponent) }

        let oobeItem = try #require(results.first { $0.path.contains("/OOBE") })
        let coreStateItem = try #require(results.first { $0.path.hasSuffix("settings.db") })
        let protectedItem = try #require(results.first { $0.path.contains("/cloudnative") })
        #expect(oobeItem.scope == .creativeCloudInfrastructure)
        #expect(coreStateItem.scope == .creativeCloudInfrastructure)
        #expect(protectedItem.scope == .protectedUserContent)
    }

    @Test func officePDFMakerAddInsAreDetectedWithoutTouchingOtherOfficeFiles() async throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("PDFMaker")
        defer { try? fileManager.removeItem(at: testRoot) }

        let systemLibrary = testRoot.appendingPathComponent("Library")
        let startup = systemLibrary.appendingPathComponent(
            "Application Support/Microsoft/Office365/User Content.localized/Startup"
        )
        let pdfMakerFiles = [
            startup.appendingPathComponent("Word/linkCreation.dotm"),
            startup.appendingPathComponent("Powerpoint/SaveAsAdobePDF.ppam"),
            startup.appendingPathComponent("Excel/AcrobatExcelAddin.xlam")
        ]
        let unrelated = startup.appendingPathComponent("Word/Normal.dotm")
        for file in pdfMakerFiles + [unrelated] {
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("test".utf8).write(to: file)
        }

        let results = await AdobeScanner(
            fileManager: FileManager(),
            home: testRoot.appendingPathComponent("Home"),
            systemLibrary: systemLibrary
        ).scan().filter { $0.path.contains(testRoot.lastPathComponent) }

        let detectedPaths = Set(results.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path })
        let expectedPaths = Set(pdfMakerFiles.map { $0.resolvingSymlinksInPath().path })
        #expect(detectedPaths == expectedPaths)
        #expect(results.allSatisfy { $0.scope == .adobeProduct })
        #expect(!results.contains { $0.path == unrelated.path })
    }

    @Test func officePDFMakerFilenameMatchingIsNarrow() {
        #expect(AdobeScanner.isAdobeOfficeAddInFilename("linkCreation.dotm"))
        #expect(AdobeScanner.isAdobeOfficeAddInFilename("SaveAsAdobePDF.ppam"))
        #expect(AdobeScanner.isAdobeOfficeAddInFilename("AcrobatExcelAddin.xlam"))
        #expect(!AdobeScanner.isAdobeOfficeAddInFilename("Normal.dotm"))
        #expect(!AdobeScanner.isAdobeOfficeAddInFilename("SaveAsAdobePDF.txt"))
    }

    @Test func symlinkedScanRootIsNotFollowed() async throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("SymlinkRoot")
        defer { try? fileManager.removeItem(at: testRoot) }
        let external = testRoot.appendingPathComponent("ExternalCaches")
        let caches = testRoot.appendingPathComponent("Home/Library/Caches")
        let adobeCache = external.appendingPathComponent("com.adobe.hidden")
        try fileManager.createDirectory(at: adobeCache, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: caches.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: caches, withDestinationURL: external)

        let results = await AdobeScanner(
            fileManager: FileManager(),
            home: testRoot.appendingPathComponent("Home"),
            systemLibrary: testRoot.appendingPathComponent("Library"),
            applicationRoots: [testRoot.appendingPathComponent("Applications")]
        ).scan()

        #expect(!results.contains { $0.path == caches.appendingPathComponent("com.adobe.hidden").path })
    }

    @Test func intermediateSymlinkIsNotTraversedButFinalSymlinkIsPreserved() async throws {
        let fileManager = FileManager.default
        let home = try makeTestFixtureRoot("IntermediateLink")
        defer { try? fileManager.removeItem(at: home) }
        let adobeSupport = home.appendingPathComponent("Library/Application Support/Adobe")
        let externalCoreSync = home.appendingPathComponent("ExternalCoreSync")
        let externalChild = externalCoreSync.appendingPathComponent("settings.db")
        let coreSyncLink = adobeSupport.appendingPathComponent("CoreSync")
        try fileManager.createDirectory(at: adobeSupport, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: externalCoreSync, withIntermediateDirectories: true)
        try Data("external".utf8).write(to: externalChild)
        try fileManager.createSymbolicLink(at: coreSyncLink, withDestinationURL: externalCoreSync)

        let results = await AdobeScanner(
            fileManager: FileManager(),
            home: home,
            systemLibrary: home.appendingPathComponent("SystemLibrary"),
            applicationRoots: [home.appendingPathComponent("Applications")]
        ).scan()

        #expect(results.contains { $0.path == coreSyncLink.path && $0.sourceIdentity != nil })
        #expect(!results.contains { $0.path == coreSyncLink.appendingPathComponent("settings.db").path })
    }

    @Test func finalSymlinkItemIsRecordedWithoutFollowingItsTarget() async throws {
        let fileManager = FileManager.default
        let home = try makeTestFixtureRoot("FinalLink")
        defer { try? fileManager.removeItem(at: home) }
        let caches = home.appendingPathComponent("Library/Caches")
        let external = home.appendingPathComponent("External/unrelated.dat")
        let link = caches.appendingPathComponent("com.adobe.link")
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: external.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unrelated".utf8).write(to: external)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: external)

        let item = try #require(await AdobeScanner(
            fileManager: FileManager(),
            home: home,
            systemLibrary: home.appendingPathComponent("SystemLibrary"),
            applicationRoots: [home.appendingPathComponent("Applications")]
        ).scan().first { $0.path == link.path })

        #expect(item.size == 0)
        #expect(item.sourceIdentity != nil)
        #expect(fileManager.fileExists(atPath: external.path))
    }

    @Test func mixedAdobeNamedApplicationParentIsNeverSelectedAsAWhole() async throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("MixedApps")
        defer { try? fileManager.removeItem(at: testRoot) }
        let applications = testRoot.appendingPathComponent("Applications")
        let mixedParent = applications.appendingPathComponent("Adobe Mixed Suite")
        let adobeApp = mixedParent.appendingPathComponent("Adobe Photoshop.app")
        let unrelated = mixedParent.appendingPathComponent("Personal Notes.txt")
        try fileManager.createDirectory(at: adobeApp, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: unrelated)

        let results = await AdobeScanner(
            fileManager: FileManager(),
            home: testRoot.appendingPathComponent("Home"),
            systemLibrary: testRoot.appendingPathComponent("Library"),
            applicationRoots: [applications]
        ).scan()

        #expect(results.contains { $0.path == adobeApp.path })
        #expect(!results.contains { $0.path == mixedParent.path })
        #expect(fileManager.fileExists(atPath: unrelated.path))
    }

    @Test func exactCreativeCloudParentDirectoriesWithForeignFilesAreNeverSelectedAsAWhole() async throws {
        let fileManager = FileManager.default
        let testRoot = try makeTestFixtureRoot("CreativeCloudMixed")
        defer { try? fileManager.removeItem(at: testRoot) }
        let applications = testRoot.appendingPathComponent("Applications")
        let parents = [
            applications.appendingPathComponent("Adobe Creative Cloud"),
            applications.appendingPathComponent("Utilities/Adobe Creative Cloud")
        ]
        var adobeApps: [URL] = []
        var foreignFiles: [URL] = []
        for (index, parent) in parents.enumerated() {
            let adobeApp = parent.appendingPathComponent("Adobe Helper \(index).app")
            let foreign = parent.appendingPathComponent("third-party.txt")
            try fileManager.createDirectory(at: adobeApp, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: foreign)
            adobeApps.append(adobeApp)
            foreignFiles.append(foreign)
        }

        let results = await AdobeScanner(
            fileManager: FileManager(),
            home: testRoot.appendingPathComponent("Home"),
            systemLibrary: testRoot.appendingPathComponent("Library"),
            applicationRoots: [applications]
        ).scan()

        for parent in parents {
            #expect(!results.contains { $0.path == parent.path })
        }
        for app in adobeApps {
            #expect(results.contains { $0.path == app.path })
        }
        for foreign in foreignFiles {
            #expect(fileManager.fileExists(atPath: foreign.path))
        }
    }

    private func runShell(_ command: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

struct LocalizationTests {
    @Test func systemLanguageSelectsHungarianOrEnglish() {
        #expect(AppLanguage.resolve(preferredLanguages: ["hu-HU", "en-US"]) == .hungarian)
        #expect(AppLanguage.resolve(preferredLanguages: ["en-GB", "hu-HU"]) == .english)
        #expect(AppLanguage.resolve(preferredLanguages: ["de-DE"]) == .english)
        #expect(AppLanguage.resolve(preferredLanguages: []) == .english)
    }
}

@MainActor
struct SelectionPresetTests {
    @Test func creativeCloudPresetLeavesProductsAndUserContentUntouched() {
        let model = AppModel()
        model.items = [
            item("/tmp/Creative Cloud", scope: .creativeCloudInfrastructure),
            item("/tmp/Photoshop.app", scope: .adobeProduct),
            item("/tmp/cloudnative", scope: .protectedUserContent)
        ]

        model.applyPreset(.creativeCloud)
        #expect(model.selectedIDs == ["/tmp/Creative Cloud"])

        model.applyPreset(.full)
        #expect(model.selectedIDs.contains("/tmp/Creative Cloud"))
        #expect(model.selectedIDs.contains("/tmp/Photoshop.app"))
        #expect(!model.selectedIDs.contains("/tmp/cloudnative"))
    }

    @Test func protectedContainerSelectionRequiresFullDiskAccess() {
        let model = AppModel()
        let protectedPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.adobe.ContextMenuExtension")
            .path
        model.items = [item(protectedPath, scope: .creativeCloudInfrastructure)]
        model.selectedIDs = [protectedPath]
        #expect(model.selectionRequiresFullDiskAccess)

        model.items = [item("/Library/Application Support/Adobe/Test", scope: .adobeProduct)]
        model.selectedIDs = ["/Library/Application Support/Adobe/Test"]
        #expect(!model.selectionRequiresFullDiskAccess)
    }

    @Test func creativeCloudPresetDoesNotSelectProductPreferencesButFullRemovalDoes() {
        let model = AppModel()
        let photoshop = item("/tmp/Adobe Photoshop 2026 Settings", scope: .adobeProduct)
        let deviceState = item("/tmp/Adobe/Device State", scope: .adobeProduct)
        let cloudState = item("/tmp/Adobe Creative Cloud", scope: .creativeCloudInfrastructure)
        model.items = [photoshop, deviceState, cloudState]

        model.applyPreset(.creativeCloud)
        #expect(model.selectedIDs == [cloudState.id])

        model.applyPreset(.full)
        #expect(model.selectedIDs == [photoshop.id, deviceState.id, cloudState.id])
    }

    @Test func permanentQuarantineDeletionReturnsToWelcomeScreen() {
        let model = AppModel()
        model.phase = .complete
        model.isPermanentlyDeletingQuarantine = true

        model.completePermanentQuarantineDeletion()

        #expect(model.phase == .welcome)
        #expect(!model.isPermanentlyDeletingQuarantine)
        #expect(model.lastSession == nil)
        #expect(model.noticeMessage?.contains("karantén") == true || model.noticeMessage?.contains("quarantine") == true)
    }

    private func item(_ path: String, scope: ComponentScope) -> CleanupItem {
        CleanupItem(
            path: path,
            category: .sharedComponent,
            risk: .medium,
            size: 1,
            reason: "Test",
            bundleIdentifier: nil,
            scope: scope
        )
    }
}
