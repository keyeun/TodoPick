import Foundation

// MARK: - Model

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    /// "yyyy-MM-dd" of the day this item was picked for. nil = 생각함(inbox).
    var pickedDay: String? = nil
    /// Priority within the day. Lower = more important.
    var order: Int = 0
    var doneAt: Date? = nil
    /// How many times it bounced back to the inbox unfinished.
    var bounced: Int = 0
    /// Free-form type such as "운동", "연구", "TA", "회의".
    var tag: String? = nil
    /// The big task (마감) this item is a piece of.
    var deadlineID: UUID? = nil
}

struct TagInfo: Codable, Equatable {
    var name: String
    var uses: Int
}

/// One line in `archive/YYYY-MM.jsonl`.
struct ArchiveRecord: Codable {
    var kind: String
    var task: TodoItem?
    var deadline: Deadline?
    var doneAt: Date
    var archivedAt = Date()

    init(task: TodoItem, doneAt: Date) { kind = "task"; self.task = task; self.doneAt = doneAt }
    init(deadline: Deadline, doneAt: Date) { kind = "deadline"; self.deadline = deadline; self.doneAt = doneAt }
}

/// A big task with a due date, e.g. "논문 리뷰" by 11/5.
struct Deadline: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// "yyyy-MM-dd"
    var due: String
    var createdAt = Date()
    var doneAt: Date? = nil

    /// Short handle used after `@` and on task rows: the first word.
    var label: String { String(name.split(separator: " ").first ?? Substring(name)) }
}

/// Pulls the first `#태그` and `@마감` out of the text.
func parseTag(_ text: String) -> (title: String, tag: String?, mention: String?) {
    var tag: String?
    var mention: String?
    var words: [Substring] = []
    for word in text.split(separator: " ", omittingEmptySubsequences: true) {
        if word.hasPrefix("#") && word.count > 1 {
            if tag == nil { tag = String(word.dropFirst()) }
        } else if word.hasPrefix("@") && word.count > 1 {
            if mention == nil { mention = String(word.dropFirst()) }
        } else {
            words.append(word)
        }
    }
    return (words.joined(separator: " "), tag, mention)
}

/// "논문 리뷰 11/5", "기말 프로젝트 12.10", "보고서 11월 3일", "Paper review Nov 5", "X 2027-01-10"
/// → name + "yyyy-MM-dd".
func parseDeadline(_ text: String, today: Date = Date()) -> (name: String, due: String)? {
    let cal = Calendar(identifier: .gregorian)
    let patterns = [
        #"(\d{4})-(\d{1,2})-(\d{1,2})"#,
        #"(\d{1,2})\s*월\s*(\d{1,2})\s*일?"#,
        #"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s*(\d{1,2})(?:st|nd|rd|th)?\b"#,
        #"(\d{1,2})[/.](\d{1,2})"#,
    ]
    for pattern in patterns {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.matches(in: text, range: NSRange(text.startIndex..., in: text)).last else { continue }
        let nums = (1..<m.numberOfRanges).compactMap { i in
            Range(m.range(at: i), in: text).flatMap { Int(text[$0]) ?? monthNumber(String(text[$0])) }
        }
        var comps = DateComponents()
        if nums.count == 3 {
            comps.year = nums[0]; comps.month = nums[1]; comps.day = nums[2]
        } else if nums.count == 2 {
            comps.year = cal.component(.year, from: today); comps.month = nums[0]; comps.day = nums[1]
        } else { continue }
        guard var date = cal.date(from: comps), cal.component(.day, from: date) == comps.day else { continue }
        // "1/10" typed in October means next January.
        if nums.count == 2, let days = cal.dateComponents([.day], from: today, to: date).day, days < -60 {
            date = cal.date(byAdding: .year, value: 1, to: date) ?? date
        }
        var name = text
        name.removeSubrange(Range(m.range, in: text)!)
        name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return (name, TodoStore.dayKey(date))
    }
    return nil
}

/// "Nov", "november" → 11.
private func monthNumber(_ name: String) -> Int? {
    let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    return months.firstIndex(of: String(name.lowercased().prefix(3))).map { $0 + 1 }
}
