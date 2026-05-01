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
}
