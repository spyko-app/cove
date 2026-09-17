import XCTest
@testable import Cove

final class LRCParserTests: XCTestCase {

    func testParsesTwoDigitMilliseconds() {
        let lrc = "[00:12.34]Primeira linha"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines, [LyricLine(time: 12.34, text: "Primeira linha")])
    }

    func testParsesThreeDigitMilliseconds() {
        let lrc = "[00:12.340]Primeira linha"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].time, 12.340, accuracy: 0.0001)
        XCTAssertEqual(lines[0].text, "Primeira linha")
    }

    func testParsesMinutesCorrectly() {
        let lrc = "[01:05.00]Um minuto e cinco"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.first?.time, 65.0)
    }

    func testMultipleTimestampsSameLine() {
        let lrc = "[00:10.00][00:20.00]Refrão repetido"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], LyricLine(time: 10.0, text: "Refrão repetido"))
        XCTAssertEqual(lines[1], LyricLine(time: 20.0, text: "Refrão repetido"))
    }

    func testIgnoresMetadataTags() {
        let lrc = """
        [ar:Artista]
        [ti:Título]
        [al:Álbum]
        [00:05.00]Letra real
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines, [LyricLine(time: 5.0, text: "Letra real")])
    }

    func testIgnoresOffsetTag() {
        let lrc = "[offset:0]\n[00:01.00]Ok"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines, [LyricLine(time: 1.0, text: "Ok")])
    }

    func testSortsByTime() {
        let lrc = """
        [00:30.00]Terceira
        [00:05.00]Primeira
        [00:15.00]Segunda
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.map(\.text), ["Primeira", "Segunda", "Terceira"])
    }

    func testSkipsBlankLines() {
        let lrc = "[00:01.00]Linha 1\n\n[00:02.00]Linha 2"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 2)
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(LRCParser.parse(""), [])
    }

    func testCurrentIndexBeforeFirstLine() {
        let lines = [LyricLine(time: 5, text: "A"), LyricLine(time: 10, text: "B")]
        XCTAssertNil(LRCParser.currentIndex(lines, at: 0))
        XCTAssertNil(LRCParser.currentIndex(lines, at: 4.999))
    }

    func testCurrentIndexAtExactBoundary() {
        let lines = [LyricLine(time: 5, text: "A"), LyricLine(time: 10, text: "B")]
        XCTAssertEqual(LRCParser.currentIndex(lines, at: 5), 0)
        XCTAssertEqual(LRCParser.currentIndex(lines, at: 10), 1)
    }

    func testCurrentIndexBetweenLines() {
        let lines = [LyricLine(time: 5, text: "A"), LyricLine(time: 10, text: "B")]
        XCTAssertEqual(LRCParser.currentIndex(lines, at: 7), 0)
    }

    func testCurrentIndexAfterLastLine() {
        let lines = [LyricLine(time: 5, text: "A"), LyricLine(time: 10, text: "B")]
        XCTAssertEqual(LRCParser.currentIndex(lines, at: 999), 1)
    }

    func testCurrentIndexEmptyLines() {
        XCTAssertNil(LRCParser.currentIndex([], at: 5))
    }
}
