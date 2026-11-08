import Foundation
#if canImport(CoreGraphics)
// On macOS, CGRect's members and Equatable come from here. Linux Foundation has them.
import CoreGraphics
#endif

/// Something the action bar does with the selected text.
public enum TextAction: String, CaseIterable, Codable, Sendable {
    case search, cut, copy, paste, openLink, addToStack, uppercase, lowercase, titleCase

    /// The label on the bar's button.
    public var title: String {
        switch self {
        case .cut: "Cut"
        case .copy: "Copy"
        case .paste: "Paste"
        case .search: "Search"
        case .openLink: "Open"
        case .addToStack: "Stack"
        case .uppercase: "ABC"
        case .lowercase: "abc"
        case .titleCase: "Abc"
        }
    }

    /// The menu item's title, and the button's tooltip.
    public var menuTitle: String {
        switch self {
        case .cut: "Cut"
        case .copy: "Copy"
        case .paste: "Paste"
        case .search: "Search the Web"
        case .openLink: "Open Link"
        case .addToStack: "Add to Paste Stack"
        case .uppercase: "Make UPPERCASE"
        case .lowercase: "Make lowercase"
        case .titleCase: "Make Title Case"
        }
    }

    /// Typed without modifiers while the bar is open, runs the action. A
    /// letter per action, so the keys don't move when an action is hidden.
    public var key: Character {
        switch self {
        case .cut: "x"
        case .copy: "c"
        case .paste: "v"
        case .search: "s"
        case .openLink: "o"
        case .addToStack: "a"
        case .uppercase: "u"
        case .lowercase: "l"
        case .titleCase: "t"
        }
    }

    /// Non-nil for the actions that replace the selection with a new case.
    public var textCase: TextCase? {
        switch self {
        case .uppercase: .upper
        case .lowercase: .lower
        case .titleCase: .title
        default: nil
        }
    }

    /// True for the actions that change the selected text, which only
    /// make sense where it can be edited.
    public var editsText: Bool {
        switch self {
        case .cut, .paste, .uppercase, .lowercase, .titleCase: true
        default: false
        }
    }

    /// The bar's actions for `text`, in order. Open Link only for a web or
    /// email address; Paste only when the clipboard has text. Cut, Paste and
    /// the case changes only where the text is editable; nil means unknown,
    /// and then they're offered.
    public static func available(for text: String, canPaste: Bool, isEditable: Bool? = nil) -> [TextAction] {
        let editable = isEditable ?? true
        return allCases.filter { action in
            if action.editsText, !editable { return false }
            switch action {
            case .openLink: return LinkDetector.url(in: text) != nil
            case .paste: return canPaste
            default: return true
            }
        }
    }
}

public enum TextCase: String, CaseIterable, Sendable {
    case upper, lower, title

    public func apply(to text: String) -> String {
        switch self {
        case .upper: text.uppercased()
        case .lower: text.lowercased()
        case .title: Self.titleCased(text)
        }
    }

    /// Each word's first letter upper case and the rest lower case, like
    /// Foundation's `capitalized`, but the same on every platform. A word
    /// starts after whitespace, `-` or `/`. Leading punctuation is skipped,
    /// so `(hello` becomes `(Hello`; an apostrophe inside a word isn't a
    /// break, so `don't` becomes `Don't`.
    private static func titleCased(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var atWordStart = true
        for character in text {
            if character.isWhitespace || character == "-" || character == "/" {
                atWordStart = true
                result.append(character)
            } else if character.isLetter || character.isNumber {
                result += atWordStart ? String(character).uppercased() : String(character).lowercased()
                atWordStart = false
            } else {
                result.append(character)
            }
        }
        return result
    }
}

/// The counts the bar shows next to its buttons.
public struct TextStats: Equatable, Sendable {
    /// Runs of non-whitespace that hold at least one letter or digit. Text
    /// without spaces between words (Chinese, Japanese) counts as one word.
    public let words: Int
    /// User-perceived characters (grapheme clusters).
    public let characters: Int
    /// A trailing line break doesn't start another line.
    public let lines: Int

    public init(_ text: String) {
        characters = text.count
        words = text.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
            .count
        var pieces = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if pieces.last?.isEmpty == true { pieces.removeLast() }
        lines = pieces.count
    }

    /// "12 words · 64 characters", plus the line count when there's more than one.
    public var summary: String {
        var parts = [Self.count(words, "word"), Self.count(characters, "character")]
        if lines > 1 { parts.append(Self.count(lines, "line")) }
        return parts.joined(separator: " · ")
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}

/// Finds a web or email address in a selection, for Open Link.
public enum LinkDetector {
    /// Selected text may only open a browser or a mail window. `file:` and
    /// app schemes are refused: a selection shouldn't launch programs.
    public static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    /// Without a scheme, `name.txt` or `README.md` would look like a domain.
    /// So a bare host must end in one of these, or start with `www.`.
    public static let bareTLDs: Set<String> = [
        "com", "org", "net", "edu", "gov", "mil", "int",
        "io", "dev", "app", "ai", "co", "me", "info", "biz", "xyz", "tech", "site", "online", "blog", "page",
        "us", "uk", "ca", "au", "nz", "ie", "de", "fr", "es", "it", "nl", "be", "ch", "at",
        "se", "no", "dk", "fi", "is", "eu", "pl", "cz", "pt", "jp", "kr", "cn", "tw", "hk", "sg", "in", "br", "mx",
    ]

    /// The URL a selection names, or nil. The selection must be a single
    /// token (surrounding whitespace, `<>`, quotes, parentheses and a trailing
    /// `.` or `,` are ignored). Bare hosts get `https://`; a bare email
    /// address gets `mailto:`.
    public static func url(in text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 2048, !s.contains(where: \.isWhitespace) else { return nil }
        // "(https://example.com)." needs both, in turns.
        var previous = ""
        while s != previous {
            previous = s
            s = withoutTrailingPunctuation(unwrapped(s))
        }
        guard !s.isEmpty else { return nil }

        let lower = s.lowercased()
        if let separator = lower.range(of: "://") {
            let scheme = String(lower[..<separator.lowerBound])
            guard scheme == "http" || scheme == "https",
                  let url = URL(string: s), let host = url.host, !host.isEmpty
            else { return nil }
            return url
        }
        if lower.hasPrefix("mailto:") {
            return isEmail(String(s.dropFirst("mailto:".count))) ? URL(string: s) : nil
        }
        if isEmail(s) {
            return URL(string: "mailto:" + s)
        }
        guard isBareHost(s) else { return nil }
        return URL(string: "https://" + s)
    }

    private static let wrappers: [(Character, Character)] = [
        ("<", ">"), ("\"", "\""), ("'", "'"), ("(", ")"), ("[", "]"), ("“", "”"), ("‘", "’"),
    ]

    private static func unwrapped(_ s: String) -> String {
        var s = s
        var changed = true
        while changed, s.count >= 2 {
            changed = false
            for (open, close) in wrappers where s.first == open && s.last == close {
                s = String(s.dropFirst().dropLast())
                changed = true
            }
        }
        return s
    }

    /// Drops sentence punctuation after the address. A closing parenthesis
    /// or bracket stays when it closes one inside the URL (Wikipedia links).
    private static func withoutTrailingPunctuation(_ s: String) -> String {
        var s = s
        while let last = s.last {
            if ".,;:!?".contains(last) {
                s.removeLast()
            } else if last == ")" || last == "]" {
                let open: Character = last == ")" ? "(" : "["
                guard s.filter({ $0 == last }).count > s.filter({ $0 == open }).count else { break }
                s.removeLast()
            } else {
                break
            }
        }
        return s
    }

    private static func isEmail(_ s: String) -> Bool {
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[0].count <= 64 else { return false }
        let localAllowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+/=?^_`{|}~-")
        guard parts[0].allSatisfy(localAllowed.contains),
              !parts[0].hasPrefix("."), !parts[0].hasSuffix(".")
        else { return false }
        return isHost(String(parts[1]), requireKnownTLD: false)
    }

    /// `host[:port][/path][?query][#fragment]` with a host we'd recognize.
    private static func isBareHost(_ s: String) -> Bool {
        let hostEnd = s.firstIndex { "/?#".contains($0) } ?? s.endIndex
        var host = String(s[..<hostEnd])
        if let colon = host.firstIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            guard port.count <= 5, port.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(port), (1...65535).contains(number)
            else { return false }
            host = String(host[..<colon])
        }
        let isWWW = host.lowercased().hasPrefix("www.")
        return isHost(host, requireKnownTLD: !isWWW)
    }

    private static func isHost(_ host: String, requireKnownTLD: Bool) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, host.count <= 253 else { return false }
        let labelAllowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        for label in labels {
            guard (1...63).contains(label.count),
                  label.allSatisfy(labelAllowed.contains),
                  label.first != "-", label.last != "-"
            else { return false }
        }
        let tld = labels.last!.lowercased()
        guard tld.count >= 2, tld.allSatisfy(\.isLetter) else { return false }
        return !requireKnownTLD || bareTLDs.contains(tld)
    }
}

/// Where Search sends the selection.
public enum SearchEngine: String, CaseIterable, Codable, Sendable {
    case duckDuckGo, google, kagi, bing, ecosia

    public var title: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .kagi: "Kagi"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        }
    }

    private var base: String {
        switch self {
        case .duckDuckGo: "https://duckduckgo.com/?q="
        case .google: "https://www.google.com/search?q="
        case .kagi: "https://kagi.com/search?q="
        case .bing: "https://www.bing.com/search?q="
        case .ecosia: "https://www.ecosia.org/search?q="
        }
    }

    /// Longer selections are cut to this many characters.
    public static let maxQueryLength = 500

    /// Whitespace runs, line breaks included, become single spaces. Every
    /// character but `A–Z a–z 0–9 - . _ ~` is percent-encoded, so `+` and
    /// `&` in the selection reach the engine as typed (`c++` stays `c++`).
    public func url(for text: String) -> URL? {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        let query = String(words.joined(separator: " ").prefix(Self.maxQueryLength))
        guard !query.isEmpty else { return nil }
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        return URL(string: base + encoded)
    }
}

/// Where the action bar goes.
public enum BarPlacement {
    /// The bar's bottom-left corner, in AppKit screen coordinates (y grows
    /// up). Centered above `anchor` with `gap` between them; below it when
    /// there's no room above; always inside `visibleFrame` inset by `margin`.
    public static func origin(
        for size: CGSize,
        anchor: CGRect,
        visibleFrame: CGRect,
        gap: CGFloat = 8,
        margin: CGFloat = 4
    ) -> CGPoint {
        let bounds = visibleFrame.insetBy(dx: margin, dy: margin)
        var x = anchor.midX - size.width / 2
        x = min(max(x, bounds.minX), bounds.maxX - size.width)
        var y = anchor.maxY + gap
        if y + size.height > bounds.maxY {
            y = anchor.minY - gap - size.height
        }
        y = min(max(y, bounds.minY), bounds.maxY - size.height)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}
