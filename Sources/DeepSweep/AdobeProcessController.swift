import AppKit
import Darwin
import Foundation
import Security

enum CodeSigningIdentity {
    static let adobeTeamIdentifier = "JQ525L2MZD"
    static let microsoftTeamIdentifier = "UBF8T346G9"

    static func validTeamIdentifier(atExecutablePath path: String) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: path) as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
        let staticCode,
        SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil) == errSecSuccess
        else { return nil }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
        let information = signingInformation as? [String: Any]
        else { return nil }

        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

struct AdobeProcessSnapshot: Equatable, Sendable {
    let processIdentifier: pid_t
    let name: String
    let executablePath: String?
    let bundleIdentifier: String?
    let isUserApplication: Bool

    init(
        processIdentifier: pid_t,
        name: String,
        executablePath: String?,
        bundleIdentifier: String?,
        isUserApplication: Bool = true
    ) {
        self.processIdentifier = processIdentifier
        self.name = name
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
        self.isUserApplication = isUserApplication
    }
}

struct AdobeProcessStopReport: Sendable {
    let requested: [AdobeProcessSnapshot]
    let remaining: [AdobeProcessSnapshot]
}

struct AdobeProcessController: @unchecked Sendable {
    typealias TeamIdentifierProvider = @Sendable (String) -> String?

    /// Creative Cloud processes which may run without appearing as ordinary
    /// applications in `NSWorkspace.shared.runningApplications`.
    static let backgroundProcessNames = [
        "CCXProcess",
        "CoreSync",
        "Creative Cloud",
        "Adobe Desktop Service",
        "AdobeIPCBroker",
        "Adobe CEF Helper",
        "Adobe Crash Processor",
        "AdobeCRDaemon",
        "AdobeResourceSynchronizer",
        "Adobe Content Synchronizer",
        "AdobeNotificationClient",
        "AdobeCollabSync"
    ]

    private static let normalizedBackgroundProcessNames = Set(
        backgroundProcessNames.map(normalizedProcessName)
    )

    private static let officeBundleIdentifiers: Set<String> = [
        "com.microsoft.word", "com.microsoft.excel", "com.microsoft.powerpoint"
    ]

    private let teamIdentifierProvider: TeamIdentifierProvider

    init(
        teamIdentifierProvider: @escaping TeamIdentifierProvider = CodeSigningIdentity.validTeamIdentifier
    ) {
        self.teamIdentifierProvider = teamIdentifierProvider
    }

    @MainActor
    func stopRelevantProcesses(includesOfficePDFMaker: Bool) async -> AdobeProcessStopReport {
        let initial = relevantProcesses(
            from: runningProcessSnapshots(),
            includesOfficePDFMaker: includesOfficePDFMaker
        )

        requestTermination(of: initial)
        // A save dialog can keep an editor running. Never force it to quit.
        for _ in 0..<20 {
            if Task.isCancelled { break }
            if matchingCurrentProcesses(initial).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return AdobeProcessStopReport(
            requested: initial,
            remaining: relevantProcesses(
                from: runningProcessSnapshots(),
                includesOfficePDFMaker: includesOfficePDFMaker
            )
        )
    }

    func relevantProcesses(
        from snapshots: [AdobeProcessSnapshot],
        includesOfficePDFMaker: Bool
    ) -> [AdobeProcessSnapshot] {
        snapshots.filter {
            Self.isRelevant(
                $0,
                includesOfficePDFMaker: includesOfficePDFMaker,
                teamIdentifierProvider: teamIdentifierProvider
            )
        }
    }

    static func isRelevant(
        _ process: AdobeProcessSnapshot,
        includesOfficePDFMaker: Bool,
        teamIdentifierProvider: TeamIdentifierProvider = CodeSigningIdentity.validTeamIdentifier
    ) -> Bool {
        let identifier = process.bundleIdentifier?.lowercased() ?? ""
        guard let executablePath = process.executablePath,
              let teamIdentifier = teamIdentifierProvider(executablePath)
        else { return false }

        if includesOfficePDFMaker,
           officeBundleIdentifiers.contains(identifier) {
            return teamIdentifier == CodeSigningIdentity.microsoftTeamIdentifier
        }

        let executableName = process.executablePath.map {
            URL(fileURLWithPath: $0).lastPathComponent
        }
        let nameMatches = [process.name, executableName]
            .compactMap { $0 }
            .map(normalizedProcessName)
            .contains { normalizedBackgroundProcessNames.contains($0) }
        let hasAdobeIdentityHint = identifier.hasPrefix("com.adobe.")
            || nameMatches && isVerifiedAdobeExecutablePath(executablePath)
        return hasAdobeIdentityHint && teamIdentifier == CodeSigningIdentity.adobeTeamIdentifier
    }

    private static func isVerifiedAdobeExecutablePath(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path.lowercased()
        let allowedPrefixes = [
            "/library/application support/adobe/",
            "/library/privilegedhelpertools/com.adobe.",
            "/applications/adobe ",
            "/applications/utilities/adobe ",
            home + "/library/application support/adobe/",
            home + "/applications/adobe "
        ]
        return allowedPrefixes.contains { normalized.hasPrefix($0) }
    }

    private static func normalizedProcessName(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    @MainActor
    private func requestTermination(of processes: [AdobeProcessSnapshot]) {
        for process in matchingCurrentProcesses(processes) {
            if let application = NSRunningApplication(processIdentifier: process.processIdentifier) {
                application.terminate()
            } else {
                Darwin.kill(process.processIdentifier, SIGTERM)
            }
        }
    }

    @MainActor
    private func matchingCurrentProcesses(
        _ previous: [AdobeProcessSnapshot]
    ) -> [AdobeProcessSnapshot] {
        let currentByPID = Dictionary(
            uniqueKeysWithValues: runningProcessSnapshots().map { ($0.processIdentifier, $0) }
        )
        return previous.compactMap { earlier in
            guard let current = currentByPID[earlier.processIdentifier],
                  Self.hasSameIdentity(current, earlier),
                  Self.isRelevant(
                      current,
                      includesOfficePDFMaker: Self.officeBundleIdentifiers.contains(
                          earlier.bundleIdentifier?.lowercased() ?? ""
                      ),
                      teamIdentifierProvider: teamIdentifierProvider
                  )
            else { return nil }
            return current
        }
    }

    private static func hasSameIdentity(
        _ current: AdobeProcessSnapshot,
        _ earlier: AdobeProcessSnapshot
    ) -> Bool {
        if let currentPath = current.executablePath,
           let earlierPath = earlier.executablePath {
            return currentPath == earlierPath
        }
        guard let currentIdentifier = current.bundleIdentifier?.lowercased(),
              let earlierIdentifier = earlier.bundleIdentifier?.lowercased(),
              !currentIdentifier.isEmpty
        else { return false }
        return currentIdentifier == earlierIdentifier
    }

    @MainActor
    private func runningProcessSnapshots() -> [AdobeProcessSnapshot] {
        var snapshotsByPID: [pid_t: AdobeProcessSnapshot] = [:]

        for application in NSWorkspace.shared.runningApplications {
            let pid = application.processIdentifier
            snapshotsByPID[pid] = AdobeProcessSnapshot(
                processIdentifier: pid,
                name: application.localizedName ?? application.executableURL?.lastPathComponent ?? "",
                executablePath: application.executableURL?.path,
                bundleIdentifier: application.bundleIdentifier,
                isUserApplication: application.activationPolicy == .regular
            )
        }

        for snapshot in systemProcessSnapshots() where snapshotsByPID[snapshot.processIdentifier] == nil {
            snapshotsByPID[snapshot.processIdentifier] = snapshot
        }
        snapshotsByPID.removeValue(forKey: getpid())
        return Array(snapshotsByPID.values)
    }

    private func systemProcessSnapshots() -> [AdobeProcessSnapshot] {
        let capacity = max(Int(proc_listallpids(nil, 0)), 1)
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { return [] }

        return pids.prefix(Int(count)).compactMap { pid in
            guard pid > 0, let identity = processIdentity(pid: pid) else { return nil }
            return AdobeProcessSnapshot(
                processIdentifier: pid,
                name: identity.name,
                executablePath: identity.path,
                bundleIdentifier: nil,
                isUserApplication: false
            )
        }
    }

    private func processIdentity(pid: pid_t) -> (name: String, path: String?)? {
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
        let nameLength = nameBuffer.withUnsafeMutableBufferPointer {
            proc_name(pid, $0.baseAddress, UInt32($0.count))
        }
        guard nameLength > 0 else { return nil }
        let name = decodedCString(nameBuffer)

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let pathLength = pathBuffer.withUnsafeMutableBufferPointer {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        let path = pathLength > 0 ? decodedCString(pathBuffer) : nil
        return (name, path)
    }

    private func decodedCString(_ buffer: [CChar]) -> String {
        String(
            decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }
}
