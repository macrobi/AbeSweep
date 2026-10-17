import AppKit
import Testing
@testable import AbeSweep

struct SecretSweepTests {
    @Test func optionAndCommandAreBothRequired() {
        #expect(SecretSweepTrigger.isActive([.command, .option]))
        #expect(SecretSweepTrigger.isActive([.command, .option, .shift]))
        #expect(!SecretSweepTrigger.isActive([.command]))
        #expect(!SecretSweepTrigger.isActive([.option]))
        #expect(!SecretSweepTrigger.isActive([]))
    }
}
