import Foundation

struct ParsedTask: Equatable {
    var title: String
    var dueDate: Date?
    var hasTime: Bool
    var priority: Priority
}

/// Turns "call mom tomorrow at 5pm !high" into a title, a due date (with or without a time)
/// and a priority. Dates come from `NSDataDetector`, so this runs fully offline.
enum NaturalLanguageParser {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    private static let priorityTokens: [String: Priority] = [
        "!!!": .high, "!high": .high, "p1": .high,
        "!!": .medium, "!medium": .medium, "!med": .medium, "p2": .medium,
        "!low": .low, "p3": .low,
    ]

    private static let timePattern = try! NSRegularExpression(
        pattern: #"(\b\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)|\b\d{1,2}:\d{2}\b|\b(noon|midnight|morning|afternoon|evening|tonight)\b|\bat \d{1,2}\b|\bin \d+\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours)\b)"#,
        options: [.caseInsensitive]
    )

    private static let dayPattern = try! NSRegularExpression(
        pattern: #"\b(today|tonight|tomorrow|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next|this|week|month|jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec|january|february|march|april|june|july|august|september|october|november|december|\d{1,2}/\d{1,2})\b"#,
        options: [.caseInsensitive]
    )

    private static let danglingPattern = try! NSRegularExpression(
        pattern: #"\s+(at|on|by|due|for|in|from)$"#,
        options: [.caseInsensitive]
    )

    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedTask {
        var priority = Priority.none
        var words: [Substring] = []
        for word in input.split(whereSeparator: \.isWhitespace) {
            if let p = priorityTokens[word.lowercased()] {
                priority = max(priority, p)
            } else {
                words.append(word)
            }
        }

        var text = words.joined(separator: " ")
        var dueDate: Date?
        var hasTime = false

        if let detector {
            let ns = text as NSString
            let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            if let match = matches.first(where: { $0.date != nil }), let date = match.date {
                let phrase = ns.substring(with: match.range)
                hasTime = contains(timePattern, in: phrase)
                if hasTime {
                    var resolved = date
                    // "at 5pm" with no day means the next 5pm, not one that already passed.
                    if !contains(dayPattern, in: phrase), resolved < now {
                        resolved = calendar.date(byAdding: .day, value: 1, to: resolved) ?? resolved
                    }
                    dueDate = resolved
                } else {
                    dueDate = calendar.startOfDay(for: date)
                }
                text = ns.replacingCharacters(in: match.range, with: " ")
            }
        }

        return ParsedTask(title: clean(text), dueDate: dueDate, hasTime: hasTime, priority: priority)
    }

    private static func contains(_ regex: NSRegularExpression, in text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func clean(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;-–")))
        while let match = danglingPattern.firstMatch(in: result, range: NSRange(location: 0, length: (result as NSString).length)) {
            result = (result as NSString).replacingCharacters(in: match.range, with: "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;-–")))
        }
        return result
    }
}
