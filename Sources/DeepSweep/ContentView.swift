import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showingHelp = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            switch model.phase {
            case .welcome:
                WelcomeView(
                    scan: model.scan,
                    showDisclaimer: model.showDisclaimerManually,
                    openFullDiskAccessSettings: model.openFullDiskAccessSettings,
                    fullDiskAccessStatus: model.fullDiskAccessStatus,
                    quarantineCount: model.quarantineRecords.count,
                    restorableQuarantineCount: model.restorableQuarantineCount,
                    noticeMessage: model.noticeMessage,
                    showQuarantines: model.showQuarantineManager
                )
            case .scanning:
                ProgressScreen(
                    title: L10n.text("Adobe-összetevők keresése…", "Scanning for Adobe components…"),
                    detail: L10n.text("Alkalmazások, szolgáltatások és rejtett maradványok ellenőrzése", "Checking applications, services, and hidden remnants")
                )
            case .results:
                ResultsView(model: model)
            case .cleaning:
                CleanupProgressView(model: model)
            case .restoring:
                ProgressScreen(
                    title: L10n.text("Az elemek visszaállítása…", "Restoring items…"),
                    detail: L10n.text("Az eredeti helyek és jogosultságok helyreállítása", "Restoring original locations and permissions")
                )
            case .complete:
                CompletionView(model: model)
            }
        }
        .alert(L10n.text("Nem sikerült befejezni", "Could Not Complete"), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.dismissError() } }
        )) {
            Button(L10n.text("Rendben", "OK"), role: .cancel) { model.dismissError() }
            if model.errorOffersFullDiskAccessSettings {
                Button(L10n.text("Teljes lemezhozzáférés megnyitása", "Open Full Disk Access")) {
                    model.openFullDiskAccessSettings()
                    model.dismissError()
                }
            }
        } message: {
            Text(model.errorMessage ?? L10n.text("Ismeretlen hiba", "Unknown error"))
        }
        .alert(L10n.text("Teljes lemezhozzáférés", "Full Disk Access"), isPresented: Binding(
            get: { model.fullDiskAccessConfirmationMessage != nil },
            set: { if !$0 { model.dismissFullDiskAccessConfirmation() } }
        )) {
            Button(L10n.text("Rendben", "OK"), role: .cancel) { model.dismissFullDiskAccessConfirmation() }
        } message: {
            Text(model.fullDiskAccessConfirmationMessage ?? "")
        }
        .alert(L10n.text("Sikeres visszaállítás", "Restore Successful"), isPresented: Binding(
            get: { model.restoreSuccessMessage != nil },
            set: { if !$0 { model.dismissRestoreSuccess() } }
        )) {
            Button(L10n.text("Később", "Later"), role: .cancel) { model.dismissRestoreSuccess() }
            Button(L10n.text("Új vizsgálat", "Rescan")) { model.rescanAfterRestore() }
        } message: {
            Text(model.restoreSuccessMessage ?? "")
        }
        .sheet(isPresented: $model.showingLog) {
            LogView(model: model)
        }
        .sheet(isPresented: $model.showingQuarantineManager) {
            QuarantineManagerView(model: model)
        }
        .sheet(isPresented: $model.showingDisclaimer) {
            DisclaimerView(
                requiresAcceptance: model.disclaimerRequiresAcceptance,
                initiallySuppressed: model.suppressDisclaimerOnLaunch,
                onAccept: model.acceptDisclaimer
            )
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .abeSweepShowHelp)) { _ in
            showingHelp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .abeSweepShowDisclaimer)) { _ in
            model.showDisclaimerManually()
        }
        .onReceive(NotificationCenter.default.publisher(for: .abeSweepOpenLogs)) { _ in
            model.revealLogDirectory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .abeSweepOpenFullDiskAccess)) { _ in
            model.openFullDiskAccessSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshFullDiskAccessStatus()
        }
    }
}

private struct BrandMark: View {
    var size: CGFloat = 58

    private var bundledIcon: NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let bundledIcon {
                Image(nsImage: bundledIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .purple.opacity(0.22), radius: 16, y: 7)
    }
}

private struct WelcomeView: View {
    let scan: () -> Void
    let showDisclaimer: () -> Void
    let openFullDiskAccessSettings: () -> Void
    let fullDiskAccessStatus: FullDiskAccessStatus
    let quarantineCount: Int
    let restorableQuarantineCount: Int
    let noticeMessage: String?
    let showQuarantines: () -> Void
    @State private var showingSecretSweep = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BrandMark(size: 76)
                .contentShape(Rectangle())
                .onTapGesture {
                    if SecretSweepTrigger.isActive(NSEvent.modifierFlags) {
                        showingSecretSweep = true
                    }
                }
            VStack(spacing: 10) {
                Text("AbeSweep")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text(L10n.text("Adobe-karbantartás és eltávolítás Macen", "Adobe maintenance and removal for Mac"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if let noticeMessage {
                Label(noticeMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .frame(maxWidth: 570)
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(symbol: "magnifyingglass", text: L10n.text("Megtalálja a rejtett háttérszolgáltatásokat és maradványokat", "Finds hidden background services and remnants"))
                FeatureRow(symbol: "checkmark.shield.fill", text: L10n.text("Elmagyarázza, mi távolítható el és milyen kockázattal", "Explains what can be removed and the associated risk"))
                FeatureRow(symbol: "arrow.uturn.backward.circle.fill", text: L10n.text("Karanténnal és lehetőség szerinti visszaállítással csökkenti a kockázatot", "Uses quarantine and best-effort restore to reduce risk"))
            }
            .padding(22)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 570)

            VStack(alignment: .leading, spacing: 10) {
                Label(
                    fullDiskAccessStatus == .granted
                        ? L10n.text("Teljes lemezhozzáférés: rendben", "Full Disk Access: OK")
                        : L10n.text(
                            "A teljes eltávolításhoz Teljes lemezhozzáférés szükséges",
                            "Full Disk Access is required for complete removal"
                        ),
                    systemImage: fullDiskAccessStatus == .granted ? "checkmark.shield.fill" : "externaldrive.badge.checkmark"
                )
                .font(.headline)
                .foregroundStyle(fullDiskAccessStatus == .granted ? .green : .indigo)

                Text(fullDiskAccessStatus == .granted
                    ? L10n.text(
                        "Az AbeSweep eléri a macOS védett ellenőrzőpontját; nincs további teendő.",
                        "AbeSweep can reach the protected macOS probe location; no further action is needed."
                    )
                    : L10n.text(
                        "1. Nyisd meg a beállítást.  2. Oldd fel a panelt, majd a + gombbal add hozzá az AbeSweep.app fájlt.  3. Kapcsold be mellette a hozzáférést.  4. Lépj ki az AbeSweepből, majd indítsd újra.",
                        "1. Open the setting.  2. Unlock the panel, then use + to add AbeSweep.app.  3. Turn on access beside it.  4. Quit AbeSweep, then open it again."
                    ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(
                        fullDiskAccessStatus == .granted
                            ? L10n.text("Hozzáférés ellenőrzése", "Check Access")
                            : L10n.text("Teljes lemezhozzáférés megnyitása…", "Open Full Disk Access…"),
                        action: openFullDiskAccessSettings
                    )
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    Text(L10n.text(
                        "A hitelesítés módját a macOS választja; támogatott esetben Touch ID-t is felajánlhat.",
                        "macOS chooses the authentication method and may offer Touch ID when supported."
                    ))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.indigo.opacity(0.25)))
            .frame(maxWidth: 570)

            Button(action: scan) {
                Label(L10n.text("Vizsgálat indítása", "Start Scan"), systemImage: "sparkle.magnifyingglass")
                    .font(.headline)
                    .frame(width: 230)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)

            if quarantineCount > 0 {
                Button(action: showQuarantines) {
                    Label(
                        L10n.text(
                            "Karanténbejegyzések kezelése (\(quarantineCount), ebből \(restorableQuarantineCount) visszaállítható)…",
                            "Manage Quarantine Records (\(quarantineCount), \(restorableQuarantineCount) restorable)…"
                        ),
                        systemImage: "archivebox"
                    )
                }
                .buttonStyle(.bordered)
            }

            Text(L10n.text("A vizsgálat nem módosít semmit. Nem hivatalos Adobe-termék.", "Scanning does not modify anything. Not an official Adobe product."))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button(L10n.text("Felelősségi tájékoztató", "Disclaimer"), action: showDisclaimer)
                .buttonStyle(.link)
                .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
        }
        .sheet(isPresented: $showingSecretSweep) {
            SecretSweepView()
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(.indigo)
                .font(.title3)
                .frame(width: 26)
            Text(text)
        }
    }
}

private struct ProgressScreen: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 20) {
            BrandMark(size: 64)
            ProgressView().controlSize(.large)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary)
        }
    }
}

private struct CleanupProgressView: View {
    @ObservedObject var model: AppModel

    private var stageTitle: String {
        switch model.cleanupStage {
        case "rollback": L10n.text("A módosítások visszaállítása…", "Rolling back changes…")
        case "cancelled": L10n.text("A művelet megszakadt", "Operation cancelled")
        default: L10n.text("A kijelölt elemek eltávolítása…", "Removing selected items…")
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            BrandMark(size: 64)
            Text(stageTitle).font(.title2.bold())

            VStack(spacing: 10) {
                ProgressView(value: model.cleanupFraction, total: 1)
                    .progressViewStyle(.linear)
                    .tint(model.cleanupStage == "rollback" ? .orange : .indigo)
                HStack {
                    Text("\(model.cleanupCompleted) / \(L10n.itemCount(model.cleanupTotal))")
                    Spacer()
                    Text(model.cleanupFraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 570)

            VStack(spacing: 7) {
                Text(model.cleanupStage == "preparing"
                    ? L10n.text("Állapot", "Status")
                    : L10n.text("Feldolgozás alatt", "Processing"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(URL(fileURLWithPath: model.cleanupCurrentPath).lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(model.cleanupCurrentPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .frame(maxWidth: 570)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))

            Button(role: .destructive, action: model.cancelCleanup) {
                Label(
                    model.cancellationRequested
                        ? L10n.text("Megszakítás és visszaállítás…", "Cancelling and rolling back…")
                        : L10n.text("Művelet megszakítása", "Cancel Operation"),
                    systemImage: "xmark.circle"
                )
            }
            .disabled(model.cancellationRequested || model.cleanupStage == "rollback")

            Text(L10n.text("Megszakításkor az AbeSweep visszagörgetést indít. Várd meg az eredményt; az esetleges ütközést jelzi.", "Cancellation starts rollback. Wait for the result; any conflicts will be reported."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(42)
    }
}

private struct ResultsView: View {
    @ObservedObject var model: AppModel
    @State private var showingDomainReviewInfo = false

    private var groupedItems: [(CleanupCategory, [CleanupItem])] {
        CleanupCategory.allCases.compactMap { category in
            let matches = model.items.filter { $0.category == category }
            return matches.isEmpty ? nil : (category, matches)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let notice = model.noticeMessage {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                    Text(notice)
                    Spacer()
                    Button(L10n.text("Napló", "Log"), action: model.showLog)
                        .disabled(!model.hasLog)
                }
                .foregroundStyle(.indigo)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(.indigo.opacity(0.08))
                Divider()
            }
            if model.items.isEmpty
                && model.hostsCleanupPlan == nil
                && model.unverifiedHostsCandidates.isEmpty
                && !model.malformedManagedHostsBlock {
                ContentUnavailableView(
                    L10n.text("Nem találtam Adobe-maradványt", "No Adobe Remnants Found"),
                    systemImage: "checkmark.seal.fill",
                    description: Text(L10n.text("A vizsgált rendszerterületek tiszták.", "The scanned system locations are clean."))
                )
            } else {
                HStack(spacing: 0) {
                    sidebar
                    Divider()
                    resultList
                }
            }
            Divider()
            footer
        }
        .sheet(isPresented: $model.showingConfirmation) {
            ConfirmationView(model: model)
        }
        .sheet(isPresented: $showingDomainReviewInfo) {
            DomainReviewInfoView()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            BrandMark(size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("Vizsgálati eredmény", "Scan Results")).font(.title2.bold())
                Text("\(L10n.itemCount(model.items.count)) • \(model.totalSizeText)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.text("Újra", "Rescan"), systemImage: "arrow.clockwise", action: model.scan)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("TAKARÍTÁSI MÓD", "CLEANUP MODE"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(SelectionPreset.allCases) { preset in
                Button {
                    model.applyPreset(preset)
                } label: {
                    HStack {
                        Image(systemName: model.preset == preset ? "largecircle.fill.circle" : "circle")
                        Text(preset.title)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.preset == preset ? Color.indigo : Color.primary)
            }
            Label(presetExplanation, systemImage: presetExplanationSymbol)
                .font(.caption)
                .foregroundStyle(.indigo)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Label(L10n.text("A piros jelölésű elemek személyes preseteket vagy más alkotói adatot tartalmazhatnak.", "Items marked in red may contain personal presets or other creative data."), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            domainReviewPanel
            Spacer()
        }
        .padding(22)
        .frame(width: 270)
        .background(.quaternary.opacity(0.22))
    }

    private var domainReviewPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(L10n.text("DOMAINADATBÁZIS", "DOMAIN DATABASE"), systemImage: "network")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(L10n.text("Ellenőrzött lista: \(model.domainCatalogVersion)", "Verified list: \(model.domainCatalogVersion)"))
                .font(.caption)
            Text(L10n.text(
                "Az ellenőrzés azért kell, mert az Adobe idővel új hálózati címeket vezethet be.",
                "This review is needed because Adobe may introduce new network addresses over time."
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Toggle(
                L10n.text("Heti automatikus ellenőrzés", "Automatic weekly review"),
                isOn: Binding(
                    get: { model.automaticDomainReview },
                    set: { model.setAutomaticDomainReview($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(.caption)
            Text(model.automaticDomainReview
                ? L10n.text(
                    "Bekapcsolva: legfeljebb hetente egyszer.",
                    "On: runs at most once per week."
                )
                : L10n.text(
                    "Alapból kikapcsolva; így nincs automatikus hálózati kérés.",
                    "Off by default; no automatic network request is made."
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("Ellenőrzés most", "Review Now")) {
                    model.reviewAdobeDomains(force: true)
                }
                .disabled(model.isReviewingDomains)
                if model.isReviewingDomains { ProgressView().controlSize(.small) }
            }
            if !model.domainReviewMessage.isEmpty {
                Text(model.domainReviewMessage)
                    .font(.caption2)
                    .foregroundStyle(model.newOfficialDomainCandidates.isEmpty ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.newOfficialDomainCandidates.isEmpty {
                Text(model.newOfficialDomainCandidates.joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
            Button(L10n.text("Hivatalos Adobe-forrás", "Official Adobe Source")) {
                model.openOfficialDomainSource()
            }
            .buttonStyle(.link)
            .font(.caption2)
            Button(L10n.text("Mit ellenőriz? Adatvédelem", "What Is Checked? Privacy")) {
                showingDomainReviewInfo = true
            }
            .buttonStyle(.link)
            .font(.caption2)
        }
    }

    private var presetExplanation: String {
        switch model.preset {
        case .safe:
            L10n.text("Csak gyorsítótárakat és naplókat jelöl ki. Alkalmazást és beállítást nem távolít el.", "Selects only caches and logs. Applications and settings are not removed.")
        case .creativeCloud:
            L10n.text("A Creative Cloud újratelepíthető összetevőit jelöli ki. Az Adobe-appok és a személyes felhőtartalom megmaradnak.", "Selects reinstallable Creative Cloud components. Adobe apps and personal cloud content are preserved.")
        case .full:
            L10n.text("Minden felismert Adobe-összetevőt kijelöl, de a védett személyes tartalmat megőrzi.", "Selects every recognized Adobe component while preserving protected personal content.")
        case .custom:
            L10n.text("Kizárólag a kézzel kijelölt elemek kerülnek karanténba.", "Only manually selected items are placed in quarantine.")
        }
    }

    private var presetExplanationSymbol: String {
        switch model.preset {
        case .safe: "bolt.horizontal.circle.fill"
        case .creativeCloud: "arrow.clockwise.circle.fill"
        case .full: "shippingbox.fill"
        case .custom: "checklist"
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                if let hostsPlan = model.hostsCleanupPlan {
                    HostsCleanupRow(
                        plan: hostsPlan,
                        selected: model.cleanAdobeHosts,
                        toggle: { model.cleanAdobeHosts.toggle() }
                    )
                }
                if model.malformedManagedHostsBlock {
                    MalformedHostsBlockRow()
                }
                if !model.unverifiedHostsCandidates.isEmpty {
                    HostsCandidateRow(
                        hostnames: model.unverifiedHostsCandidates,
                        hasCleanableEntries: model.hostsCleanupPlan != nil
                    )
                }
                ForEach(groupedItems, id: \.0) { category, items in
                    VStack(spacing: 0) {
                        HStack {
                            Label(category.title, systemImage: category.symbol)
                                .font(.headline)
                                .foregroundStyle(category.tint)
                            Spacer()
                            Text(L10n.itemCount(items.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(category.tint.opacity(0.08))

                        ForEach(items) { item in
                            ItemRow(item: item, selected: model.selectedIDs.contains(item.id)) {
                                model.toggle(item)
                            }
                            if item.id != items.last?.id { Divider().padding(.leading, 52) }
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
                }
            }
            .padding(22)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(L10n.selectedCount(model.selectedOperationCount)) • \(model.selectedSizeText)")
                .fontWeight(.medium)
            Spacer()
            if model.hasLog {
                Button(L10n.text("Legutóbbi napló", "Latest Log"), systemImage: "doc.text", action: model.showLog)
            }
            if model.hasQuarantines {
                Button(
                    L10n.text(
                        "Karanténbejegyzések (\(model.quarantineRecords.count))…",
                        "Quarantine Records (\(model.quarantineRecords.count))…"
                    ),
                    systemImage: "archivebox",
                    action: model.showQuarantineManager
                )
            }
            Button(L10n.text("Eltávolítás…", "Remove…")) { model.showingConfirmation = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.indigo)
                .disabled(!model.hasSelectedOperation)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

private struct QuarantineManagerView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("AbeSweep-karanténok", "AbeSweep Quarantines"))
                        .font(.title2.bold())
                    Text(L10n.text(
                        "A lista a ténylegesen visszaállítható adatot és a csak jegyzékként megmaradt munkameneteket is megkülönbözteti",
                        "The list distinguishes actually restorable data from sessions that remain only as records"
                    ))
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)
            Divider()

            if model.quarantineRecords.isEmpty {
                ContentUnavailableView(
                    L10n.text("Nincs megőrzött karantén", "No Saved Quarantine"),
                    systemImage: "archivebox",
                    description: Text(L10n.text(
                        "Nincs visszaállítható vagy végleg törölhető AbeSweep-munkamenet.",
                        "There is no AbeSweep session available to restore or permanently delete."
                    ))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.quarantineRecords) { record in
                            let session = record.session
                            HStack(spacing: 14) {
                                Image(systemName: record.hasRestorableContent ? "shippingbox.fill" : "doc.text.magnifyingglass")
                                    .font(.title2)
                                    .foregroundStyle(record.hasRestorableContent ? .orange : .secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)
                                    if record.hasRestorableContent {
                                        Label(
                                            L10n.text(
                                                "\(record.restorableItemCount) ténylegesen visszaállítható elem",
                                                "\(record.restorableItemCount) actually restorable item(s)"
                                            ),
                                            systemImage: "arrow.uturn.backward.circle.fill"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                    } else {
                                        Label(
                                            L10n.text(
                                                "Csak jegyzék/naplóhivatkozás maradt – nincs visszaállítható fájl",
                                                "Record/log reference only — no files can be restored"
                                            ),
                                            systemImage: "exclamationmark.triangle.fill"
                                        )
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                    }
                                    Text(session.quarantinePath)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Button(L10n.text("Kezelés…", "Manage…")) {
                                    model.manageQuarantine(record)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)
                            }
                            .padding(15)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))
                        }
                    }
                    .padding(20)
                }
            }

            Divider()
            HStack {
                Text(L10n.text(
                    "A jegyzék önmagában nem karanténmásolat: visszaállítás csak akkor érhető el, ha a tényleges fájlok is megvannak.",
                    "A record alone is not a quarantine copy: restore is available only while the actual files are present."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Bezárás", "Close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 720, height: 520)
    }
}

private struct HostsCandidateRow: View {
    let hostnames: [String]
    let hasCleanableEntries: Bool

    private var displayedHostnames: [String] { Array(hostnames.prefix(12)) }
    private var hiddenCount: Int { max(0, hostnames.count - displayedHostnames.count) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "questionmark.diamond.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("Új, még nem ellenőrzött Adobe-domainjelölt", "New, unverified Adobe domain candidate"))
                    .font(.headline)
                Text(L10n.text(
                    "A hosts fájlban \(hostnames.count) Adobe-nak tűnő, de az ellenőrzött adatbázisban még nem szereplő gépnév található. Az AbeSweep ezeket szándékosan nem távolítja el automatikusan, mert köztük más szolgáltatók címei is lehetnek.",
                    "The hosts file contains \(hostnames.count) Adobe-looking hostname(s) not yet present in the verified database. AbeSweep intentionally does not remove them automatically because they may include addresses belonging to other providers."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(hasCleanableEntries
                    ? L10n.text(
                        "Az ellenőrzött találatok külön, kijelölhető Hosts fájl kitakarítása sorban láthatók. Az alábbi jelöltek nem részei annak a műveletnek.",
                        "Verified matches appear separately in the selectable Clean Hosts File row. The candidates below are not part of that operation."
                    )
                    : L10n.text(
                        "Nincs biztonságosan eltávolítható hosts-találat, ezért a program nem módosítja a fájlt. Jelölők nélkül egy külső tiltólista teljes tartalmát sem tekinti automatikusan Adobe-tulajdonúnak.",
                        "There is no safely removable hosts match, so the app will not modify the file. Without markers, it does not automatically treat an entire third-party block list as Adobe-owned."
                    ))
                    .font(.caption.bold())
                    .foregroundStyle(hasCleanableEntries ? Color.secondary : Color.orange)
                Text(displayedHostnames.joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                if hiddenCount > 0 {
                    Text(L10n.text(
                        "Az első 12 cím látható; további \(hiddenCount) jelölt elrejtve.",
                        "Showing the first 12 addresses; \(hiddenCount) more candidate(s) hidden."
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.orange.opacity(0.35)))
    }
}

private struct DomainReviewInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(
                L10n.text("Adobe-domainellenőrzés és adatvédelem", "Adobe Domain Review and Privacy"),
                systemImage: "hand.raised.fill"
            )
            .font(.title2.bold())
            .foregroundStyle(.indigo)

            Text(L10n.text(
                "Miért szükséges? Az Adobe termékei és hálózati végpontjai változhatnak. Az AbeSweep időnként összeveti a beépített, kézzel ellenőrzött domaincsaládokat az Adobe nyilvános hivatalos végpontoldalával. Az új címeket csak felülvizsgálatra jelzi: nem kezdi el őket automatikusan törölni.",
                "Why is it needed? Adobe products and network endpoints can change. AbeSweep occasionally compares its built-in, manually verified domain families with Adobe's public official endpoint page. New addresses are only flagged for review; they are never removed automatically."
            ))

            Text(L10n.text(
                "Mit tölt le? Egy szokásos HTTPS-kéréssel kizárólag az Adobe hivatalos, nyilvános domainoldalát. A webkiszolgáló a normál internetkapcsolat részeként láthatja az IP-címet és az AbeSweep nevét tartalmazó technikai kérésazonosítót.",
                "What is downloaded? Only Adobe's official public domain page, using a normal HTTPS request. As part of an ordinary internet connection, the web server can see the IP address and a technical request identifier containing the AbeSweep name."
            ))

            Text(L10n.text(
                "Mi nem hagyja el a Macet? A hosts fájl tartalma, a talált fájlok és útvonalak, a naplók, a karantén, az Adobe-fiók adatai és más személyes adat nem kerül feltöltésre. Helyben csak az ellenőrzés időpontja, a nyilvános domainlista eredménye és az esetleges új jelöltek tárolódnak. Az automatikus heti ellenőrzés bármikor kikapcsolható.",
                "What never leaves the Mac? The hosts file, discovered files and paths, logs, quarantine, Adobe account data, and other personal data are not uploaded. Only the review time, results from the public domain list, and any new candidates are stored locally. Automatic weekly review can be turned off at any time."
            ))

            Spacer()
            HStack {
                Spacer()
                Button(L10n.text("Bezárás", "Close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .padding(28)
        .frame(width: 610, height: 470)
    }
}

private struct MalformedHostsBlockRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("Hiányos Adobe-blokkjelölés", "Incomplete Adobe Block Markers"))
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(L10n.text(
                    "Az AbeSweep Ruddernation-blokkjelölőt talált, de a kezdő és záró jelölők nem alkotnak szabályos párt. Biztonsági okból a hosts fájl nem választható ki. Javítsd vagy állítsd vissza kézzel a blokkot, majd indíts új vizsgálatot.",
                    "AbeSweep found a Ruddernation block marker, but the start and end markers do not form a valid pair. For safety, the hosts file cannot be selected. Repair or manually restore the block, then start a new scan."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.red.opacity(0.35)))
    }
}

private struct HostsCleanupRow: View {
    let plan: HostsCleanupPlan
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(L10n.text("Opcionális rendszerbeállítás", "Optional system setting"), systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Text("/etc/hosts")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.orange.opacity(0.08))

            Button(action: toggle) {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.orange : Color.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.text("Hosts fájl kitakarítása", "Clean Hosts File"))
                            .fontWeight(.medium)
                        Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(detailText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.orange.opacity(0.35)))
    }

    private var description: String {
        if plan.managedBlockCount > 0 {
            return L10n.text(
                "Alapból nincs kijelölve. Felismert \(plan.managedBlockCount) Ruddernation Adobe-blokkot \(plan.managedBlockEntryCount) bejegyzéssel; a pontos jelölők közötti teljes blokkot és a külön megtalált ellenőrzött Adobe-bejegyzéseket eltávolítja. Az eredeti hosts fájl a karanténban marad.",
                "Off by default. Found \(plan.managedBlockCount) Ruddernation Adobe block(s) containing \(plan.managedBlockEntryCount) entries; the complete content between exact markers and separately found verified Adobe entries will be removed. The original hosts file remains in quarantine."
            )
        }
        return L10n.text(
            "Alapból nincs kijelölve. Csak az ellenőrzött Adobe-doménekhez tartozó \(plan.matchedHostnames.count) gépnevet távolítja el; az eredetit a karanténban megőrzi.",
            "Off by default. Removes only \(plan.matchedHostnames.count) hostname(s) belonging to verified Adobe domains and keeps the original in quarantine."
        )
    }

    private var detailText: String {
        if plan.managedBlockCount > 0 {
            return L10n.text(
                "Ruddernation jelölt blokk: \(plan.managedBlockEntryCount) bejegyzés",
                "Ruddernation marked block: \(plan.managedBlockEntryCount) entries"
            )
        }
        return plan.matchedHostnames.joined(separator: ", ")
    }
}

private struct ItemRow: View {
    let item: CleanupItem
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.indigo : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(item.displayName).fontWeight(.medium)
                        Text(item.risk.label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(item.risk.color.opacity(0.13), in: Capsule())
                            .foregroundStyle(item.risk.color)
                        if item.scope == .creativeCloudInfrastructure {
                            Text("Creative Cloud")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.indigo.opacity(0.12), in: Capsule())
                                .foregroundStyle(.indigo)
                        }
                    }
                    Text(item.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(item.formattedSize)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ConfirmationView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var acceptedRisk = false
    @State private var showingDisclaimer = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.indigo)
                    Text(L10n.text("Eltávolításra kész", "Ready to Remove")).font(.title2.bold())
                    Text(confirmationMessage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 440)
                    if model.isCreativeCloudOnlySelection {
                        Label(L10n.text("A Photoshop és a többi Adobe-alkalmazás megmarad, de az újratelepítésig nem biztos, hogy elindul.", "Photoshop and other Adobe applications are preserved, but may not launch until Creative Cloud is reinstalled."), systemImage: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.indigo)
                            .padding(12)
                            .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if model.selectedItems.contains(where: { $0.scope == .protectedUserContent }) {
                        Label(L10n.text("A kijelölés személyes Adobe-adatot is tartalmazhat.", "The selection may contain personal Adobe data."), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .padding(12)
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if model.selectionIncludesOfficePDFMaker {
                        Label(
                            L10n.text(
                                "Adobe PDFMaker Office-bővítmény is eltávolításra kerül. Mentsd el a munkádat: a Word, az Excel és a PowerPoint bezáródhat.",
                                "An Adobe PDFMaker Office add-in will also be removed. Save your work: Word, Excel, and PowerPoint may close."
                            ),
                            systemImage: "doc.badge.gearshape"
                        )
                        .foregroundStyle(.orange)
                        .padding(12)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if model.selectionRequiresFullDiskAccess {
                        VStack(alignment: .leading, spacing: 9) {
                            if model.fullDiskAccessStatus == .granted {
                                Label(
                                    L10n.text(
                                        "A kijelölés védett Adobe-adatot tartalmaz, és a Teljes lemezhozzáférés ellenőrzése rendben van.",
                                        "The selection contains protected Adobe data, and the Full Disk Access check is OK."
                                    ),
                                    systemImage: "checkmark.shield.fill"
                                )
                                .foregroundStyle(.green)
                            } else {
                                Label(
                                    L10n.text(
                                        "A kijelölés védett Adobe-alkalmazásadatot tartalmaz. Az eltávolításhoz add hozzá az AbeSweepet a macOS Teljes lemezhozzáférés listájához, majd indítsd újra az alkalmazást.",
                                        "The selection contains protected Adobe application data. To remove it, add AbeSweep to macOS Full Disk Access, then restart the application."
                                    ),
                                    systemImage: "externaldrive.badge.checkmark"
                                )
                                Button(L10n.text("Teljes lemezhozzáférés beállítása…", "Grant Full Disk Access…")) {
                                    model.openFullDiskAccessSettings()
                                }
                                .buttonStyle(.link)
                            }
                        }
                        .padding(12)
                        .background((model.fullDiskAccessStatus == .granted ? Color.green : Color.indigo).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: 455, alignment: .leading)
                    }
                    if model.cleanAdobeHosts {
                        Label(
                            model.selectedHostsManagedBlockCount > 0
                                ? L10n.text(
                                    "A hosts fájl módosításához rendszergazdai jóváhagyás szükséges. A pontos Ruddernation-jelölők közötti teljes blokk — külső szolgáltatói címeivel együtt — eltávolításra kerül. Az eredeti fájlt a karantén őrzi.",
                                    "Modifying the hosts file requires administrator approval. The complete content between exact Ruddernation markers — including third-party service addresses — will be removed. The original file is kept in quarantine."
                                )
                                : L10n.text(
                                    "A hosts fájl módosításához rendszergazdai jóváhagyás szükséges. Az AbeSweep csak a felsorolt, ellenőrzött Adobe-gépneveket távolítja el, az eredeti fájlt pedig a karanténban őrzi.",
                                    "Modifying the hosts file requires administrator approval. AbeSweep removes only the listed, verified Adobe hostnames and keeps the original file in quarantine."
                                ),
                            systemImage: "lock.shield.fill"
                        )
                        .foregroundStyle(.orange)
                        .padding(12)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: 455, alignment: .leading)
                    }
                    Toggle(isOn: $acceptedRisk) {
                        Text(L10n.text(
                            "Átnéztem a kijelölt elemeket, van naprakész biztonsági mentésem, és értem, hogy a művelet alkalmazások működését befolyásolhatja.",
                            "I reviewed the selected items, have an up-to-date backup, and understand that this operation may affect application functionality."
                        ))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: 455, alignment: .leading)

                    Button(L10n.text("Felelősségi tájékoztató megtekintése", "View Disclaimer")) {
                        showingDisclaimer = true
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
            }

            Divider()
            HStack {
                Button(L10n.text("Mégse", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.text("Eltávolítás és karantén", "Remove and Quarantine")) { model.startCleanup() }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(!acceptedRisk)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .frame(width: 560, height: 570)
        .sheet(isPresented: $showingDisclaimer) {
            DisclaimerView(
                requiresAcceptance: false,
                initiallySuppressed: model.suppressDisclaimerOnLaunch,
                onAccept: { suppressOnLaunch in
                    model.acceptDisclaimer(suppressOnLaunch: suppressOnLaunch)
                    showingDisclaimer = false
                }
            )
        }
    }

    private var confirmationMessage: String {
        if model.isCreativeCloudOnlySelection {
            return L10n.text(
                "\(model.selectedItems.count) Creative Cloud-összetevő (\(model.selectedSizeText)) kikerül az aktív rendszerből. A felhőfájlok, presetek és telepített Adobe-alkalmazások érintetlenek maradnak.",
                "\(model.selectedItems.count) Creative Cloud component(s) (\(model.selectedSizeText)) will be removed from the active system. Cloud files, presets, and installed Adobe applications remain untouched."
            )
        }
        if model.selectedItems.isEmpty && model.cleanAdobeHosts {
            return L10n.text(
                "A kijelölt Adobe-bejegyzések kikerülnek a /etc/hosts fájlból. Az eredeti hosts fájl visszaállítható másolata a karanténba kerül.",
                "The selected Adobe entries will be removed from /etc/hosts. A restorable copy of the original hosts file will be stored in quarantine."
            )
        }
        if model.cleanAdobeHosts {
            return L10n.text(
                "\(model.selectedOperationCount) elem (\(model.selectedSizeText)) érintett. Az alkalmazásfájlok és az eredeti hosts fájl visszaállítható karanténba kerülnek.",
                "\(model.selectedOperationCount) item(s) (\(model.selectedSizeText)) are affected. Application files and the original hosts file will be placed in restorable quarantine."
            )
        }
        return L10n.text(
            "\(model.selectedItems.count) elem (\(model.selectedSizeText)) kikerül az aktív rendszerből. Az érintett alkalmazások bezáródnak, a fájlok pedig visszaállítható karanténba kerülnek.",
            "\(model.selectedItems.count) item(s) (\(model.selectedSizeText)) will be removed from the active system. Affected applications will close and the files will be placed in a restorable quarantine."
        )
    }
}

private struct DisclaimerView: View {
    let requiresAcceptance: Bool
    let onAccept: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    @State private var suppressOnLaunch: Bool

    init(
        requiresAcceptance: Bool,
        initiallySuppressed: Bool,
        onAccept: @escaping (Bool) -> Void
    ) {
        self.requiresAcceptance = requiresAcceptance
        self.onAccept = onAccept
        _suppressOnLaunch = State(initialValue: initiallySuppressed)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text(DisclaimerCopy.title).font(.title2.bold())
                    Text(L10n.text("Kérjük, olvasd el az AbeSweep használata előtt.", "Please read this before using AbeSweep."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(DisclaimerCopy.introduction)
                    disclaimerSection(L10n.text("Hogyan működik", "How It Works"), DisclaimerCopy.operation)
                    disclaimerSection(L10n.text("Teljes lemezhozzáférés", "Full Disk Access"), DisclaimerCopy.fullDiskAccess)
                    disclaimerSection(L10n.text("Online ellenőrzés és adatvédelem", "Online Review and Privacy"), DisclaimerCopy.privacy)
                    disclaimerSection(L10n.text("Kockázatok és előkészületek", "Risks and Preparation"), DisclaimerCopy.risk)
                    disclaimerSection(L10n.text("Felelősség", "Liability"), DisclaimerCopy.liability)
                    disclaimerSection(L10n.text("Védjegyek", "Trademarks"), DisclaimerCopy.trademarks)
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Divider()
            VStack(spacing: 14) {
                if requiresAcceptance {
                    Toggle(L10n.text("Elolvastam és megértettem a tájékoztatót.", "I have read and understood this notice."), isOn: $confirmed)
                        .toggleStyle(.checkbox)
                }
                Toggle(L10n.text("Ne jelenjen meg automatikusan a következő indításkor.", "Do not show automatically on the next launch."), isOn: $suppressOnLaunch)
                    .toggleStyle(.checkbox)
                HStack {
                    if requiresAcceptance {
                        Button(L10n.text("Nem fogadom el", "Decline")) { NSApplication.shared.terminate(nil) }
                    }
                    Spacer()
                    Button(requiresAcceptance
                        ? L10n.text("Elfogadom és folytatom", "Accept and Continue")
                        : L10n.text("Beállítás mentése és bezárás", "Save Setting and Close")) {
                        onAccept(suppressOnLaunch)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(requiresAcceptance && !confirmed)
                }
            }
            .padding(18)
        }
        .frame(minWidth: 700, minHeight: 650)
        .interactiveDismissDisabled(requiresAcceptance)
    }

    private func disclaimerSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(body).foregroundStyle(.secondary)
        }
    }
}

private struct HelpSectionCopy {
    let title: String
    let body: String
}

private struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                BrandMark(size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(helpTitle).font(.title2.bold())
                    Text(helpSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(helpSections.enumerated()), id: \.offset) { _, section in
                        helpSection(section.title, section.body)
                    }

                    Label(warningText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .padding(14)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Divider()
            HStack {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(closeButtonTitle) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 740, minHeight: 650)
    }

    private var helpTitle: String {
        L10n.text("AbeSweep súgó", "AbeSweep Help")
    }

    private var helpSubtitle: String {
        L10n.text(
            "Útmutató az Adobe-összetevők átvizsgálásához és eltávolításához",
            "Guide to scanning for and removing Adobe components"
        )
    }

    private var helpSections: [HelpSectionCopy] {
        switch L10n.language {
        case .hungarian:
            return [
                HelpSectionCopy(
                    title: "1. Vizsgálat",
                    body: "A Vizsgálat indítása nem módosítja a rendszert. Az AbeSweep Adobe-alkalmazásokat, az /Applications/Utilities mappába telepített Adobe-segédprogramokat és telepítőmappákat, háttérszolgáltatásokat, közös összetevőket, beállításokat, gyorsítótárakat, naplókat és felhasználói adatokat keres. A Containers, Group Containers és Application Scripts helyeken a com.adobe azonosítókat és az Adobe csapatazonosítójával kiegészített változataikat is felismeri. A teljes eltávolítás a bizonyíthatóan Adobe-eredetű Photoshop-, InDesign- és más termékpreferenciákat, valamint az Adobe-gyökér alatti Device State adatokat is felismeri; ezek korábbi munkameneteket, legutóbbi fájlokat vagy személyes preseteket őrizhetnek, ezért piros figyelmeztetéssel jelennek meg. Az Újra gomb az előző művelet befejezése után friss vizsgálatot indít. Ha egy CoreSync-mappa tartalma nem olvasható, az AbeSweep kihagyja a teljes mappát; szükség esetén ellenőrizd a Teljes lemezhozzáférést."
                ),
                HelpSectionCopy(
                    title: "2. Takarítási módok",
                    body: "A Csak ideiglenes fájlok kizárólag újragenerálható gyorsítótárakat és naplókat jelöl ki. A Csak Creative Cloud a Creative Cloud helyi infrastruktúráját távolítja el egy tiszta újratelepítés előkészítéséhez; az Adobe-alkalmazások és a védett személyes felhőtartalom megmaradnak. A Teljes Adobe-eltávolítás minden felismert Adobe-összetevőt kijelöl, a védett személyes tartalom kivételével. Az Egyéni kijelölésben te döntesz minden elemről."
                ),
                HelpSectionCopy(
                    title: "3. Eredmények és kockázati jelölések",
                    body: "Minden találatnál látható a fájl vagy mappa neve, útvonala, mérete, kategóriája, az eltávolítás oka és a kockázati szint. A piros figyelmeztetés azt jelzi, hogy az elem személyes beállítást, presetet vagy más alkotói adatot tartalmazhat. A kijelölést az eltávolítás előtt kézzel módosíthatod."
                ),
                HelpSectionCopy(
                    title: "4. Eltávolítás és folyamatjelzés",
                    body: "Az AbeSweep megerősítést és szükség esetén macOS-rendszergazdai engedélyt kér. Az eltávolítás előtt felismeri a futó Adobe-alkalmazásokat és az olyan Creative Cloud-háttérfolyamatokat, mint a CCXProcess és a CoreSync. Szabályos bezárást kér, és nem kényszeríti a szerkesztőprogramok leállítását. Ha egy alkalmazás nyitva marad, például mentési ablakot mutat, a takarítás leáll. Mentsd el a munkádat, zárd be az alkalmazást, majd próbáld újra. A kijelölt és biztonságosan ellenőrzött Adobe-indítási szolgáltatásokat rendszergazdai engedéllyel megkísérli leállítani. A nem leállítható háttérfolyamatokat a napló jelzi. Ezek az események bekerülnek a naplóba. A folyamatjelző mutatja az elkészült elemek arányát és az éppen feldolgozott fájl útvonalát. A kijelölt elemek először nem véglegesen törlődnek, hanem visszaállítható karanténba kerülnek."
                ),
                HelpSectionCopy(
                    title: "5. Teljes lemezhozzáférés",
                    body: "A macOS a más alkalmazásokhoz tartozó Containers és Group Containers adatokat külön védi, ezért a teljes eltávolításhoz Teljes lemezhozzáférés szükséges lehet. Az AbeSweep egy védett macOS-ellenőrzőpont megnyitásával, a fájl tartalmának elolvasása vagy megőrzése nélkül vizsgálja az állapotot. Ha a hozzáférés már működik, zöld Rendben jelzést ad, és a gomb nem nyitja meg a Rendszerbeállításokat. Ha nincs engedély vagy az állapot nem ellenőrizhető, a gomb az Adatvédelem és biztonság > Teljes lemezhozzáférés panelre visz. Ott add hozzá az AbeSweep.app fájlt, kapcsold be mellette az engedélyt, majd teljesen lépj ki az AbeSweepből és indítsd újra. A jogosultságot és a hitelesítés módját a macOS kezeli: támogatott, beállított gépen Touch ID-t is felajánlhat, de az AbeSweep ezt nem tudja kikényszeríteni, és nem tud saját magának hozzáférést adni."
                ),
                HelpSectionCopy(
                    title: "6. Megszakítás",
                    body: "A Művelet megszakítása gombbal leállíthatod a folyamatban lévő eltávolítást. Az AbeSweep ilyenkor megkísérli visszahelyezni a már karanténba mozgatott elemeket az eredeti helyükre. Ha a cél közben újra létrejött vagy az útvonal megváltozott, nem írja felül: hibát jelez, és a megmaradt karanténadatokat megőrzi. Ellenőrizd a naplót és a karanténbejegyzéseket. Várd meg a visszagörgetés végét; módosítás közben a szabályos kilépés nem engedélyezett."
                ),
                HelpSectionCopy(
                    title: "7. Karantén, napló és visszaállítás",
                    body: "A karantén a ~/Library/Application Support/AbeSweep/Quarantine mappában őrzi az eltávolított elemeket, ezért azok addig továbbra is foglalnak lemezterületet. A Karanténbejegyzések kezelése lista újraindítás után is megmutatja a munkameneteket, de külön megszámolja a ténylegesen még meglévő visszaállítható fájlokat. A „Csak jegyzék/naplóhivatkozás maradt” figyelmeztetés azt jelenti, hogy az eredeti fájlok már nincsenek a karanténban: ez a bejegyzés önmagában nem biztonsági másolat, és nem állítható vissza. A részletes napló külön, a ~/Library/Logs/AbeSweep mappában marad. A korábbi AbeSweep-verziók /Users/Shared alatti karanténjai továbbra is támogatottak. A Visszaállítás csak a ténylegesen még meglévő karanténelemeknél érhető el. Hiányzó hosts-mentés esetén a többi meglévő elem továbbra is visszaállítható; hiányzó adatot az AbeSweep nem tud pótolni. A sikeres visszaállítás után új vizsgálat indítható. A ki nem jelölt üres szülőmappák megmaradhatnak, így az eredeti jogosultságaik is megőrződnek."
                ),
                HelpSectionCopy(
                    title: "8. Karantén végleges törlése",
                    body: "Csak akkor használd, amikor már ellenőrizted, hogy a rendszer és a szükséges Adobe-alkalmazások megfelelően működnek. A külön megerősítés után az AbeSweep újraellenőrzi a karantén útvonalát és a mappa azonosságát, majd végleg törli az adott karantén tartalmát, így felszabadul a lemezterület. Ez a művelet nem vonható vissza, és utána nincs lehetőség visszaállításra. A napló nem törlődik, továbbra is megtekinthető."
                ),
                HelpSectionCopy(
                    title: "9. Adobe PDFMaker és Microsoft Office",
                    body: "Az Acrobat PDFMaker Word-, Excel- és PowerPoint-bővítményeket telepíthet a Microsoft Office indítási mappáiba. Ha az Acrobat keretrendszere eltűnik, de ezek a bővítmények megmaradnak, az Office Visual Basic fájlhiányt jelezhet. A Teljes Adobe-eltávolítás felismeri és karanténba helyezi a PDFMaker-bővítményeket is. Mentsd el az Office-dokumentumokat, mert az érintett Office-alkalmazások bezáródhatnak."
                ),
                HelpSectionCopy(
                    title: "10. Opcionális hosts-takarítás",
                    body: "A funkció neve Hosts fájl kitakarítása, angolul Clean Hosts File. Ha a /etc/hosts fájl Adobe-doménekhez tartozó egyedi bejegyzéseket tartalmaz, az opció külön és alapból kikapcsolva jelenik meg. Az AbeSweep csak ellenőrzött Adobe-gépneveket távolít el. Ha megtalálja a Ruddernation Adobe URL Block List pontos ADOBE_BLOCKLIST_START és ADOBE_BLOCKLIST_END jelölőit, a közöttük lévő teljes blokkot külön, felismert egységként tudja eltávolítani; magát a közösségi listát nem tölti le és nem építi be. Jelölők nélküli külső tiltólistánál az ismeretlen vagy más szolgáltatóhoz tartozó címeket csak jelzi, nem törli. Nagy lista esetén a felület csak az első 12 jelöltet írja ki és megmutatja a továbbiak számát. Ha nincs ellenőrzött találat, egyértelműen jelzi, hogy nem fogja módosítani a fájlt. Hiányos vagy hibás jelölőpárnál szintén leáll. Az eredeti hosts fájlt a karantén őrzi. A takarítás megőrzi a fájl jogosultságait; a csere előtt ismét ellenőrzi a tartalmat, és észlelt változásnál leáll. A hosts fájlt a művelet alatt ne szerkeszd másik programmal."
                ),
                HelpSectionCopy(
                    title: "11. Adobe-domainellenőrzés és adatvédelem",
                    body: "Az alkalmazásfrissítés ellenőrzése a macadmin.hu frissítési kiszolgálójához kapcsolódik; a rendszerprofil-küldés ki van kapcsolva. Ettől külön az Adobe idővel új hálózati végpontokat vezethet be, ezért az AbeSweep opcionálisan összeveti a beépített, kézzel ellenőrzött domaincsaládokat az Adobe hivatalos nyilvános oldalával. Az ellenőrzés új telepítésnél alapból kikapcsolt, kézzel bármikor elindítható, vagy engedélyezhető legfeljebb heti egy automatikus futásra. Elkülönített, cookie- és tartós cache nélküli HTTPS-munkamenetet használ. Nem tölti fel a hosts fájlt, a vizsgálati eredményeket, útvonalakat, naplókat, karantént vagy fiókadatokat. Az Adobe-kiszolgáló a normál kapcsolat miatt láthatja az IP-címet és az AbeSweep nevét tartalmazó technikai kérésazonosítót. Új domain csak felülvizsgálati jelölt lesz; automatikus törlés nincs."
                ),
                HelpSectionCopy(
                    title: "12. Frissítés",
                    body: "Az AbeSweep a Sparkle segítségével ellenőrzi és telepíti a frissítéseket. Kézzel az AbeSweep menü Frissítések keresése pontjából indíthatod. A fontos frissítések kiemelt jelzést és rövid magyarázatot kapnak; az 1.4-es verzió telepítése a következő takarítás előtt ajánlott. Frissítés előtt várd meg a folyamatban lévő művelet végét. Ha az automatikus ellenőrzést kikapcsoltad, kézzel keress frissítést. A hivatalos DMG-ben húzd az AbeSweepet az Applications mappába, és onnan indítsd."
                ),
                HelpSectionCopy(
                    title: "13. Felelősségi tájékoztató",
                    body: "A teljes tájékoztató a Súgó menü Felelősségi tájékoztató pontjából bármikor megnyitható. Az automatikus megjelenítés ugyanott újra beállítható."
                )
            ]
        case .english:
            return [
                HelpSectionCopy(
                    title: "1. Scan",
                    body: "Starting a scan does not modify the system. AbeSweep searches for Adobe applications, Adobe utilities and installer folders in /Applications/Utilities, background services, shared components, settings, caches, logs, and user data. In Containers, Group Containers, and Application Scripts, it recognizes both com.adobe identifiers and their Adobe team-prefixed forms. Full removal also detects verifiably Adobe-owned Photoshop, InDesign, and other product preferences, plus Device State data under Adobe roots. These may retain previous sessions, recent files, or personal presets, so they are shown with a red warning. Use Rescan after the previous operation has finished. If a CoreSync directory cannot be read, AbeSweep skips the whole directory; check Full Disk Access if necessary."
                ),
                HelpSectionCopy(
                    title: "2. Cleanup modes",
                    body: "Temporary files only selects regenerable caches and logs. Creative Cloud only removes the local Creative Cloud infrastructure to prepare for a clean reinstall; Adobe applications and protected personal cloud content are preserved. Full Adobe removal selects every recognized Adobe component except protected personal content. Custom selection lets you decide about every item."
                ),
                HelpSectionCopy(
                    title: "3. Results and risk indicators",
                    body: "Each result shows the file or folder name, path, size, category, removal reason, and risk level. A red warning means that the item may contain personal settings, presets, or other creative data. You can change the selection manually before removal."
                ),
                HelpSectionCopy(
                    title: "4. Removal and progress",
                    body: "AbeSweep asks for confirmation and, when required, macOS administrator authorization. Before removal, it detects running Adobe applications and Creative Cloud background processes such as CCXProcess and CoreSync. It requests normal termination and never forces document applications to quit. If an application stays open, for example to display a save dialog, cleanup stops. Save your work, close the application, then try again. It attempts to stop selected, validated Adobe launch services with administrator authorization. Background processes that could not be stopped are recorded in the log. These events are recorded in the log. The progress indicator shows the completed proportion and the path of the file currently being processed. Selected items are first moved into a restorable quarantine instead of being deleted immediately."
                ),
                HelpSectionCopy(
                    title: "5. Full Disk Access",
                    body: "macOS separately protects Containers and Group Containers data owned by other applications, so complete removal may require Full Disk Access. AbeSweep checks the state by opening a protected macOS probe without reading or retaining its contents. If access already works, it shows a green OK state and the button does not open System Settings. If permission is missing or cannot be determined, the button opens Privacy & Security > Full Disk Access. Add AbeSweep.app, turn on access beside it, then completely quit and reopen AbeSweep. macOS controls both the permission and authentication method: it may offer Touch ID on a supported, configured Mac, but AbeSweep cannot force it or grant access to itself."
                ),
                HelpSectionCopy(
                    title: "6. Cancelling an operation",
                    body: "Use Cancel Operation to stop a removal in progress. AbeSweep attempts to return items already in quarantine to their original locations. If a destination was recreated or a path changed, it does not overwrite it: it reports an error and retains the remaining quarantine data. Check the log and quarantine records. Wait for rollback to finish; normal quitting is blocked while changes are in progress."
                ),
                HelpSectionCopy(
                    title: "7. Quarantine, log, and restore",
                    body: "Quarantine stores removed items in ~/Library/Application Support/AbeSweep/Quarantine, so they continue to occupy disk space until permanently deleted. Manage Quarantine Records continues to show sessions after the app restarts, but it separately counts files that are actually still present and restorable. A “Record/log reference only” warning means the original files are no longer in quarantine: that record alone is not a backup and cannot be restored. The detailed log is stored separately in ~/Library/Logs/AbeSweep. Quarantines created by earlier AbeSweep versions under /Users/Shared remain supported. Restore is enabled only when actual quarantined content remains. A missing hosts backup does not block restoration of other remaining items; AbeSweep cannot recreate missing data. After a successful restore, you can start a new scan. Unselected empty parent directories may remain to preserve their original permissions."
                ),
                HelpSectionCopy(
                    title: "8. Permanently delete quarantine",
                    body: "Use Permanently Delete Quarantine only after confirming that the system and the Adobe applications you need work correctly. After a separate confirmation, AbeSweep rechecks the quarantine path and directory identity, then permanently deletes the current quarantine and frees its disk space. This action cannot be undone, and restoring is no longer possible afterward. The log is retained and remains available for review."
                ),
                HelpSectionCopy(
                    title: "9. Adobe PDFMaker and Microsoft Office",
                    body: "Acrobat PDFMaker may install Word, Excel, and PowerPoint add-ins in Microsoft Office startup folders. If the Acrobat framework is removed while these add-ins remain, Office may display a Visual Basic missing-file error. Full Adobe removal detects and quarantines the PDFMaker add-ins as well. Save your Office documents because affected Office applications may close."
                ),
                HelpSectionCopy(
                    title: "10. Optional hosts cleanup",
                    body: "The feature is named Clean Hosts File. If /etc/hosts contains custom Adobe-domain entries, the option appears separately and is off by default. AbeSweep removes only verified Adobe hostnames. If it finds the exact ADOBE_BLOCKLIST_START and ADOBE_BLOCKLIST_END markers used by the Ruddernation Adobe URL Block List, it can remove all content between them as one recognized block; AbeSweep neither downloads nor embeds the community list itself. In an unmarked third-party block list, unknown addresses and addresses belonging to other providers are reported but not removed. For a large list, the interface shows only the first 12 candidates and the number hidden. If there is no verified match, it clearly states that the file will not be modified. Missing or malformed marker pairs also stop modification. The original hosts file is kept in quarantine. Cleanup preserves its permissions; the content is checked again before replacement, and detected changes stop the operation. Do not edit the hosts file in another program during the operation."
                ),
                HelpSectionCopy(
                    title: "11. Adobe domain review and privacy",
                    body: "Application update checks connect to the macadmin.hu update server; system profiling is disabled. Separately, Adobe may introduce new network endpoints over time, so AbeSweep can optionally compare its built-in, manually verified domain families with Adobe's official public page. Review is off by default on a new installation; it can be run manually or enabled to run automatically at most weekly. It uses an isolated HTTPS session without cookies or persistent caching. It does not upload the hosts file, scan results, paths, logs, quarantine, or account data. Adobe's server can see the IP address and a technical request identifier containing the AbeSweep name as part of the normal connection. A new domain becomes a review candidate only; nothing is removed automatically."
                ),
                HelpSectionCopy(
                    title: "12. Updates",
                    body: "AbeSweep uses Sparkle to check for and install updates. You can check manually using Check for Updates in the AbeSweep menu. Important updates include a prominent notice and a short explanation; installing version 1.4 is recommended before your next cleanup. Wait for any running operation to finish before updating. If you disabled automatic checks, check manually. From the official DMG, drag AbeSweep to Applications and launch it from there."
                ),
                HelpSectionCopy(
                    title: "13. Disclaimer",
                    body: "You can open the full disclaimer at any time from Disclaimer in the Help menu. Its automatic display behavior can also be configured there."
                )
            ]
        }
    }

    private var warningText: String {
        L10n.text(
            "Eltávolítás előtt mindig mentsd el a munkádat, ellenőrizd a Creative Cloud szinkronizálását, és készíts biztonsági mentést.",
            "Before removal, always save your work, verify Creative Cloud synchronization, and create a backup."
        )
    }

    private var footerText: String {
        L10n.text(
            "A Súgó a menüsorból vagy a ⌘? billentyűkkel bármikor megnyitható.",
            "Help is available at any time from the menu bar or by pressing ⌘?."
        )
    }

    private var closeButtonTitle: String {
        L10n.text("Bezárás", "Close")
    }

    private func helpSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

private struct CompletionView: View {
    @ObservedObject var model: AppModel
    @State private var showingRestoreConfirmation = false
    @State private var showingPermanentDeleteConfirmation = false
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            Text(L10n.text("A takarítás elkészült", "Cleanup Complete")).font(.largeTitle.bold())
            Text(completionMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            HStack {
                Button(L10n.text("Karantén megnyitása", "Open Quarantine"), systemImage: "folder", action: model.revealQuarantine)
                    .disabled(model.quarantinePermanentlyDeleted || model.isPermanentlyDeletingQuarantine)
                Button(L10n.text("Napló megtekintése", "View Log"), systemImage: "doc.text.magnifyingglass", action: model.showLog)
                    .disabled(!model.hasLog)
                Button(L10n.text("Visszaállítás…", "Restore…"), systemImage: "arrow.uturn.backward") {
                    showingRestoreConfirmation = true
                }
                .disabled(!model.canRestoreLastSession || model.isPermanentlyDeletingQuarantine)
                Button(L10n.text("Új vizsgálat", "New Scan"), systemImage: "arrow.clockwise", action: model.scan)
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(model.isPermanentlyDeletingQuarantine)
            }
            if model.quarantinePermanentlyDeleted {
                Label(L10n.text("A karantén végleg törölve. A napló megmaradt, visszaállítás már nem lehetséges.", "The quarantine was permanently deleted. The log remains, but restore is no longer possible."), systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                if model.lastQuarantineRecord?.hasRestorableContent == false {
                    Label(
                        L10n.text(
                            "Ez a bejegyzés már csak jegyzéket és naplóhivatkozást tartalmaz. Az eltávolított eredeti fájlok nincsenek a karanténban, ezért visszaállítás nem lehetséges.",
                            "This entry now contains only a record and log reference. The removed original files are not in quarantine, so restore is not possible."
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 620)
                    .multilineTextAlignment(.center)
                }
                if model.isPermanentlyDeletingQuarantine {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text(L10n.text("A karantén végleges törlése…", "Permanently deleting quarantine…"))
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button(L10n.text("Karantén végleges törlése…", "Permanently Delete Quarantine…"), systemImage: "trash.fill", role: .destructive) {
                        showingPermanentDeleteConfirmation = true
                    }
                }

                Text(L10n.text("A karantén helye: ", "Quarantine location: ") + model.lastQuarantineBasePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(40)
        .alert(L10n.text("Mindent visszaállítasz?", "Restore Everything?"), isPresented: $showingRestoreConfirmation) {
            Button(L10n.text("Mégse", "Cancel"), role: .cancel) { }
            Button(L10n.text("Visszaállítás", "Restore")) { model.restoreLastSession() }
        } message: {
            Text(L10n.text("A karantén elemei visszakerülnek az eredeti helyükre, az ellenőrzött háttérszolgáltatások újraindítását megkísérli, és ha volt hosts-takarítás, annak biztonsági másolata is visszaáll. A hosts fájl későbbi módosítását az AbeSweep nem írja felül.", "Quarantined items will return to their original locations, validated background services will be restarted where possible, and any hosts backup will also be restored. AbeSweep will not overwrite a hosts file changed after cleanup."))
        }
        .alert(L10n.text("Végleg törlöd a karantént?", "Permanently Delete Quarantine?"), isPresented: $showingPermanentDeleteConfirmation) {
            Button(L10n.text("Mégse", "Cancel"), role: .cancel) { }
            Button(L10n.text("Végleg törlöm", "Delete Permanently"), role: .destructive) {
                model.permanentlyDeleteLastQuarantine()
            }
        } message: {
            Text(L10n.text("A karanténba helyezett fájlok végleg eltűnnek, és felszabadul az általuk foglalt lemezterület. A művelet nem vonható vissza, visszaállításra többé nem lesz lehetőség. Az AbeSweep naplója megmarad.", "Quarantined files will be permanently deleted and their disk space will be freed. This action cannot be undone and restore will no longer be possible. The AbeSweep log is retained."))
        }
    }

    private var completionMessage: String {
        if model.quarantinePermanentlyDeleted {
            return L10n.text("A takarítás befejeződött, és a karantén tartalma is véglegesen törlődött. Az AbeSweep naplója továbbra is megtekinthető.", "Cleanup is complete and the quarantine was permanently deleted. The AbeSweep log remains available.")
        }
        if model.lastSessionWasCreativeCloudOnly {
            return L10n.text("A Creative Cloud helyi összetevői eltűntek, a személyes fájlok és Adobe-alkalmazások megmaradtak. Most tisztán újratelepítheted a Creative Cloudot.", "Local Creative Cloud components were removed while personal files and Adobe applications were preserved. You can now perform a clean Creative Cloud reinstall.")
        }
        if model.lastQuarantineRecord?.hasRestorableContent == false {
            return L10n.text(
                "A korábbi művelet jegyzéke megvan, de tényleges karanténfájl már nincs benne. A külön AbeSweep-napló ettől még megtekinthető lehet.",
                "The earlier operation record exists, but it no longer contains actual quarantined files. The separate AbeSweep log may still be available for review."
            )
        }
        let count = model.lastQuarantineRecord?.restorableItemCount ?? 0
        return L10n.text(
            "\(count) elem kikerült az aktív rendszerből. A karantén megmarad, amíg meg nem győződtél róla, hogy minden megfelelően működik.",
            "\(count) item(s) were removed from the active system. Keep the quarantine until you have confirmed that everything works correctly."
        )
    }
}

private struct LogView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("AbeSweep napló", "AbeSweep Log")).font(.title2.bold())
                    Text(L10n.text("A feldolgozott, kihagyott, visszaállított és törölt elemek eseményei", "Events for processed, skipped, restored, and deleted items"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()

            ScrollView([.vertical, .horizontal]) {
                Text(model.logContents)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(18)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()
            HStack {
                Button(L10n.text("Megjelenítés a Finderben", "Show in Finder"), systemImage: "folder", action: model.revealLog)
                Spacer()
                Button(L10n.text("Bezárás", "Close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
