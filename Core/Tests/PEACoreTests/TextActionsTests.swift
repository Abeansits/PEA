import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import PEACore

final class TextActionsTests: XCTestCase {
    // MARK: Actions

    func testEveryActionHasItsOwnKey() {
        let keys = TextAction.allCases.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(keys.allSatisfy { $0.isLetter && $0.isLowercase })
    }

    func testOpenLinkAndPasteShowOnlyWhenTheyCanWork() {
        XCTAssertEqual(
            TextAction.available(for: "hello world", canPaste: false),
            [.search, .cut, .copy, .addToStack, .uppercase, .lowercase, .titleCase]
        )
        XCTAssertEqual(
            TextAction.available(for: "example.com", canPaste: true),
            [.search, .cut, .copy, .paste, .openLink, .addToStack, .uppercase, .lowercase, .titleCase]
        )
    }

    func testReadOnlyTextGetsNoEditingActions() {
        XCTAssertEqual(
            TextAction.available(for: "example.com", canPaste: true, isEditable: false),
            [.search, .copy, .openLink, .addToStack]
        )
        XCTAssertEqual(
            TextAction.available(for: "hello", canPaste: true, isEditable: true),
            TextAction.available(for: "hello", canPaste: true, isEditable: nil)
        )
        XCTAssertEqual(TextAction.allCases.filter(\.editsText), [.cut, .paste, .uppercase, .lowercase, .titleCase])
    }

    // MARK: Case

    func testCaseChanges() {
        XCTAssertEqual(TextCase.upper.apply(to: "Hello, wörld"), "HELLO, WÖRLD")
        XCTAssertEqual(TextCase.lower.apply(to: "Hello, WÖRLD"), "hello, wörld")
    }

    func testTitleCase() {
        let cases: [(String, String)] = [
            ("hello WORLD", "Hello World"),
            ("don't stop", "Don't Stop"),
            ("(quoted) 'words'", "(Quoted) 'Words'"),
            ("well-known and/or", "Well-Known And/Or"),
            ("  two  spaces\nnew line", "  Two  Spaces\nNew Line"),
            ("3d printing", "3d Printing"),
            ("élan vital", "Élan Vital"),
            ("", ""),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(TextCase.title.apply(to: input), expected, input)
        }
    }

    func testCaseActionsMapToCases() {
        XCTAssertEqual(TextAction.uppercase.textCase, .upper)
        XCTAssertEqual(TextAction.lowercase.textCase, .lower)
        XCTAssertEqual(TextAction.titleCase.textCase, .title)
        XCTAssertNil(TextAction.copy.textCase)
    }

    // MARK: Stats

    func testStats() {
        let cases: [(String, words: Int, characters: Int, lines: Int)] = [
            ("Hello, world!", 2, 13, 1),
            ("one\ntwo three\n", 3, 14, 2),
            ("a\r\nb", 2, 3, 2),
            ("  —  ", 0, 5, 1),
            ("👍🏽", 0, 1, 1),
            ("", 0, 0, 0),
        ]
        for (text, words, characters, lines) in cases {
            let stats = TextStats(text)
            XCTAssertEqual(stats.words, words, "words in \(text.debugDescription)")
            XCTAssertEqual(stats.characters, characters, "characters in \(text.debugDescription)")
            XCTAssertEqual(stats.lines, lines, "lines in \(text.debugDescription)")
        }
    }

    func testStatsSummary() {
        XCTAssertEqual(TextStats("word").summary, "1 word · 4 characters")
        XCTAssertEqual(TextStats("two words").summary, "2 words · 9 characters")
        XCTAssertEqual(TextStats("a\nb").summary, "2 words · 3 characters · 2 lines")
    }

    // MARK: Links

    func testFindsLinks() {
        let cases: [(String, String)] = [
            ("https://example.com/a?b=c#d", "https://example.com/a?b=c#d"),
            ("  http://localhost:3000/  ", "http://localhost:3000/"),
            ("example.com", "https://example.com"),
            ("Example.COM/path", "https://Example.COM/path"),
            ("www.example.museum", "https://www.example.museum"),
            ("example.com:8080/x", "https://example.com:8080/x"),
            ("<https://example.com>", "https://example.com"),
            ("(https://example.com).", "https://example.com"),
            ("https://example.com/page.", "https://example.com/page"),
            ("https://en.wikipedia.org/wiki/Swift_(programming_language)",
             "https://en.wikipedia.org/wiki/Swift_(programming_language)"),
            ("“example.org”", "https://example.org"),
            ("user@example.com", "mailto:user@example.com"),
            ("first.last+tag@mail.example.co.uk", "mailto:first.last+tag@mail.example.co.uk"),
            ("mailto:user@example.com", "mailto:user@example.com"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(LinkDetector.url(in: input)?.absoluteString, expected, input)
        }
    }

    func testLeavesNonLinksAlone() {
        let cases = [
            "", "hello", "hello world", "two example.com words",
            "README.md", "notes.txt", "Node.js", "main.swift", "v1.2.3", "e.g.", "3.14",
            "file:///Applications/Calculator.app", "ftp://example.com", "javascript:alert(1)",
            "x-apple.systempreferences:com.apple.preference.security",
            "http://", "mailto:nobody", "@example.com", "user@", "user@localhost",
            "-bad.com", "bad-.com", "example.com:99999",
        ]
        for input in cases {
            XCTAssertNil(LinkDetector.url(in: input), input)
        }
    }

    // MARK: Search

    func testSearchURLsEncodeEverythingButUnreservedCharacters() {
        XCTAssertEqual(
            SearchEngine.duckDuckGo.url(for: "c++ & a=b")?.absoluteString,
            "https://duckduckgo.com/?q=c%2B%2B%20%26%20a%3Db"
        )
        XCTAssertEqual(
            SearchEngine.google.url(for: "  multi\n line\ttext ")?.absoluteString,
            "https://www.google.com/search?q=multi%20line%20text"
        )
        XCTAssertEqual(
            SearchEngine.kagi.url(for: "smörgåsbord")?.absoluteString,
            "https://kagi.com/search?q=sm%C3%B6rg%C3%A5sbord"
        )
        XCTAssertNil(SearchEngine.bing.url(for: " \n "))
    }

    func testSearchCutsLongSelections() {
        let long = String(repeating: "a", count: SearchEngine.maxQueryLength + 50)
        let url = SearchEngine.ecosia.url(for: long)
        XCTAssertEqual(url?.absoluteString, "https://www.ecosia.org/search?q=" + String(repeating: "a", count: SearchEngine.maxQueryLength))
    }

    func testEveryEngineMakesAURL() {
        for engine in SearchEngine.allCases {
            XCTAssertNotNil(engine.url(for: "test"), engine.title)
        }
    }

    // MARK: Placement

    // A 1440×875 visible area starting at y 0 (AppKit coordinates, y up).
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let bar = CGSize(width: 400, height: 36)

    func testBarSitsCenteredAboveTheSelection() {
        let selection = CGRect(x: 500, y: 400, width: 200, height: 20)
        XCTAssertEqual(
            BarPlacement.origin(for: bar, anchor: selection, visibleFrame: visible),
            CGPoint(x: 400, y: 428)
        )
    }

    func testBarGoesBelowWhenThereIsNoRoomAbove() {
        let selection = CGRect(x: 500, y: 850, width: 200, height: 20)
        XCTAssertEqual(
            BarPlacement.origin(for: bar, anchor: selection, visibleFrame: visible),
            CGPoint(x: 400, y: 806)
        )
    }

    func testBarStaysOnScreen() {
        let nearLeftEdge = CGRect(x: 10, y: 400, width: 20, height: 20)
        XCTAssertEqual(BarPlacement.origin(for: bar, anchor: nearLeftEdge, visibleFrame: visible).x, 4)
        let nearRightEdge = CGRect(x: 1430, y: 400, width: 10, height: 20)
        XCTAssertEqual(BarPlacement.origin(for: bar, anchor: nearRightEdge, visibleFrame: visible).x, 1036)
        // Taller than the screen: neither above nor below fits.
        let huge = CGRect(x: 500, y: -100, width: 200, height: 1100)
        let origin = BarPlacement.origin(for: bar, anchor: huge, visibleFrame: visible)
        XCTAssertEqual(origin, CGPoint(x: 400, y: 4))
    }
}
