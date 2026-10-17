import CryptoKit
import Foundation

struct HostsCleanupPlan: Codable, Equatable, Sendable {
    let originalContent: String
    let cleanedContent: String
    let originalSHA256: String
    let cleanedSHA256: String
    let matchedHostnames: [String]
    let managedBlockCount: Int
    let managedBlockEntryCount: Int

    var record: HostsCleanupRecord {
        HostsCleanupRecord(
            originalSHA256: originalSHA256,
            cleanedSHA256: cleanedSHA256,
            removedHostnames: matchedHostnames
        )
    }
}

struct HostsCleanupRecord: Codable, Equatable, Sendable {
    let originalSHA256: String
    let cleanedSHA256: String
    let removedHostnames: [String]
}

struct HostsInspection: Equatable, Sendable {
    let cleanupPlan: HostsCleanupPlan?
    let unverifiedCandidates: [String]
    let malformedManagedBlock: Bool
}

struct HostsFileService: Sendable {
    static let ruddernationStartMarker = "## ADOBE_BLOCKLIST_START ##"
    static let ruddernationEndMarker = "## ADOBE_BLOCKLIST_END ##"

    let catalog: AdobeDomainCatalog

    init(catalog: AdobeDomainCatalog = .current) {
        self.catalog = catalog
    }

    func inspect(at url: URL = URL(fileURLWithPath: "/etc/hosts")) throws -> HostsInspection {
        let content = try String(contentsOf: url, encoding: .utf8)
        return inspect(content: content)
    }

    func inspect(content: String) -> HostsInspection {
        let managedBlocks = analyzeManagedBlocks(in: content)
        return HostsInspection(
            cleanupPlan: managedBlocks.malformed ? nil : plan(content: content),
            unverifiedCandidates: managedBlocks.malformed
                ? candidateHostnames(content: content)
                : candidateHostnames(content: managedBlocks.contentOutsideBlocks),
            malformedManagedBlock: managedBlocks.malformed
        )
    }

    func plan(at url: URL = URL(fileURLWithPath: "/etc/hosts")) throws -> HostsCleanupPlan? {
        let content = try String(contentsOf: url, encoding: .utf8)
        return plan(content: content)
    }

    func plan(content: String) -> HostsCleanupPlan? {
        let managedBlocks = analyzeManagedBlocks(in: content)
        guard !managedBlocks.malformed else { return nil }
        let hadTrailingNewline = content.hasSuffix("\n")
        let sourceLines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var matched = Set<String>()
        var insideManagedBlock = false

        var cleanedLines: [String] = []
        for line in sourceLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == Self.ruddernationStartMarker {
                insideManagedBlock = true
                continue
            }
            if trimmed == Self.ruddernationEndMarker {
                insideManagedBlock = false
                continue
            }
            if insideManagedBlock {
                hostnames(in: line).forEach { matched.insert($0) }
                continue
            }

            let commentIndex = line.firstIndex(of: "#")
            let dataPart = commentIndex.map { String(line[..<$0]) } ?? line
            let commentPart = commentIndex.map { String(line[$0...]) }
            let tokens = dataPart.split(whereSeparator: \.isWhitespace).map(String.init)

            guard tokens.count >= 2, isIPAddress(tokens[0]) else {
                cleanedLines.append(line)
                continue
            }
            let adobeHosts = tokens.dropFirst().filter(isAdobeHostname)
            guard !adobeHosts.isEmpty else {
                cleanedLines.append(line)
                continue
            }

            adobeHosts.forEach { matched.insert(Self.normalizedHostname($0)) }
            let retainedHosts = tokens.dropFirst().filter { !isAdobeHostname($0) }
            if retainedHosts.isEmpty {
                cleanedLines.append(commentPart ?? "")
                continue
            }

            let rebuilt = ([tokens[0]] + retainedHosts).joined(separator: "\t")
            cleanedLines.append(commentPart.map { rebuilt + "\t" + $0 } ?? rebuilt)
        }

        guard !matched.isEmpty else { return nil }
        if hadTrailingNewline, cleanedLines.last == "" {
            cleanedLines.removeLast()
        }
        var cleaned = cleanedLines.joined(separator: "\n")
        if hadTrailingNewline { cleaned += "\n" }

        return HostsCleanupPlan(
            originalContent: content,
            cleanedContent: cleaned,
            originalSHA256: Self.sha256(content),
            cleanedSHA256: Self.sha256(cleaned),
            matchedHostnames: matched.sorted(),
            managedBlockCount: managedBlocks.blockCount,
            managedBlockEntryCount: managedBlocks.entryCount
        )
    }

    func isAdobeHostname(_ value: String) -> Bool {
        let hostname = Self.normalizedHostname(value)
        if catalog.verifiedExactHostnames.contains(hostname) { return true }
        return catalog.verifiedSuffixes.contains { suffix in
            hostname == suffix || hostname.hasSuffix("." + suffix)
        }
    }

    func candidateHostnames(content: String) -> [String] {
        let markers = ["adobe", "acrobat", "behance", "creativecloud", "fotolia", "typekit"]
        let candidates = hostnames(in: content).filter { hostname in
            guard !isAdobeHostname(hostname) else { return false }
            return hostname.split(separator: ".").contains { label in
                markers.contains { marker in String(label).localizedCaseInsensitiveContains(marker) }
            }
        }
        return Array(Set(candidates)).sorted()
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedHostname(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func hostnames(in content: String) -> [String] {
        content.split(separator: "\n", omittingEmptySubsequences: false).flatMap { rawLine -> [String] in
            let line = String(rawLine)
            let dataPart = line.firstIndex(of: "#").map { String(line[..<$0]) } ?? line
            let tokens = dataPart.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 2, isIPAddress(tokens[0]) else { return [] }
            return tokens.dropFirst().map(Self.normalizedHostname)
        }
    }

    private func analyzeManagedBlocks(in content: String) -> (
        malformed: Bool,
        blockCount: Int,
        entryCount: Int,
        contentOutsideBlocks: String
    ) {
        let hadTrailingNewline = content.hasSuffix("\n")
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var outside: [String] = []
        var inside = false
        var malformed = false
        var blockCount = 0
        var entryCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == Self.ruddernationStartMarker {
                if inside { malformed = true }
                inside = true
                blockCount += 1
                continue
            }
            if trimmed == Self.ruddernationEndMarker {
                if !inside { malformed = true }
                inside = false
                continue
            }
            if inside {
                entryCount += hostnames(in: line).count
            } else {
                outside.append(line)
            }
        }
        if inside { malformed = true }

        if hadTrailingNewline, outside.last == "" { outside.removeLast() }
        var outsideContent = outside.joined(separator: "\n")
        if hadTrailingNewline { outsideContent += "\n" }
        return (malformed, blockCount, entryCount, outsideContent)
    }

    private func isIPAddress(_ value: String) -> Bool {
        if value.contains(":") {
            let address = value.split(separator: "%", maxSplits: 1).first.map(String.init) ?? value
            return !address.isEmpty && address.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard let number = Int(part) else { return false }
            return (0...255).contains(number)
        }
    }
}
