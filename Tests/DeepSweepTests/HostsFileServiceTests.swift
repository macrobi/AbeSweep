import Foundation
import Testing
@testable import AbeSweep

@Suite struct HostsFileServiceTests {
    @Test func removesOnlyAdobeHostnamesAndPreservesMixedEntries() {
        let source = """
        ## local hosts
        127.0.0.1 localhost activate.adobe.com # mixed
        0.0.0.0 genuine.adobe.com
        0.0.0.0 example.com

        """

        let plan = HostsFileService().plan(content: source)

        #expect(plan?.matchedHostnames == ["activate.adobe.com", "genuine.adobe.com"])
        #expect(plan?.cleanedContent.contains("127.0.0.1\tlocalhost\t# mixed") == true)
        #expect(plan?.cleanedContent.contains("example.com") == true)
        #expect(plan?.cleanedContent.contains("activate.adobe.com") == false)
        #expect(plan?.cleanedContent.hasSuffix("\n") == true)
    }

    @Test func ignoresCommentsAndSimilarLookingDomains() {
        let source = """
        # 0.0.0.0 activate.adobe.com
        0.0.0.0 adobe.com.example.org
        0.0.0.0 myadobe.com
        """

        #expect(HostsFileService().plan(content: source) == nil)
    }

    @Test func recognizesConfiguredAdobeDomainFamilies() {
        let service = HostsFileService()
        #expect(service.isAdobeHostname("cc-api-data.adobe.io"))
        #expect(service.isAdobeHostname("use.typekit.net."))
        #expect(service.isAdobeHostname("assets.behance.net"))
        #expect(service.isAdobeHostname("anything.adobegenuine.com"))
        #expect(!service.isAdobeHostname("notadobe.io.example.com"))
    }

    @Test func unknownAdobeLookingHostsAreReportedButNotRemoved() {
        let content = "0.0.0.0 licensing.new-adobe-domain.example\n0.0.0.0 ordinary.example\n"
        let inspection = HostsInspection(
            cleanupPlan: HostsFileService().plan(content: content),
            unverifiedCandidates: HostsFileService().candidateHostnames(content: content),
            malformedManagedBlock: false
        )
        #expect(inspection.cleanupPlan == nil)
        #expect(inspection.unverifiedCandidates == ["licensing.new-adobe-domain.example"])
    }

    @Test func removesACompleteRuddernationManagedBlockWithoutImportingItsRules() throws {
        let content = """
        127.0.0.1 localhost
        ## ADOBE_BLOCKLIST_START ##
        0.0.0.0 activate.adobe.com
        0.0.0.0 workflow-ui-prod.licensingstack.com
        0.0.0.0 adobe.demdex.net
        ## ADOBE_BLOCKLIST_END ##
        0.0.0.0 ordinary.example

        """

        let inspection = HostsFileService().inspect(content: content)
        let plan = try #require(inspection.cleanupPlan)
        #expect(plan.managedBlockCount == 1)
        #expect(plan.managedBlockEntryCount == 3)
        #expect(plan.cleanedContent == "127.0.0.1 localhost\n0.0.0.0 ordinary.example\n")
        #expect(inspection.unverifiedCandidates.isEmpty)
    }

    @Test func malformedManagedBlockDisablesHostsModification() {
        let content = """
        127.0.0.1 localhost
        ## ADOBE_BLOCKLIST_START ##
        0.0.0.0 activate.adobe.com
        """

        let inspection = HostsFileService().inspect(content: content)
        #expect(inspection.malformedManagedBlock)
        #expect(inspection.cleanupPlan == nil)
    }

    @Test func largeUnmarkedCandidateListIsReportedButNeverTreatedAsCleanable() {
        let content = (1...350)
            .map { "0.0.0.0 adobe-candidate-\($0).third-party.example" }
            .joined(separator: "\n") + "\n"

        let inspection = HostsFileService().inspect(content: content)

        #expect(inspection.cleanupPlan == nil)
        #expect(inspection.unverifiedCandidates.count == 350)
        #expect(!inspection.malformedManagedBlock)
    }
}
