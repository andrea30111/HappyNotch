import XCTest
@testable import Notchy

final class AppleNotesTests: XCTestCase {
    func testDayFromTitle() {
        XCTAssertEqual(NotesScript.day(fromTitle: "Notchy · 2026-11-01"), "2026-11-01")
        XCTAssertNil(NotesScript.day(fromTitle: "Shopping 2026-11-01"))
        XCTAssertNil(NotesScript.day(fromTitle: "Notchy · someday"))
    }

    func testBodyDropsTitleAndNormalizes() {
        let plaintext = "Notchy · 2026-11-01\r\nfirst\u{00A0}line  \n\nsecond\n"
        XCTAssertEqual(NotesScript.body(fromPlaintext: plaintext), "first line\n\nsecond")
        XCTAssertEqual(NotesScript.body(fromPlaintext: "Notchy · 2026-11-01"), "")
    }

    func testHTMLEscapesAndKeepsBlankLines() {
        let html = NotesScript.html(day: "2026-11-01", text: "a < b & c\n\nd")
        XCTAssertEqual(html, "<div><h1>Notchy · 2026-11-01</h1></div><div>a &lt; b &amp; c</div><div><br></div><div>d</div>")
    }

    func testParsesFetchOutput() {
        let output = "id1\u{1F}Notchy · 2026-11-01\u{1F}Notchy · 2026-11-01\nhello\u{1E}id2\u{1F}Groceries\u{1F}Groceries\nmilk"
        let notes = NotesScript.parseFetchOutput(output)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].day, "2026-11-01")
        XCTAssertEqual(notes[0].text, "hello")
        XCTAssertNil(notes[1].day)
        XCTAssertTrue(NotesScript.parseFetchOutput("").isEmpty)
    }

    func testParsesPermissionError() {
        let error = NotesScript.parseError("0:12: execution error: Not authorized to send Apple events to Notes. (-1743)\n")
        XCTAssertEqual(error.number, -1743)
        XCTAssertTrue(error.isPermissionDenied)
        XCTAssertEqual(error.message, "Not authorized to send Apple events to Notes.")
    }

    func testMergeKeepsBothSides() {
        XCTAssertEqual(AppleNotesSync.merge(local: "", remote: "r"), "r")
        XCTAssertEqual(AppleNotesSync.merge(local: "same", remote: "same"), "same")
        XCTAssertEqual(AppleNotesSync.merge(local: "abc", remote: "abc\nmore"), "abc\nmore")
        XCTAssertEqual(AppleNotesSync.merge(local: "local", remote: "remote"), "local\n\nremote")
    }
}
