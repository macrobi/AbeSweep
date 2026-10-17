import AppKit
import SwiftUI
import Sparkle

@main
struct AbeSweepApp: App {
    @NSApplicationDelegateAdaptor(AbeSweepApplicationDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        Window("AbeSweep", id: "main") {
            ContentView(model: model)
                .onAppear { appDelegate.model = model }
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .systemServices) { }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .help) {
                Button(L10n.text("AbeSweep súgó", "AbeSweep Help")) {
                    NotificationCenter.default.post(name: .abeSweepShowHelp, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)

                Button(L10n.text("Felelősségi tájékoztató…", "Disclaimer…")) {
                    NotificationCenter.default.post(name: .abeSweepShowDisclaimer, object: nil)
                }

                Divider()

                Button(L10n.text("Teljes lemezhozzáférés ellenőrzése…", "Check Full Disk Access…")) {
                    NotificationCenter.default.post(name: .abeSweepOpenFullDiskAccess, object: nil)
                }

                Divider()

                Button(L10n.text("Naplómappa megnyitása", "Open Log Folder")) {
                    NotificationCenter.default.post(name: .abeSweepOpenLogs, object: nil)
                }
            }
        }
    }
}

@MainActor
final class AbeSweepApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.isMutating == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L10n.text("Művelet folyamatban", "Operation in Progress")
        alert.informativeText = L10n.text(
            "Kilépés előtt várd meg a művelet végét. Az eltávolítást a Művelet megszakítása gombbal állíthatod le; utána várd meg a visszagörgetést.",
            "Wait for the operation to finish before quitting. To stop cleanup, use Cancel Operation and wait for rollback to complete."
        )
        alert.addButton(withTitle: L10n.text("Rendben", "OK"))
        alert.runModal()
        return .terminateCancel
    }
}
