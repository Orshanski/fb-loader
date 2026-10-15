import Testing
@testable import FB_Loader

@MainActor
@Suite("LoadSessionGate")
struct LoadSessionGateTests {
    @Test("stale callbacks are ignored after a load finishes")
    func staleCallbacksIgnoredAfterFinish() {
        let gate = LoadSessionGate()
        let token = gate.begin()
        var applied: [String] = []

        gate.apply(token) {
            applied.append("loading")
        }

        #expect(gate.finish(token) == true)

        gate.apply(token) {
            applied.append("stale")
        }

        #expect(applied == ["loading"])
    }

    @Test("после cancel колбэки и результат прежней загрузки не применяются")
    func cancelledTokenIgnored() {
        let gate = LoadSessionGate()
        let token = gate.begin()
        var applied = false

        gate.cancel()
        gate.apply(token) { applied = true }

        #expect(!applied)
        #expect(gate.finish(token) == false)
    }
}
