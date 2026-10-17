import Foundation

struct AdobeDomainCatalog: Sendable {
    static let current = AdobeDomainCatalog(
        version: "2026.08.10",
        reviewedAt: Date(timeIntervalSince1970: 1_786_320_000),
        sourceURL: URL(string: "https://helpx.adobe.com/business/enterprise/manage-services/configure-services/network-endpoints.html")!,
        verifiedSuffixes: [
            "acrobat.com", "adobe.com", "adobe.io", "adobe.net", "adobe-identity.com",
            "adobe-services.com", "adobecc.com", "adobecces.com", "adobeccstatic.com",
            "adobeconnect.com", "adobedc.net", "adobedtm.com", "adobeexchange.com",
            "adobeexchange.org", "adobegenuine.com", "adobegov.com", "adobejanus.com",
            "adobelogin.com", "adobeoobe.com", "adobeprojectm.com", "adobesc.com",
            "adobess.com", "adobesunbreak.com", "adobetag.com", "behance.net",
            "creativecloud.com", "ftcdn.net", "typekit.com", "typekit.net"
        ],
        verifiedExactHostnames: ["slp-statics.astockcdn.net"]
    )

    let version: String
    let reviewedAt: Date
    let sourceURL: URL
    let verifiedSuffixes: Set<String>
    let verifiedExactHostnames: Set<String>

    init(
        version: String,
        reviewedAt: Date,
        sourceURL: URL,
        verifiedSuffixes: Set<String>,
        verifiedExactHostnames: Set<String>
    ) {
        self.version = version
        self.reviewedAt = reviewedAt
        self.sourceURL = sourceURL
        self.verifiedSuffixes = verifiedSuffixes
        self.verifiedExactHostnames = verifiedExactHostnames
    }
}

struct DomainReviewResult: Codable, Equatable, Sendable {
    let checkedAt: Date
    let publishedSuffixes: [String]
    let newCandidates: [String]
}

enum DomainReviewError: LocalizedError {
    case invalidResponse
    case sourceTooLarge
    case listNotFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            L10n.text("Az Adobe hivatalos domainoldala nem adott érvényes választ.", "Adobe's official domain page did not return a valid response.")
        case .sourceTooLarge:
            L10n.text("Az Adobe domainoldala a biztonsági méretkorlátnál nagyobb.", "Adobe's domain page exceeded the safety size limit.")
        case .listNotFound:
            L10n.text("A hivatalos Adobe-domainlista nem ismerhető fel az oldalon.", "The official Adobe domain list could not be recognized on the page.")
        }
    }
}

struct AdobeDomainCatalogReviewer: Sendable {
    let catalog: AdobeDomainCatalog

    init(catalog: AdobeDomainCatalog = .current) {
        self.catalog = catalog
    }

    func review() async throws -> DomainReviewResult {
        var request = URLRequest(url: catalog.sourceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        request.setValue("AbeSweep/\(appVersion) domain-review", forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              http.url?.scheme == "https",
              http.url?.host.map({ $0 == "adobe.com" || $0.hasSuffix(".adobe.com") }) == true
        else { throw DomainReviewError.invalidResponse }
        guard data.count <= 5_000_000 else { throw DomainReviewError.sourceTooLarge }
        guard let html = String(data: data, encoding: .utf8) else { throw DomainReviewError.invalidResponse }

        let published = try Self.extractAdobeHostedSuffixes(from: html)
        let known = catalog.verifiedSuffixes
        return DomainReviewResult(
            checkedAt: Date(),
            publishedSuffixes: published.sorted(),
            newCandidates: published.subtracting(known).sorted()
        )
    }

    static func extractAdobeHostedSuffixes(from html: String) throws -> Set<String> {
        let text = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#42;", with: "*")
            .replacingOccurrences(of: "&ast;", with: "*")

        guard let start = text.range(of: "Adobe hosted domains", options: [.caseInsensitive]),
              let end = text.range(of: "Amazon Web Services", options: [.caseInsensitive], range: start.upperBound..<text.endIndex)
        else { throw DomainReviewError.listNotFound }

        let section = String(text[start.upperBound..<end.lowerBound])
        let regex = try NSRegularExpression(pattern: #"\*\.([a-z0-9-]+(?:\.[a-z0-9-]+)+)"#, options: [.caseInsensitive])
        let range = NSRange(section.startIndex..<section.endIndex, in: section)
        let suffixes = regex.matches(in: section, range: range).compactMap { match -> String? in
            guard let valueRange = Range(match.range(at: 1), in: section) else { return nil }
            return String(section[valueRange]).lowercased()
        }
        guard suffixes.count >= 10 else { throw DomainReviewError.listNotFound }
        return Set(suffixes)
    }
}
