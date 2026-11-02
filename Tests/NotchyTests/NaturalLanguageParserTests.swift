import XCTest
@testable import Notchy

final class NaturalLanguageParserTests: XCTestCase {
    private let calendar = Calendar.current

    func testTomorrowWithTime() throws {
        let parsed = NaturalLanguageParser.parse("call mom tomorrow at 5pm")
        XCTAssertEqual(parsed.title, "call mom")
        XCTAssertTrue(parsed.hasTime)
        let due = try XCTUnwrap(parsed.dueDate)
        XCTAssertTrue(calendar.isDateInTomorrow(due))
        XCTAssertEqual(calendar.component(.hour, from: due), 17)
        XCTAssertEqual(calendar.component(.minute, from: due), 0)
    }

    func testDateWithoutTimeIsAllDay() throws {
        let parsed = NaturalLanguageParser.parse("Ship the landing page tomorrow")
        XCTAssertEqual(parsed.title, "Ship the landing page")
        XCTAssertFalse(parsed.hasTime)
        let due = try XCTUnwrap(parsed.dueDate)
        XCTAssertEqual(due, calendar.startOfDay(for: due))
        XCTAssertTrue(calendar.isDateInTomorrow(due))
    }

    func testPlainTextHasNoDate() {
        let parsed = NaturalLanguageParser.parse("Review Sam's PR")
        XCTAssertEqual(parsed.title, "Review Sam's PR")
        XCTAssertNil(parsed.dueDate)
        XCTAssertEqual(parsed.priority, .none)
    }

    func testPriorityTokens() {
        XCTAssertEqual(NaturalLanguageParser.parse("Pay rent !high").priority, .high)
        XCTAssertEqual(NaturalLanguageParser.parse("Pay rent p2").priority, .medium)
        XCTAssertEqual(NaturalLanguageParser.parse("Pay rent !low").title, "Pay rent")
    }

    func testTimeOnlyIsInTheFuture() throws {
        let parsed = NaturalLanguageParser.parse("stretch at 7:30am")
        let due = try XCTUnwrap(parsed.dueDate)
        XCTAssertTrue(parsed.hasTime)
        XCTAssertGreaterThan(due, Date())
        XCTAssertEqual(parsed.title, "stretch")
    }
}

final class InsightsTests: XCTestCase {
    private let calendar = Calendar.current

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))!.addingTimeInterval(3600 * 10)
    }

    private func completed(_ offset: Int) -> TaskItem {
        var task = TaskItem(title: "t")
        task.isCompleted = true
        task.completedAt = day(offset)
        return task
    }

    func testStreakCountsConsecutiveDays() {
        let tasks = [completed(0), completed(-1), completed(-2), completed(-5)]
        let summary = InsightsSummary.compute(tasks: tasks, sessions: [])
        XCTAssertEqual(summary.currentStreak, 3)
        XCTAssertEqual(summary.bestStreak, 3)
        XCTAssertEqual(summary.completedToday, 1)
    }

    func testStreakSurvivesUntilEndOfToday() {
        let sessions = [FocusSession(start: day(-1), duration: 1500), FocusSession(start: day(-2), duration: 600)]
        let summary = InsightsSummary.compute(tasks: [], sessions: sessions)
        XCTAssertEqual(summary.currentStreak, 2)
        XCTAssertEqual(Int(summary.totalFocusMinutes), 35)
    }

    func testBrokenStreak() {
        let summary = InsightsSummary.compute(tasks: [completed(-3)], sessions: [])
        XCTAssertEqual(summary.currentStreak, 0)
        XCTAssertEqual(summary.bestStreak, 1)
    }
}

final class HTTPParsingTests: XCTestCase {
    func testParsesCompleteRequest() {
        let raw = "POST /mcp?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 2\r\nAuthorization: Bearer abc\r\n\r\n{}"
        guard case .complete(let request) = HTTPRequest.parse(Data(raw.utf8)) else {
            return XCTFail("expected a complete request")
        }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/mcp")
        XCTAssertEqual(request.headers["authorization"], "Bearer abc")
        XCTAssertEqual(request.body, Data("{}".utf8))
    }

    func testWaitsForBody() {
        let raw = "POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}"
        guard case .incomplete = HTTPRequest.parse(Data(raw.utf8)) else {
            return XCTFail("expected incomplete")
        }
    }
}
