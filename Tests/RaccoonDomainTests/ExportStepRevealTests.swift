import RaccoonDomain
import Testing

struct ExportStepRevealTests {
    static func ms(_ values: [Int]) -> [Duration] { values.map { .milliseconds($0) } }

    @Test(arguments: [
        // Three steps finishing together start 60 ms apart.
        ([0, 0, 0], [0, 60, 120]),
        // A late step starts when it finishes: no artificial delay.
        ([0, 0, 500], [0, 60, 500]),
        // A step finishing inside the previous one's stagger waits for it.
        ([0, 30, 70], [0, 60, 120]),
        // Steps already further apart than 60 ms are left alone.
        ([10, 200, 900], [10, 200, 900]),
        ([], []),
    ])
    func `check i starts at the later of its finish and 60 ms after the previous start`(finished: [Int], expected: [Int]) {
        #expect(ExportStepReveal.starts(finishedAt: Self.ms(finished), reduceMotion: false) == Self.ms(expected))
    }

    @Test func `Reduce Motion returns the finish times unchanged`() {
        let finished = Self.ms([0, 0, 500])
        #expect(ExportStepReveal.starts(finishedAt: finished, reduceMotion: true) == finished)
    }
}
