import XCTest
@testable import Notchy

final class DashboardLayoutTests: XCTestCase {
    private func total(_ widths: [CGFloat], count: Int) -> CGFloat {
        widths.reduce(0, +) + DashboardLayout.spacing * CGFloat(count - 1)
    }

    func testCardsAlwaysFillTheRow() {
        for tools in [[Tool.tasks, .focus], [.focus, .week, .insights], [.tasks, .focus, .notepad, .calendar, .clipboard]] {
            let widths = DashboardLayout.widths(for: tools, in: 856)
            XCTAssertEqual(total(widths, count: tools.count), 856, accuracy: 0.5)
        }
    }

    func testShrinkingNeverGoesBelowMinimum() {
        let tools: [Tool] = [.tasks, .focus, .notepad, .calendar, .clipboard]
        let widths = DashboardLayout.widths(for: tools, in: 856)
        for (tool, width) in zip(tools, widths) {
            XCTAssertGreaterThanOrEqual(width + 0.5, DashboardLayout.minimumWidth(tool))
        }
    }

    func testFitsRejectsOverflowingDashboards() {
        XCTAssertTrue(DashboardLayout.fits([.tasks, .focus, .notepad, .calendar, .clipboard], in: 856))
        XCTAssertFalse(DashboardLayout.fits([.tasks, .focus, .notepad, .calendar, .clipboard, .week], in: 856))
    }
}
