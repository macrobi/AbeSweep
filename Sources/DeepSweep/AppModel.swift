import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case welcome
        case scanning
        case results
        case cleaning
        case restoring
        case complete
    }

    @Published var phase: Phase = .welcome
    @Published var items: [CleanupItem] = []
    @Published var selectedIDs: Set<String> = []
    @Published var hostsCleanupPlan: HostsCleanupPlan?
    @Published var unverifiedHostsCandidates: [String] = []
    @Published var malformedManagedHostsBlock = false
    @Published var cleanAdobeHosts = false
    @Published var automaticDomainReview = false
    @Published var isReviewingDomains = false
    @Published var domainReviewMessage = ""
    @Published var newOfficialDomainCandidates: [String] = []
    @Published var preset: SelectionPreset = .safe
    @Published var errorMessage: String?
    @Published var lastSession: CleanupSession?
    @Published var showingConfirmation = false
    @Published var cleanupCompleted = 0
    @Published var cleanupTotal = 0
    @Published var cleanupCurrentPath = ""
    @Published var cleanupStage = "preparing"
    @Published var cancellationRequested = false
    @Published var noticeMessage: String?
    @Published var showingLog = false
    @Published var logContents = ""
    @Published var showingDisclaimer = false
    @Published var showingQuarantineManager = false
    @Published private(set) var quarantineRecords: [QuarantineRecord] = []
    @Published private(set) var fullDiskAccessStatus: FullDiskAccessStatus = .unknown
    @Published var fullDiskAccessConfirmationMessage: String?
    @Published var restoreSuccessMessage: String?
    @Published private(set) var errorOffersFullDiskAccessSettings = false
    @Published var isPermanentlyDeletingQuarantine = false
    @Published private(set) var quarantinePermanentlyDeleted = false
    @Published private(set) var disclaimerAccepted = false
    @Published private(set) var suppressDisclaimerOnLaunch = false
    @Published private(set) var disclaimerRequiresAcceptance = false

    private let scanner = AdobeScanner()
    private let hostsFileService = HostsFileService()
    private let domainReviewer = AdobeDomainCatalogReviewer()
    private let cleanupService = CleanupService()
    private let fullDiskAccessChecker = FullDiskAccessChecker()
    private var runContext: CleanupRunContext?
    private var progressTask: Task<Void, Never>?
    private(set) var lastLogURL: URL?

    init() {
        suppressDisclaimerOnLaunch = UserDefaults.standard.bool(forKey: "AbeSweepSuppressDisclaimerOnLaunch")
        disclaimerAccepted = suppressDisclaimerOnLaunch
        disclaimerRequiresAcceptance = !suppressDisclaimerOnLaunch
        showingDisclaimer = !suppressDisclaimerOnLaunch

        if UserDefaults.standard.object(forKey: "AbeSweepAutomaticDomainReview") != nil {
            automaticDomainReview = UserDefaults.standard.bool(forKey: "AbeSweepAutomaticDomainReview")
        }
        if let data = UserDefaults.standard.data(forKey: "AbeSweepLastDomainReview"),
           let result = try? JSONDecoder().decode(DomainReviewResult.self, from: data) {
            newOfficialDomainCandidates = result.newCandidates
            domainReviewMessage = reviewMessage(for: result)
        }
        refreshQuarantineSessions()
        refreshFullDiskAccessStatus()
    }

    var isMutating: Bool {
        phase == .cleaning || phase == .restoring || isPermanentlyDeletingQuarantine
    }
    var isBusy: Bool { isMutating || phase == .scanning }

    var selectedItems: [CleanupItem] { items.filter { selectedIDs.contains($0.id) } }
    var hasSelectedOperation: Bool { !selectedItems.isEmpty || cleanAdobeHosts && hostsCleanupPlan != nil }
    var selectedOperationCount: Int { selectedItems.count + (cleanAdobeHosts && hostsCleanupPlan != nil ? 1 : 0) }
    var selectedHostsManagedBlockCount: Int {
        guard cleanAdobeHosts else { return 0 }
        return hostsCleanupPlan?.managedBlockCount ?? 0
    }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var selectedSizeText: String { ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file) }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var totalSizeText: String { ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file) }
    var isCreativeCloudOnlySelection: Bool {
        !cleanAdobeHosts && !selectedItems.isEmpty && selectedItems.allSatisfy { $0.scope == .creativeCloudInfrastructure }
    }
    var selectionIncludesOfficePDFMaker: Bool {
        selectedItems.contains {
            AdobeScanner.isAdobeOfficeAddInFilename(URL(fileURLWithPath: $0.path).lastPathComponent)
        }
    }
    var selectionRequiresFullDiskAccess: Bool {
        selectedItems.contains { cleanupService.requiresAppDataAuthorization(path: $0.path) }
    }
    var lastSessionWasCreativeCloudOnly: Bool {
        guard let session = lastSession, !session.items.isEmpty, session.hostsCleanup == nil else { return false }
        return session.items.allSatisfy { $0.scope == .creativeCloudInfrastructure }
    }
    var cleanupFraction: Double {
        guard cleanupTotal > 0 else { return 0 }
        return Double(cleanupCompleted) / Double(cleanupTotal)
    }
    var hasLog: Bool { lastLogURL != nil }
    var hasQuarantines: Bool { !quarantineRecords.isEmpty }
    var restorableQuarantineCount: Int { quarantineRecords.filter(\.hasRestorableContent).count }
    var lastQuarantineRecord: QuarantineRecord? {
        guard let lastSession else { return nil }
        return cleanupService.quarantineRecord(for: lastSession)
    }
    var canRestoreLastSession: Bool {
        !quarantinePermanentlyDeleted && (lastQuarantineRecord?.hasRestorableContent == true)
    }
    var domainCatalogVersion: String { AdobeDomainCatalog.current.version }
    var lastQuarantineBasePath: String {
        guard let path = lastSession?.quarantinePath else {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/AbeSweep/Quarantine", isDirectory: true)
                .path
        }
        return URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    func scan() {
        guard !isBusy else { return }
        phase = .scanning
        errorMessage = nil
        errorOffersFullDiskAccessSettings = false
        noticeMessage = nil
        Task {
            let result = await scanner.scan()
            items = result
            let hostsInspection = try? hostsFileService.inspect()
            hostsCleanupPlan = hostsInspection?.cleanupPlan
            unverifiedHostsCandidates = hostsInspection?.unverifiedCandidates ?? []
            malformedManagedHostsBlock = hostsInspection?.malformedManagedBlock ?? false
            cleanAdobeHosts = false
            applyPreset(.safe)
            phase = .results
            reviewAdobeDomains(force: false)
        }
    }

    func setAutomaticDomainReview(_ enabled: Bool) {
        automaticDomainReview = enabled
        UserDefaults.standard.set(enabled, forKey: "AbeSweepAutomaticDomainReview")
        if enabled { reviewAdobeDomains(force: false) }
    }

    func reviewAdobeDomains(force: Bool) {
        guard !isReviewingDomains else { return }
        if !force {
            guard automaticDomainReview else { return }
            if let data = UserDefaults.standard.data(forKey: "AbeSweepLastDomainReview"),
               let result = try? JSONDecoder().decode(DomainReviewResult.self, from: data),
               Date().timeIntervalSince(result.checkedAt) < 7 * 24 * 60 * 60 {
                return
            }
        }

        isReviewingDomains = true
        domainReviewMessage = L10n.text("Az Adobe hivatalos listájának ellenőrzése…", "Checking Adobe's official list…")
        Task {
            do {
                let result = try await domainReviewer.review()
                newOfficialDomainCandidates = result.newCandidates
                domainReviewMessage = reviewMessage(for: result)
                if let data = try? JSONEncoder().encode(result) {
                    UserDefaults.standard.set(data, forKey: "AbeSweepLastDomainReview")
                }
            } catch {
                domainReviewMessage = L10n.text(
                    "Az online felülvizsgálat most nem sikerült: \(error.localizedDescription)",
                    "Online review is currently unavailable: \(error.localizedDescription)"
                )
            }
            isReviewingDomains = false
        }
    }

    func openOfficialDomainSource() {
        NSWorkspace.shared.open(AdobeDomainCatalog.current.sourceURL)
    }

    func applyPreset(_ newPreset: SelectionPreset) {
        preset = newPreset
        switch newPreset {
        case .safe:
            selectedIDs = Set(items.filter { $0.category.defaultSelected }.map(\.id))
        case .creativeCloud:
            selectedIDs = Set(items.filter { $0.scope == .creativeCloudInfrastructure }.map(\.id))
        case .full:
            selectedIDs = Set(items.filter { $0.scope != .protectedUserContent }.map(\.id))
        case .custom:
            break
        }
    }

    func toggle(_ item: CleanupItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
        preset = .custom
    }

    func startCleanup() {
        guard !isBusy, disclaimerAccepted, hasSelectedOperation else { return }
        showingConfirmation = false
        errorMessage = nil
        errorOffersFullDiskAccessSettings = false
        noticeMessage = nil
        quarantinePermanentlyDeleted = false
        let selection = selectedItems
        let selectedHostsPlan = cleanAdobeHosts ? hostsCleanupPlan : nil
        let context: CleanupRunContext
        do {
            context = try CleanupRunContext.create(items: selection, hostsCleanup: selectedHostsPlan)
        } catch {
            errorMessage = L10n.text(
                "A napló nem hozható létre: \(error.localizedDescription)",
                "The log could not be created: \(error.localizedDescription)"
            )
            return
        }
        runContext = context
        lastLogURL = context.logURL
        cleanupCompleted = 0
        cleanupTotal = selection.count + (selectedHostsPlan == nil ? 0 : 1)
        cleanupCurrentPath = L10n.text("Rendszergazdai jóváhagyásra vár", "Waiting for administrator authorization")
        cleanupStage = "preparing"
        cancellationRequested = false
        phase = .cleaning
        startProgressMonitoring(context)

        Task {
            do {
                lastSession = try await cleanupService.quarantine(
                    selection,
                    hostsCleanup: selectedHostsPlan,
                    context: context
                )
                refreshQuarantineSessions()
                finishProgressMonitoring(context)
                phase = .complete
            } catch CleanupError.operationCancelled {
                finishProgressMonitoring(context)
                refreshQuarantineSessions()
                noticeMessage = L10n.text(
                    "A művelet megszakadt. A már áthelyezett elemek visszaálltak; a napló megtekinthető.",
                    "The operation was cancelled. Items already moved were restored; the log is available."
                )
                phase = .results
            } catch {
                finishProgressMonitoring(context)
                refreshQuarantineSessions()
                present(error)
                phase = .results
            }
        }
    }

    func cancelCleanup() {
        guard phase == .cleaning, let context = runContext, !cancellationRequested else { return }
        cancellationRequested = true
        cleanupCurrentPath = L10n.text(
            "Megszakítás kérése - visszaállítás következik…",
            "Requesting cancellation - rollback will follow…"
        )
        do {
            try Data().write(to: context.cancelURL, options: .atomic)
        } catch {
            errorMessage = L10n.text(
                "A megszakítás nem kezdeményezhető: \(error.localizedDescription)",
                "Cancellation could not be requested: \(error.localizedDescription)"
            )
            cancellationRequested = false
        }
    }

    func showLog() {
        guard let url = cleanupService.validatedLogURL(lastLogURL?.path) else { return }
        do {
            logContents = try String(contentsOf: url, encoding: .utf8)
            showingLog = true
        } catch {
            errorMessage = L10n.text(
                "A napló nem olvasható: \(error.localizedDescription)",
                "The log could not be read: \(error.localizedDescription)"
            )
        }
    }

    func acceptDisclaimer(suppressOnLaunch: Bool) {
        UserDefaults.standard.set(suppressOnLaunch, forKey: "AbeSweepSuppressDisclaimerOnLaunch")
        suppressDisclaimerOnLaunch = suppressOnLaunch
        disclaimerAccepted = true
        disclaimerRequiresAcceptance = false
        showingDisclaimer = false
    }

    func showDisclaimerManually() {
        disclaimerRequiresAcceptance = false
        showingDisclaimer = true
    }

    func openFullDiskAccessSettings() {
        refreshFullDiskAccessStatus()
        if fullDiskAccessStatus == .granted {
            fullDiskAccessConfirmationMessage = L10n.text(
                "Teljes lemezhozzáférés: rendben. Az AbeSweep eléri a macOS által védett hely ellenőrzőpontját; nem szükséges megnyitni a Rendszerbeállításokat.",
                "Full Disk Access: OK. AbeSweep can reach the protected macOS probe location, so System Settings does not need to be opened."
            )
            return
        }
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ].compactMap(URL.init(string:))

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }

    func refreshFullDiskAccessStatus() {
        fullDiskAccessStatus = fullDiskAccessChecker.status()
    }

    func dismissFullDiskAccessConfirmation() {
        fullDiskAccessConfirmationMessage = nil
    }

    func dismissError() {
        errorMessage = nil
        errorOffersFullDiskAccessSettings = false
    }

    func revealLogDirectory() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AbeSweep", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func revealLog() {
        guard let url = cleanupService.validatedLogURL(lastLogURL?.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealQuarantine() {
        guard let path = lastSession?.quarantinePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func showQuarantineManager() {
        guard !isBusy else { return }
        refreshQuarantineSessions()
        showingQuarantineManager = true
    }

    func manageQuarantine(_ record: QuarantineRecord) {
        guard !isBusy else { return }
        let session = record.session
        lastSession = session
        quarantinePermanentlyDeleted = false
        isPermanentlyDeletingQuarantine = false
        lastLogURL = cleanupService.validatedLogURL(session.logPath)
        showingQuarantineManager = false
        phase = .complete
    }

    func restoreLastSession() {
        guard !isBusy, let session = lastSession, canRestoreLastSession else { return }
        phase = .restoring
        errorMessage = nil
        restoreSuccessMessage = nil
        appendToLog(L10n.text(
            "VISSZAÁLLÍTÁS INDÍTVA | \(session.items.count) elem",
            "RESTORE STARTED | \(session.items.count) item(s)"
        ))
        Task {
            do {
                try await cleanupService.restore(session)
                appendToLog(L10n.text(
                    "VISSZAÁLLÍTÁS SIKERES | Az elemek visszakerültek az eredeti helyükre",
                    "RESTORE SUCCESSFUL | Items returned to their original locations"
                ))
                lastSession = nil
                refreshQuarantineSessions()
                phase = .welcome
                restoreSuccessMessage = L10n.text(
                    "Minden karanténba helyezett elem visszakerült az eredeti helyére. Szeretnél most új vizsgálatot indítani?",
                    "All quarantined items were returned to their original locations. Would you like to start a new scan now?"
                )
            } catch {
                appendToLog(L10n.text("VISSZAÁLLÍTÁSI HIBA", "RESTORE ERROR") + " | \(error.localizedDescription)")
                refreshQuarantineSessions()
                present(error)
                phase = .complete
            }
        }
    }

    func dismissRestoreSuccess() {
        restoreSuccessMessage = nil
    }

    func rescanAfterRestore() {
        restoreSuccessMessage = nil
        scan()
    }

    func permanentlyDeleteLastQuarantine() {
        guard !isBusy, let session = lastSession,
              !quarantinePermanentlyDeleted,
              !isPermanentlyDeletingQuarantine
        else { return }

        isPermanentlyDeletingQuarantine = true
        errorMessage = nil
        appendToLog(L10n.text("KARANTÉN VÉGLEGES TÖRLÉSE INDÍTVA", "PERMANENT QUARANTINE DELETION STARTED") + " | \(session.quarantinePath)")

        Task {
            do {
                try await cleanupService.permanentlyDeleteQuarantine(session)
                refreshQuarantineSessions()
                appendToLog(L10n.text(
                    "KARANTÉN VÉGLEGESEN TÖRÖLVE | A visszaállítás már nem lehetséges",
                    "QUARANTINE PERMANENTLY DELETED | Restore is no longer possible"
                ))
                completePermanentQuarantineDeletion()
            } catch {
                appendToLog(L10n.text("KARANTÉN TÖRLÉSI HIBA", "QUARANTINE DELETION ERROR") + " | \(error.localizedDescription)")
                present(error)
                isPermanentlyDeletingQuarantine = false
            }
        }
    }

    func completePermanentQuarantineDeletion() {
        lastSession = nil
        quarantinePermanentlyDeleted = false
        isPermanentlyDeletingQuarantine = false
        showingQuarantineManager = false
        noticeMessage = L10n.text(
            "A karantén véglegesen törölve. A napló megmaradt.",
            "The quarantine was permanently deleted. The log was retained."
        )
        phase = .welcome
    }

    private func refreshQuarantineSessions() {
        quarantineRecords = cleanupService.discoverQuarantineRecords()
    }

    private func startProgressMonitoring(_ context: CleanupRunContext) {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.readProgress(from: context.statusURL)
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func readProgress(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(CleanupProgressState.self, from: data)
        else { return }
        cleanupCompleted = state.completed
        cleanupTotal = state.total
        cleanupCurrentPath = state.currentPath
        cleanupStage = state.stage
    }

    private func finishProgressMonitoring(_ context: CleanupRunContext) {
        readProgress(from: context.statusURL)
        progressTask?.cancel()
        progressTask = nil
        runContext = nil
        try? FileManager.default.removeItem(at: context.directory)
    }

    private func appendToLog(_ message: String) {
        guard let url = cleanupService.validatedLogURL(lastLogURL?.path),
              let handle = try? FileHandle(forWritingTo: url)
        else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            let line = "\(Date().formatted(date: .numeric, time: .standard)) | \(message)\n"
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            return
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        if let cleanupError = error as? CleanupError,
           case .appDataAccessDenied = cleanupError {
            errorOffersFullDiskAccessSettings = true
        } else {
            errorOffersFullDiskAccessSettings = false
        }
    }

    private func reviewMessage(for result: DomainReviewResult) -> String {
        if result.newCandidates.isEmpty {
            return L10n.text(
                "A beépített lista egyezik az Adobe hivatalos domaincsaládjaival.",
                "The built-in list matches Adobe's official domain families."
            )
        }
        return L10n.text(
            "\(result.newCandidates.count) új hivatalos domaincsalád felülvizsgálatra vár; automatikus törlés nincs.",
            "\(result.newCandidates.count) new official domain family/families await review; nothing is removed automatically."
        )
    }
}
