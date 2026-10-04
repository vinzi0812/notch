import CoreGraphics
import Testing
@testable import Notch

struct TabReorderTests {
    // Three tabs 20, 40 and 20 wide with 10 between: centers at 10, 50 and 90.
    let widths: [CGFloat] = [20, 40, 20]
    let spacing: CGFloat = 10

    @Test func centersAreLaidOutLeftToRight() {
        #expect(TabReorder.centers(widths: widths, spacing: spacing) == [10, 50, 90])
    }

    @Test func aNeighborMakesWayWhenTheLeadingEdgeReachesItsCenter() {
        // The first tab's right edge starts at 20; the middle tab's center is at 50.
        #expect(TabReorder.target(from: 0, offset: 29, widths: widths, spacing: spacing) == 0)
        #expect(TabReorder.target(from: 0, offset: 31, widths: widths, spacing: spacing) == 1)
        #expect(TabReorder.target(from: 0, offset: 71, widths: widths, spacing: spacing) == 2)
        // Back the other way: the last tab's left edge starts at 80.
        #expect(TabReorder.target(from: 2, offset: -29, widths: widths, spacing: spacing) == 2)
        #expect(TabReorder.target(from: 2, offset: -31, widths: widths, spacing: spacing) == 1)
        #expect(TabReorder.target(from: 2, offset: -71, widths: widths, spacing: spacing) == 0)
    }

    @Test func aTabCantBeDraggedPastTheEndsOfItsRow() {
        #expect(TabReorder.clamped(-50, from: 0, widths: widths, spacing: spacing) == 0)
        #expect(TabReorder.clamped(500, from: 0, widths: widths, spacing: spacing) == 80)
        #expect(TabReorder.clamped(500, from: 1, widths: widths, spacing: spacing) == 30)
    }

    @Test func draggingRightSlidesThePassedTabsLeft() {
        let shifts = (0..<3).map { TabReorder.shift(of: $0, from: 0, to: 2, by: 30) }
        #expect(shifts == [0, -30, -30])
    }

    @Test func draggingLeftSlidesThePassedTabsRight() {
        let shifts = (0..<3).map { TabReorder.shift(of: $0, from: 2, to: 1, by: 30) }
        #expect(shifts == [0, 30, 0])
    }

    @Test func nothingMovesUntilATabIsPassed() {
        let shifts = (0..<3).map { TabReorder.shift(of: $0, from: 1, to: 1, by: 30) }
        #expect(shifts == [0, 0, 0])
    }

    @Test func aReleasedTabGlidesToWhereTheNewOrderDrawsIt() {
        // Dropped last: [40, 20, 20] puts it at center 90, from 10.
        #expect(TabReorder.slotOffset(from: 0, to: 2, widths: widths, spacing: spacing) == 80)
        // The wide middle tab dropped first: center 20, from 50.
        #expect(TabReorder.slotOffset(from: 1, to: 0, widths: widths, spacing: spacing) == -30)
        #expect(TabReorder.slotOffset(from: 1, to: 1, widths: widths, spacing: spacing) == 0)
    }
}
