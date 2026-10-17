import Testing
@testable import AbeSweep

struct FullDiskAccessCheckerTests {
    @Test func deniedProbeIsNotMaskedByAnotherReadableProbe() {
        #expect(FullDiskAccessChecker.resolve([.readable, .denied]) == .notGranted)
        #expect(FullDiskAccessChecker.resolve([.denied, .readable]) == .notGranted)
    }

    @Test func readableProtectedProbeMeansAccessIsGranted() {
        #expect(FullDiskAccessChecker.resolve([.unavailable, .readable]) == .granted)
    }

    @Test func deniedProtectedProbeMeansAccessIsMissing() {
        #expect(FullDiskAccessChecker.resolve([.unavailable, .denied]) == .notGranted)
    }

    @Test func missingProbesLeaveAccessUnknown() {
        #expect(FullDiskAccessChecker.resolve([.unavailable]) == .unknown)
    }
}
