import Darwin
import Foundation

enum FullDiskAccessStatus: Equatable, Sendable {
    case granted
    case notGranted
    case unknown
}

struct FullDiskAccessChecker {
    enum ProbeResult: Equatable, Sendable {
        case readable
        case denied
        case unavailable
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func status() -> FullDiskAccessStatus {
        let home = fileManager.homeDirectoryForCurrentUser
        let protectedFiles = [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Safari/History.db"),
            home.appendingPathComponent("Library/Messages/chat.db")
        ]
        return Self.resolve(protectedFiles.map(probe))
    }

    static func resolve(_ results: [ProbeResult]) -> FullDiskAccessStatus {
        // A readable probe must not hide a denied protected location.
        if results.contains(.denied) { return .notGranted }
        if results.contains(.readable) { return .granted }
        return .unknown
    }

    private func probe(_ url: URL) -> ProbeResult {
        let descriptor = url.path.withCString { open($0, O_RDONLY | O_CLOEXEC) }
        if descriptor >= 0 {
            close(descriptor)
            return .readable
        }
        if errno == EACCES || errno == EPERM { return .denied }
        return .unavailable
    }
}
