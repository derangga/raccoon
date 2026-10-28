import RaccoonDomain
import Testing

struct CloseStepTests {
    @Test(arguments: [
        (false, false, CloseStep.close),
        (false, true, .close),
        (true, false, .ask),
        (true, true, .close),
    ])
    func `closing asks only for losable content while always discarding is off`(losable: Bool, alwaysDiscards: Bool, step: CloseStep) {
        #expect(CloseStep(hasLosableContent: losable, alwaysDiscards: alwaysDiscards) == step)
    }
}
