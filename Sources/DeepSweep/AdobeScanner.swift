import Darwin
import Foundation

fileprivate struct AdobePatternRule {
    let directory: URL
    let category: CleanupCategory
    let risk: RiskLevel
    let reason: String
    let matches: @Sendable (String) -> Bool
}

actor AdobeScanner {
    private let fileManager: FileManager
    private let home: URL
    private let systemLibrary: URL
    private let applicationRoots: [URL]
    private let pathPolicy: AdobePathPolicy

    init(
        fileManager: FileManager = .default,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL = URL(fileURLWithPath: "/Library"),
        applicationRoots: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.home = home
        self.systemLibrary = systemLibrary
        self.applicationRoots = applicationRoots ?? [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")
        ]
        self.pathPolicy = AdobePathPolicy(
            fileManager: fileManager,
            home: home,
            systemLibrary: systemLibrary,
            applicationRoots: self.applicationRoots
        )
    }

    func scan() async -> [CleanupItem] {
        var found: [CleanupItem] = []
        found.append(contentsOf: scanAdobeUtilityItems())
        found.append(contentsOf: scanApplications())
        found.append(contentsOf: scanAdobePreferenceItems())

        found.append(contentsOf: scanAdobeSupportContainer(
            home.appendingPathComponent("Library/Application Support/Adobe"),
            category: .userData
        ))
        found.append(contentsOf: scanAdobeSupportContainer(
            URL(fileURLWithPath: "/Library/Application Support/Adobe"),
            category: .sharedComponent
        ))
        found.append(contentsOf: scanAdobeSupportContainer(
            URL(fileURLWithPath: "/Users/Shared/Adobe"),
            category: .sharedComponent
        ))
        found.append(contentsOf: scanContainerChildren(
            home.appendingPathComponent("Library/Caches/Adobe"),
            category: .cache,
            risk: .low,
            reason: L10n.text("Újragenerálható Adobe gyorsítótár.", "Regenerable Adobe cache.")
        ))
        found.append(contentsOf: scanContainerChildren(
            home.appendingPathComponent("Library/Logs/Adobe"),
            category: .log,
            risk: .low,
            reason: L10n.text("Adobe diagnosztikai napló.", "Adobe diagnostic log.")
        ))
        found.append(contentsOf: scanContainerChildren(
            URL(fileURLWithPath: "/Library/Logs/Adobe"),
            category: .log,
            risk: .low,
            reason: L10n.text("Rendszerszintű Adobe diagnosztikai napló.", "System-wide Adobe diagnostic log.")
        ))

        found.append(contentsOf: scanOfficePDFMakerAddIns())

        for candidate in exactCandidates() where fileManager.fileExists(atPath: candidate.url.path) {
            found.append(makeItem(candidate))
        }

        for pattern in pathPolicy.patternRules() {
            found.append(contentsOf: scanChildren(of: pattern))
        }

        var unique: [String: CleanupItem] = [:]
        let secured = found.compactMap(pathPolicy.secureScannedItem)
        for item in secured.sorted(by: { $0.url.pathComponents.count < $1.url.pathComponents.count }) {
            // If a parent directory is already a result, children would only make
            // the same bytes look larger and make the choice harder to understand.
            let covered = unique.keys.contains { item.path.hasPrefix($0 + "/") }
            if !covered { unique[item.path] = item }
        }
        return unique.values.sorted {
            if $0.category != $1.category {
                return categoryOrder($0.category) < categoryOrder($1.category)
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private struct Candidate {
        let url: URL
        let category: CleanupCategory
        let risk: RiskLevel
        let reason: String
    }

    private func exactCandidates() -> [Candidate] {
        [
            Candidate(url: URL(fileURLWithPath: "/Library/Application Support/regid.1986-12.com.adobe"), category: .sharedComponent, risk: .medium, reason: L10n.text("Adobe-licencelési és termékregisztrációs adatok.", "Adobe licensing and product registration data.")),
        ]
    }

    private func scanAdobePreferenceItems() -> [CleanupItem] {
        let preferences = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        guard pathPolicy.isSafeContainer(preferences) else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(
            at: preferences,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [CleanupItem] = []
        for child in children {
            let name = child.lastPathComponent.lowercased()
            if name == "adobe" {
                let nested = scanAdobePreferenceContainer(child)
                if nested.isEmpty {
                    items.append(makeAdobePreferenceItem(child))
                } else {
                    items.append(contentsOf: nested)
                }
            } else if name.hasPrefix("adobe ") || name.hasPrefix("com.adobe.") {
                items.append(makeAdobePreferenceItem(child))
            }
        }
        return items
    }

    private func scanAdobePreferenceContainer(_ directory: URL) -> [CleanupItem] {
        guard pathPolicy.isSafeContainer(directory) else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children
            .filter { $0.lastPathComponent != ".DS_Store" }
            .map(makeAdobePreferenceItem)
    }

    private func makeAdobePreferenceItem(_ url: URL) -> CleanupItem {
        let deviceState = Self.isDeviceStateName(url.lastPathComponent)
        return CleanupItem(
            path: url.path,
            category: .settings,
            risk: .high,
            size: allocatedSize(url),
            reason: deviceState
                ? L10n.text(
                    "Adobe-eszköz- és alkalmazásállapot; korábbi munkamenetek vagy legutóbbi fájlok adatait őrizheti.",
                    "Adobe device and application state; it may retain previous sessions or recent-file information."
                )
                : L10n.text(
                    "Adobe-termék felhasználói beállítása; legutóbbi fájlokat, munkaterületet vagy személyes presetet is tartalmazhat.",
                    "Adobe product user setting; it may include recent files, workspace state, or personal presets."
                ),
            bundleIdentifier: nil,
            scope: pathPolicy.scope(for: url.path, bundleIdentifier: nil)
        )
    }

    nonisolated static func isDeviceStateName(_ name: String) -> Bool {
        let normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalized == "devicestate"
    }

    private func scanOfficePDFMakerAddIns() -> [CleanupItem] {
        let userLibrary = home.appendingPathComponent("Library")
        let roots = [
            systemLibrary.appendingPathComponent("Application Support/Microsoft/Office365/User Content.localized/Startup"),
            systemLibrary.appendingPathComponent("Application Support/Microsoft/Office365/User Content/Startup"),
            userLibrary.appendingPathComponent("Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized"),
            userLibrary.appendingPathComponent("Group Containers/UBF8T346G9.Office/User Content/Startup"),
            userLibrary.appendingPathComponent("Application Support/Microsoft/Office/Startup")
        ]

        var results: [CleanupItem] = []
        for root in roots {
            guard pathPolicy.isSafeContainer(root) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard pathPolicy.hasSafeParentPath(url) else {
                    enumerator.skipDescendants()
                    continue
                }
                if url.pathComponents.count > root.pathComponents.count + 3 {
                    enumerator.skipDescendants()
                    continue
                }
                guard Self.isAdobeOfficeAddInFilename(url.lastPathComponent) else { continue }
                results.append(CleanupItem(
                    path: url.path,
                    category: .sharedComponent,
                    risk: .medium,
                    size: allocatedSize(url),
                    reason: L10n.text(
                        "Adobe PDFMaker Office-bővítmény; Acrobat eltávolítása után hibát okozhat.",
                        "Adobe PDFMaker Office add-in; it may cause errors after Acrobat is removed."
                    ),
                    bundleIdentifier: nil,
                    scope: .adobeProduct
                ))
            }
        }
        return results
    }

    nonisolated static func isAdobeOfficeAddInFilename(_ filename: String) -> Bool {
        let value = filename.lowercased()
        let knownNames: Set<String> = [
            "linkcreation.dotm",
            "saveasadobepdf.ppam",
            "acrobatexceladdin.xlam",
            "adobepdfmaker.dotm",
            "saveasadobepdf.xlam",
            "adobepdfmaker.ppam",
            "pdfmaker.dot",
            "pdfmaker.xla",
            "pdfmaker.ppa"
        ]
        guard knownNames.contains(value)
                || value.contains("pdfmaker")
                || value.contains("saveasadobepdf")
                || value.contains("acrobat") && value.contains("addin")
        else { return false }

        return ["dot", "dotm", "xla", "xlam", "ppa", "ppam"].contains(
            URL(fileURLWithPath: value).pathExtension
        )
    }

    private func scanApplications() -> [CleanupItem] {
        var items: [CleanupItem] = []
        for root in applicationRoots {
            guard pathPolicy.isSafeContainer(root) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard pathPolicy.hasSafeParentPath(url) else {
                    enumerator.skipDescendants()
                    continue
                }
                if url.pathComponents.count > root.pathComponents.count + 3 {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension.lowercased() == "app" else { continue }
                let bundle = Bundle(url: url)
                let identifier = bundle?.bundleIdentifier?.lowercased()
                let applicationName = url.deletingPathExtension().lastPathComponent.lowercased()
                let nameLooksAdobe = applicationName == "adobe" || applicationName.hasPrefix("adobe ")
                guard identifier?.hasPrefix("com.adobe.") == true || nameLooksAdobe else { continue }
                items.append(CleanupItem(
                    path: url.path,
                    category: .application,
                    risk: .medium,
                    size: allocatedSize(url),
                    reason: L10n.text("Telepített Adobe-alkalmazás.", "Installed Adobe application."),
                    bundleIdentifier: identifier,
                    scope: pathPolicy.scope(for: url.path, bundleIdentifier: identifier)
                ))
                enumerator.skipDescendants()
            }
        }
        return items
    }

    private func scanAdobeUtilityItems() -> [CleanupItem] {
        var items: [CleanupItem] = []
        for applicationsRoot in applicationRoots {
            let utilities = applicationsRoot.appendingPathComponent("Utilities", isDirectory: true)
            guard pathPolicy.isSafeContainer(utilities) else { continue }
            guard let children = try? fileManager.contentsOfDirectory(
                at: utilities,
                includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children where Self.isAdobeUtilityItem(child, fileManager: fileManager) {
                let bundleIdentifier = child.pathExtension.lowercased() == "app"
                    ? Bundle(url: child)?.bundleIdentifier?.lowercased()
                    : nil
                items.append(CleanupItem(
                    path: child.path,
                    category: .application,
                    risk: .medium,
                    size: allocatedSize(child),
                    reason: L10n.text(
                        "Az Alkalmazások/Segédprogramok mappába telepített Adobe-segédprogram vagy telepítőösszetevő.",
                        "Adobe utility or installer component installed in Applications/Utilities."
                    ),
                    bundleIdentifier: bundleIdentifier,
                    scope: pathPolicy.scope(for: child.path, bundleIdentifier: bundleIdentifier)
                ))
            }
        }
        return items
    }

    nonisolated static func isAdobeUtilityItem(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let filename = url.lastPathComponent
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        if url.pathExtension.lowercased() == "app",
           Bundle(url: url)?.bundleIdentifier?.lowercased().hasPrefix("com.adobe.") == true {
            return true
        }

        guard fileManager.fileExists(atPath: url.path) else { return false }
        if url.pathExtension.lowercased() != "app", stem == "adobe creative cloud" {
            return false
        }
        return stem == "adobe"
            || stem.hasPrefix("adobe ")
            || filename.lowercased().hasPrefix("com.adobe.")
    }

    private func scanChildren(of pattern: AdobePatternRule) -> [CleanupItem] {
        guard pathPolicy.isSafeContainer(pattern.directory) else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(
            at: pattern.directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return children.filter { pattern.matches($0.lastPathComponent) }.map {
            CleanupItem(
                path: $0.path,
                category: pattern.category,
                risk: pattern.risk,
                size: allocatedSize($0),
                reason: pattern.reason,
                bundleIdentifier: nil,
                scope: pathPolicy.scope(for: $0.path, bundleIdentifier: nil)
            )
        }
    }

    private func makeItem(_ candidate: Candidate) -> CleanupItem {
        CleanupItem(
            path: candidate.url.path,
            category: candidate.category,
            risk: candidate.risk,
            size: allocatedSize(candidate.url),
            reason: candidate.reason,
            bundleIdentifier: nil,
            scope: pathPolicy.scope(for: candidate.url.path, bundleIdentifier: nil)
        )
    }

    private func scanAdobeSupportContainer(_ directory: URL, category: CleanupCategory) -> [CleanupItem] {
        guard pathPolicy.isSafeContainer(directory) else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        var items: [CleanupItem] = []
        for child in children where child.lastPathComponent != ".DS_Store" {
            let name = child.lastPathComponent.lowercased()
            if name == "coresync" {
                if pathPolicy.isSafeContainer(child),
                   let coreChildren = try? fileManager.contentsOfDirectory(
                       at: child,
                       includingPropertiesForKeys: [.isDirectoryKey],
                       options: []
                   ) {
                    for coreChild in coreChildren where coreChild.lastPathComponent != ".DS_Store" {
                        let isCloudNative = coreChild.lastPathComponent.lowercased() == "cloudnative"
                        items.append(CleanupItem(
                            path: coreChild.path,
                            category: isCloudNative ? .userData : category,
                            risk: isCloudNative ? .high : .medium,
                            size: allocatedSize(coreChild),
                            reason: isCloudNative
                                ? L10n.text("Nem szinkronizált Creative Cloud-tartalmat is tartalmazhat; automatikusan védett.", "May contain unsynchronized Creative Cloud content; automatically protected.")
                                : L10n.text("A CoreSync újratelepíthető helyi összetevője.", "Reinstallable local CoreSync component."),
                            bundleIdentifier: nil,
                            scope: isCloudNative ? .protectedUserContent : .creativeCloudInfrastructure
                        ))
                    }
                } else if (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    items.append(CleanupItem(
                        path: child.path,
                        category: category,
                        risk: .medium,
                        size: 0,
                        reason: L10n.text(
                            "A CoreSync szimbolikus hivatkozása; csak maga a hivatkozás kerül karanténba.",
                            "CoreSync symbolic link; only the link itself will be quarantined."
                        ),
                        bundleIdentifier: nil,
                        scope: .creativeCloudInfrastructure
                    ))
                }
                continue
            }

            let protectedLibraryContent = name.contains("creative cloud libraries")
            let deviceState = Self.isDeviceStateName(child.lastPathComponent)
            items.append(CleanupItem(
                path: child.path,
                category: protectedLibraryContent ? .userData : category,
                risk: .high,
                size: allocatedSize(child),
                reason: protectedLibraryContent
                    ? L10n.text("Creative Cloud-könyvtári tartalom; az újratelepítési mód megőrzi.", "Creative Cloud Libraries content; preserved by reinstall mode.")
                    : (deviceState
                        ? L10n.text("Adobe helyi eszköz- és alkalmazásállapot.", "Local Adobe device and application state.")
                    : (category == .userData
                        ? L10n.text("Adobe felhasználói beállítás vagy helyi összetevő.", "Adobe user setting or local component.")
                        : L10n.text("Adobe rendszerszintű összetevő vagy bővítményadat.", "System-wide Adobe component or plug-in data."))),
                bundleIdentifier: nil,
                scope: protectedLibraryContent
                    ? .protectedUserContent
                    : pathPolicy.scope(for: child.path, bundleIdentifier: nil)
            ))
        }
        return items
    }

    private func scanContainerChildren(
        _ directory: URL,
        category: CleanupCategory,
        risk: RiskLevel,
        reason: String
    ) -> [CleanupItem] {
        guard pathPolicy.isSafeContainer(directory) else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }
        return children.filter { $0.lastPathComponent != ".DS_Store" }.map {
            CleanupItem(
                path: $0.path,
                category: category,
                risk: risk,
                size: allocatedSize($0),
                reason: reason,
                bundleIdentifier: nil,
                scope: pathPolicy.scope(for: $0.path, bundleIdentifier: nil)
            )
        }
    }

    private func allocatedSize(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
        ]
        if let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink == true {
            return 0
        }
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.fileAllocatedSize ?? values.totalFileAllocatedSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            if let values = try? child.resourceValues(forKeys: keys), values.isRegularFile == true {
                total += Int64(values.fileAllocatedSize ?? values.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    private func categoryOrder(_ category: CleanupCategory) -> Int {
        CleanupCategory.allCases.firstIndex(of: category) ?? 99
    }
}

struct AdobePathClassification: Sendable {
    let category: CleanupCategory
    let risk: RiskLevel
    let scope: ComponentScope
    let bundleIdentifier: String?
}

struct AdobePathPolicy: @unchecked Sendable {
    private let home: URL
    private let systemLibrary: URL
    private let applicationRoots: [URL]

    init(
        fileManager: FileManager = .default,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL = URL(fileURLWithPath: "/Library"),
        applicationRoots: [URL]? = nil
    ) {
        self.home = home
        self.systemLibrary = systemLibrary
        self.applicationRoots = (applicationRoots ?? [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")
        ])
    }

    fileprivate func patternRules() -> [AdobePatternRule] {
        let userLibrary = home.appendingPathComponent("Library")
        return [
            AdobePatternRule(directory: userLibrary.appendingPathComponent("Application Support"), category: .sharedComponent, risk: .high, reason: L10n.text("Adobe felhasználói összetevő vagy bővítményadat.", "Adobe user component or plug-in data."), matches: Self.isAdobeID),
            AdobePatternRule(directory: userLibrary.appendingPathComponent("LaunchAgents"), category: .service, risk: .medium, reason: L10n.text("Bejelentkezéskor induló Adobe háttérfolyamat.", "Adobe background process launched at login."), matches: Self.isAdobeID),
            AdobePatternRule(directory: userLibrary.appendingPathComponent("Saved Application State"), category: .cache, risk: .low, reason: L10n.text("Adobe-ablakok visszaállítható állapota.", "Restorable Adobe window state."), matches: Self.isAdobeID),
            AdobePatternRule(directory: userLibrary.appendingPathComponent("Caches"), category: .cache, risk: .low, reason: L10n.text("Újragenerálható Adobe gyorsítótár.", "Regenerable Adobe cache."), matches: Self.isKnownAdobeSibling),
            AdobePatternRule(directory: userLibrary.appendingPathComponent("Logs"), category: .log, risk: .low, reason: L10n.text("Adobe diagnosztikai napló.", "Adobe diagnostic log."), matches: Self.isKnownAdobeSibling),
            AdobePatternRule(directory: userLibrary.appendingPathComponent("Containers"), category: .settings, risk: .medium, reason: L10n.text("Adobe-alkalmazás elkülönített adatai.", "Sandboxed Adobe application data."), matches: Self.isAdobeID),
            AdobePatternRule(directory: userLibrary.appendingPathComponent("Group Containers"), category: .settings, risk: .high, reason: L10n.text("Adobe-alkalmazások megosztott konténeradatai; beállításokat, licenc- vagy alkalmazásállapotot is tartalmazhatnak.", "Shared Adobe application container data; it may contain settings, licensing, or application state."), matches: Self.isAdobeGroupContainer),
            AdobePatternRule(directory: userLibrary.appendingPathComponent("Application Scripts"), category: .settings, risk: .medium, reason: L10n.text("Adobe-alkalmazás automatizálási adatai.", "Adobe application automation data."), matches: Self.isAdobeID),
            AdobePatternRule(directory: userLibrary.appendingPathComponent("HTTPStorages"), category: .cache, risk: .low, reason: L10n.text("Újragenerálható Adobe hálózati gyorsítótár.", "Regenerable Adobe network cache."), matches: Self.isAdobeID),
            AdobePatternRule(directory: userLibrary.appendingPathComponent("WebKit"), category: .cache, risk: .low, reason: L10n.text("Adobe webes felületének újragenerálható adatai.", "Regenerable data for Adobe web interfaces."), matches: Self.isAdobeID),
            AdobePatternRule(directory: systemLibrary.appendingPathComponent("Application Support"), category: .sharedComponent, risk: .high, reason: L10n.text("Adobe rendszerszintű összetevő vagy bővítményadat.", "System-wide Adobe component or plug-in data."), matches: Self.isKnownAdobeSibling),
            AdobePatternRule(directory: systemLibrary.appendingPathComponent("LaunchAgents"), category: .service, risk: .medium, reason: L10n.text("Minden felhasználónál induló Adobe háttérfolyamat.", "Adobe background process launched for every user."), matches: Self.isAdobeID),
            AdobePatternRule(directory: systemLibrary.appendingPathComponent("LaunchDaemons"), category: .service, risk: .medium, reason: L10n.text("Rendszerszintű Adobe háttérszolgáltatás.", "System-wide Adobe background service."), matches: Self.isAdobeID),
            AdobePatternRule(directory: systemLibrary.appendingPathComponent("PrivilegedHelperTools"), category: .service, risk: .medium, reason: L10n.text("Emelt jogosultságú Adobe segédprogram.", "Privileged Adobe helper tool."), matches: Self.isAdobeID),
            AdobePatternRule(directory: systemLibrary.appendingPathComponent("Preferences"), category: .settings, risk: .medium, reason: L10n.text("Rendszerszintű Adobe-beállítás.", "System-wide Adobe setting."), matches: Self.isAdobeID),
            AdobePatternRule(directory: systemLibrary.appendingPathComponent("Internet Plug-Ins"), category: .sharedComponent, risk: .medium, reason: L10n.text("Adobe böngésző- vagy PDF-bővítmény.", "Adobe browser or PDF plug-in."), matches: Self.isAdobeName),
            AdobePatternRule(directory: systemLibrary.appendingPathComponent("StartupItems"), category: .service, risk: .medium, reason: L10n.text("Régi típusú Adobe indítási szolgáltatás.", "Legacy Adobe startup service."), matches: Self.isAdobeName)
        ]
    }

    func secureScannedItem(_ item: CleanupItem) -> CleanupItem? {
        guard isAbsoluteAndNormalized(item.path),
              hasNoSymlinkComponents(URL(fileURLWithPath: item.path), includeLeaf: false),
              let identity = identity(at: item.path),
              let classification = classification(for: item.path, contentURL: item.url),
              classification.category == item.category,
              classification.scope == item.scope
        else { return nil }

        return rebuilt(item, classification: classification, identity: identity)
    }

    func validatedItemForQuarantine(_ item: CleanupItem) throws -> CleanupItem {
        guard isAbsoluteAndNormalized(item.path),
              hasNoSymlinkComponents(URL(fileURLWithPath: item.path), includeLeaf: false),
              let identity = identity(at: item.path),
              item.sourceIdentity == nil || item.sourceIdentity == identity,
              let classification = classification(for: item.path, contentURL: item.url),
              classification.category == item.category,
              classification.scope == item.scope
        else { throw CleanupError.invalidItemPath(item.path) }

        return rebuilt(item, classification: classification, identity: identity)
    }

    func validatedManifestItem(_ item: CleanupItem, sourceURL: URL?) throws -> CleanupItem {
        guard isAbsoluteAndNormalized(item.path),
              hasNoSymlinkComponents(URL(fileURLWithPath: item.path), includeLeaf: false),
              let classification = classification(
                  for: item.path,
                  contentURL: sourceURL,
                  bundleIdentifierHint: sourceURL == nil ? item.bundleIdentifier : nil
              ),
              classification.category == item.category,
              classification.scope == item.scope
        else { throw CleanupError.invalidManifestItem(item.path) }

        if let storedBundleIdentifier = item.bundleIdentifier?.lowercased(),
           let actualBundleIdentifier = classification.bundleIdentifier?.lowercased(),
           storedBundleIdentifier != actualBundleIdentifier {
            throw CleanupError.invalidManifestItem(item.path)
        }

        let sourceIdentity = sourceURL.flatMap { identity(at: $0.path) }
        return rebuilt(item, classification: classification, identity: sourceIdentity)
    }

    func validateUnchanged(_ item: CleanupItem) throws {
        guard isAbsoluteAndNormalized(item.path),
              hasNoSymlinkComponents(URL(fileURLWithPath: item.path), includeLeaf: false),
              let expectedIdentity = item.sourceIdentity,
              identity(at: item.path) == expectedIdentity
        else { throw CleanupError.sourceChanged(item.path) }
    }

    func validateRestoreMove(source: URL, destinationPath: String, expectedIdentity: FileIdentity?) throws {
        guard isAbsoluteAndNormalized(source.path),
              isAbsoluteAndNormalized(destinationPath),
              hasNoSymlinkComponents(source, includeLeaf: false),
              hasNoSymlinkComponents(URL(fileURLWithPath: destinationPath), includeLeaf: false),
              let expectedIdentity,
              identity(at: source.path) == expectedIdentity
        else { throw CleanupError.sourceChanged(destinationPath) }
    }

    func isAbsoluteNormalizedPath(_ path: String) -> Bool {
        isAbsoluteAndNormalized(path)
    }

    func isSafeContainer(_ url: URL) -> Bool {
        isAbsoluteAndNormalized(url.path) && hasNoSymlinkComponents(url, includeLeaf: true)
    }

    func hasSafeParentPath(_ url: URL) -> Bool {
        isAbsoluteAndNormalized(url.path) && hasNoSymlinkComponents(url, includeLeaf: false)
    }

    func isValidatedLaunchServicePath(_ item: CleanupItem) -> Bool {
        guard item.category == .service,
              item.path.hasSuffix(".plist"),
              let classification = classification(for: item.path, contentURL: nil),
              classification.category == .service,
              classification.scope == item.scope
        else { return false }

        let launchRoots = [
            home.appendingPathComponent("Library/LaunchAgents"),
            systemLibrary.appendingPathComponent("LaunchAgents"),
            systemLibrary.appendingPathComponent("LaunchDaemons")
        ]
        return launchRoots.contains { relativeComponents(of: item.path, below: $0)?.count == 1 }
    }

    func isAllowedAdobeExecutablePath(_ path: String) -> Bool {
        guard isAbsoluteAndNormalized(path),
              hasNoSymlinkComponents(URL(fileURLWithPath: path), includeLeaf: false)
        else { return false }

        let adobeSupportRoots = [
            home.appendingPathComponent("Library/Application Support/Adobe"),
            systemLibrary.appendingPathComponent("Application Support/Adobe")
        ]
        if adobeSupportRoots.contains(where: { relativeComponents(of: path, below: $0) != nil }) {
            return true
        }

        let helperRoot = systemLibrary.appendingPathComponent("PrivilegedHelperTools")
        if let relative = relativeComponents(of: path, below: helperRoot),
           relative.count == 1,
           relative[0].lowercased().hasPrefix("com.adobe.") {
            return true
        }

        for root in applicationRoots {
            guard let relative = relativeComponents(of: path, below: root),
                  let first = relative.first
            else { continue }
            let firstName = URL(fileURLWithPath: first).deletingPathExtension()
                .lastPathComponent.lowercased()
            if firstName == "adobe" || firstName.hasPrefix("adobe ") {
                return true
            }
            if relative.count > 1,
               relative[0] == "Utilities" {
                let utilityName = URL(fileURLWithPath: relative[1]).deletingPathExtension()
                    .lastPathComponent.lowercased()
                if utilityName == "adobe" || utilityName.hasPrefix("adobe ") {
                    return true
                }
            }
        }
        return false
    }

    func identity(at path: String) -> FileIdentity? {
        var information = stat()
        let result = path.withCString { Darwin.lstat($0, &information) }
        guard result == 0 else { return nil }
        return FileIdentity(device: UInt64(information.st_dev), inode: UInt64(information.st_ino))
    }

    func nearestExistingParentIdentity(for path: String) -> FileIdentity? {
        let destination = URL(fileURLWithPath: path)
        guard isAbsoluteAndNormalized(path),
              hasNoSymlinkComponents(destination, includeLeaf: false)
        else { return nil }

        var candidate = destination.deletingLastPathComponent()
        while true {
            if let identity = identity(at: candidate.path) {
                guard hasNoSymlinkComponents(candidate, includeLeaf: true) else { return nil }
                return identity
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
    }

    private func classification(
        for path: String,
        contentURL: URL?,
        bundleIdentifierHint: String? = nil
    ) -> AdobePathClassification? {
        guard isAbsoluteAndNormalized(path) else { return nil }
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        let bundleIdentifier = contentURL.flatMap(Bundle.init(url:))?.bundleIdentifier?.lowercased()
            ?? bundleIdentifierHint?.lowercased()

        for root in applicationRoots {
            guard let relative = relativeComponents(of: path, below: root), !relative.isEmpty else { continue }
            if relative.count == 2,
               relative[0] == "Utilities",
               (Self.isAdobeName(relative[1]) || bundleIdentifier?.hasPrefix("com.adobe.") == true) {
                return result(.application, .medium, scope(for: path, bundleIdentifier: bundleIdentifier), bundleIdentifier)
            }
            if relative.count <= 3,
               url.pathExtension.lowercased() == "app",
               (Self.isAdobeApplicationName(filename) || bundleIdentifier?.hasPrefix("com.adobe.") == true) {
                return result(.application, .medium, scope(for: path, bundleIdentifier: bundleIdentifier), bundleIdentifier)
            }
        }

        let supportRoots: [(URL, CleanupCategory)] = [
            (home.appendingPathComponent("Library/Application Support/Adobe"), .userData),
            (systemLibrary.appendingPathComponent("Application Support/Adobe"), .sharedComponent),
            (URL(fileURLWithPath: "/Users/Shared/Adobe"), .sharedComponent)
        ]
        for (root, category) in supportRoots {
            guard let relative = relativeComponents(of: path, below: root),
                  relative.count == 1 || relative.count == 2 && relative[0].lowercased() == "coresync"
            else { continue }
            let name = relative.last?.lowercased() ?? ""
            // An unreadable CoreSync directory may contain unsynced documents.
            // Only its individually inspected children or the link itself qualify.
            if relative.count == 1, name == "coresync", let contentURL,
               (try? contentURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true {
                return nil
            }
            if name == "cloudnative" || name.contains("creative cloud libraries") {
                return result(.userData, .high, .protectedUserContent, bundleIdentifier)
            }
            let risk: RiskLevel = relative.first?.lowercased() == "coresync" ? .medium : .high
            return result(category, risk, scope(for: path, bundleIdentifier: bundleIdentifier), bundleIdentifier)
        }

        let directAdobeContainers: [(URL, CleanupCategory, RiskLevel)] = [
            (home.appendingPathComponent("Library/Caches/Adobe"), .cache, .low),
            (home.appendingPathComponent("Library/Logs/Adobe"), .log, .low),
            (systemLibrary.appendingPathComponent("Logs/Adobe"), .log, .low)
        ]
        for (root, category, risk) in directAdobeContainers
        where relativeComponents(of: path, below: root)?.count == 1 {
            return result(category, risk, scope(for: path, bundleIdentifier: bundleIdentifier), bundleIdentifier)
        }

        let preferences = home.appendingPathComponent("Library/Preferences")
        if let relative = relativeComponents(of: path, below: preferences) {
            let directAdobeItem = relative.count == 1 && Self.isAdobeName(relative[0])
            let childOfAdobe = relative.count == 2 && relative[0].lowercased() == "adobe"
            if directAdobeItem || childOfAdobe {
                return result(.settings, .high, scope(for: path, bundleIdentifier: bundleIdentifier), bundleIdentifier)
            }
        }

        let officeRoots = [
            systemLibrary.appendingPathComponent("Application Support/Microsoft/Office365/User Content.localized/Startup"),
            systemLibrary.appendingPathComponent("Application Support/Microsoft/Office365/User Content/Startup"),
            home.appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized"),
            home.appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/User Content/Startup"),
            home.appendingPathComponent("Library/Application Support/Microsoft/Office/Startup")
        ]
        if officeRoots.contains(where: {
            guard let relative = relativeComponents(of: path, below: $0) else { return false }
            return !relative.isEmpty && relative.count <= 3
        }), AdobeScanner.isAdobeOfficeAddInFilename(filename) {
            return result(.sharedComponent, .medium, .adobeProduct, bundleIdentifier)
        }

        if path == systemLibrary.appendingPathComponent("Application Support/regid.1986-12.com.adobe").path {
            return result(.sharedComponent, .medium, .adobeProduct, bundleIdentifier)
        }

        for rule in patternRules() {
            guard let relative = relativeComponents(of: path, below: rule.directory),
                  relative.count == 1,
                  rule.matches(relative[0])
            else { continue }
            return result(rule.category, rule.risk, scope(for: path, bundleIdentifier: bundleIdentifier), bundleIdentifier)
        }

        return nil
    }

    private func rebuilt(
        _ item: CleanupItem,
        classification: AdobePathClassification,
        identity: FileIdentity?
    ) -> CleanupItem {
        CleanupItem(
            path: item.path,
            category: classification.category,
            risk: classification.risk,
            size: item.size,
            reason: item.reason,
            bundleIdentifier: classification.bundleIdentifier,
            scope: classification.scope,
            sourceIdentity: identity
        )
    }

    private func result(
        _ category: CleanupCategory,
        _ risk: RiskLevel,
        _ scope: ComponentScope,
        _ bundleIdentifier: String?
    ) -> AdobePathClassification {
        AdobePathClassification(
            category: category,
            risk: risk,
            scope: scope,
            bundleIdentifier: bundleIdentifier
        )
    }

    func scope(for path: String, bundleIdentifier: String?) -> ComponentScope {
        let value = path.lowercased()
        let identifier = bundleIdentifier?.lowercased() ?? ""
        let pathComponents = Set(URL(fileURLWithPath: path).pathComponents.map { $0.lowercased() })
        let markers = [
            "creative cloud", "creativecloud", "/coresync", "/ccxprocess",
            "/oobe", "/adobe desktop common", "/acc.",
            "com.adobe.acc", "com.adobe.ccx", "com.adobe.coresync",
            "com.adobe.adobecreativecloud", "com.adobe.creativeclouddesktop",
            "com.adobe.ngl", "com.adobe.growthsdk", "adobe-hub-app",
            "jq525l2mzd-com.adobe.jq525.flags"
        ]
        if pathComponents.contains("acc")
            || markers.contains(where: { value.contains($0) || identifier.contains($0) }) {
            return .creativeCloudInfrastructure
        }
        return .adobeProduct
    }

    private func isAbsoluteAndNormalized(_ path: String) -> Bool {
        guard !path.contains("\0"), path.hasPrefix("/"), path == "/" || !path.hasSuffix("/") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first == "",
              !components.dropFirst().contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else { return false }
        return true
    }

    private func relativeComponents(of path: String, below root: URL) -> [String]? {
        let normalizedRoot = root.path
        guard path.hasPrefix(normalizedRoot + "/") else { return nil }
        let relative = String(path.dropFirst(normalizedRoot.count + 1))
        return relative.split(separator: "/").map(String.init)
    }

    private func hasNoSymlinkComponents(_ url: URL, includeLeaf: Bool) -> Bool {
        let components = url.pathComponents
        let componentCount = includeLeaf ? components.count : max(components.count - 1, 1)
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in components.dropFirst().prefix(componentCount - 1) {
            current.appendPathComponent(component)
            var information = stat()
            let result = current.path.withCString { Darwin.lstat($0, &information) }
            if result == 0 {
                if information.st_mode & S_IFMT == S_IFLNK { return false }
            } else if errno != ENOENT {
                return false
            }
        }
        return true
    }

    private static func isAdobeApplicationName(_ name: String) -> Bool {
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.lowercased()
        return stem == "adobe" || stem.hasPrefix("adobe ")
    }

    static func isAdobeName(_ name: String) -> Bool {
        let value = name.lowercased()
        return value.hasPrefix("com.adobe.") || value.hasPrefix("adobe ") || value == "adobe"
    }

    static func isAdobeID(_ name: String) -> Bool {
        let value = name.lowercased()
        return value.hasPrefix("com.adobe.")
            || value.contains(".com.adobe.")
            || value.contains("-com.adobe.")
    }

    static func isKnownAdobeComponent(_ name: String) -> Bool {
        let value = name.lowercased()
        return isAdobeName(name)
            || isAdobeID(name)
            || value.contains("creativecloud")
            || value.contains("creative cloud")
            || value.hasPrefix("coresync")
            || value.hasPrefix("ccxprocess")
            || value == "adobe-hub-app"
            || value == "ngl"
    }

    static func isKnownAdobeSibling(_ name: String) -> Bool {
        name.lowercased() != "adobe" && isKnownAdobeComponent(name)
    }

    static func isAdobeGroupContainer(_ name: String) -> Bool {
        isAdobeID(name) || name.lowercased() == "adobe-hub-app"
    }
}
