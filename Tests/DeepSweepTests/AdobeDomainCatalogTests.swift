import Testing
@testable import AbeSweep

@Suite struct AdobeDomainCatalogTests {
    @Test func extractsOnlyAdobeHostedSection() throws {
        let html = """
        <h2>Adobe hosted domains:</h2>
        <ul>
          <li>*.adobe.com</li><li>*.adobe.io</li><li>*.adobecc.com</li>
          <li>*.adobecces.com</li><li>*.adobeccstatic.com</li><li>*.adobedtm.com</li>
          <li>*.adobeexchange.com</li><li>*.adobegenuine.com</li><li>*.adobegov.com</li>
          <li>*.adobelogin.com</li><li>*.typekit.net</li>
        </ul>
        <h2>Amazon Web Services:</h2>
        <li>*.s3.amazonaws.com</li>
        """

        let result = try AdobeDomainCatalogReviewer.extractAdobeHostedSuffixes(from: html)
        #expect(result.contains("adobe.com"))
        #expect(result.contains("typekit.net"))
        #expect(!result.contains("s3.amazonaws.com"))
    }

    @Test func rejectsUnexpectedPageStructure() {
        #expect(throws: DomainReviewError.self) {
            try AdobeDomainCatalogReviewer.extractAdobeHostedSuffixes(from: "<html>changed</html>")
        }
    }
}
