import CoreGraphics
@testable import Raccoon
import Testing

/// Where the GraphQL Query | Variables divider starts, and how little a side may shrink to (design-system.md §6).
@MainActor
struct GraphQLSplitLayoutTests {
    @Test(arguments: [
        (1016.0, 500.0),  // room 1000: equal halves
        (816.0, 400.0),
        (497.0, 240.0),   // room 481: the odd point goes to Variables
        (300.0, 142.0),   // narrower than two minimums: still equal
    ] as [(CGFloat, CGFloat)])
    func `the first layout puts the divider at 50 : 50`(width: CGFloat, position: CGFloat) {
        #expect(GraphQLSplitLayout.firstPosition(width: width, divider: 16) == position)
    }

    @Test(arguments: [16.0, 0.0] as [CGFloat])
    func `a pane with no room is not placed`(width: CGFloat) {
        #expect(GraphQLSplitLayout.firstPosition(width: width, divider: 16) == nil)
    }

    @Test(arguments: [(1000.0, 240.0), (496.0, 240.0), (400.0, 192.0), (16.0, 0.0), (0.0, 0.0)] as [(CGFloat, CGFloat)])
    func `a side keeps 240 pt, or half the room when the pane is narrower`(width: CGFloat, minimum: CGFloat) {
        #expect(GraphQLSplitLayout.minimum(width: width, divider: 16) == minimum)
    }
}
