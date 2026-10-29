// Logic tests. Run with `./build.sh test` — uses a throwaway data folder, never your real one.
import SwiftUI
import AppKit

@main
struct Tests {
    static var failures = 0

    static func check(_ ok: Bool, _ name: String) {
        print(ok ? "  ✓ \(name)" : "  ✗ \(name)")
        if !ok { failures += 1 }
    }

    static let day: TimeInterval = 86_400
    static let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TODOPICK_DIR"] ?? NSTemporaryDirectory())

    /// A store backed by a fresh folder seeded with the given data.
    static func store(_ name: String, items: [TodoItem] = [], deadlines: [Deadline] = []) -> TodoStore {
        let dir = root.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(items).write(to: dir.appendingPathComponent("tasks.json"))
        try? JSONEncoder().encode(deadlines).write(to: dir.appendingPathComponent("deadlines.json"))
        setenv("TODOPICK_DIR", dir.path, 1)
        return TodoStore()
    }

    @MainActor static func main() {
        let today = TodoStore.dayKey()
        let yesterday = TodoStore.dayKey(Date().addingTimeInterval(-day))
        let longAgo = Date().addingTimeInterval(-40 * day)
        let recently = Date().addingTimeInterval(-10 * day)

        print("parsing")
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        check(parseDeadline("논문 리뷰 12/28", today: Date())?.name == "논문 리뷰", "deadline name")
        check(parseDeadline("보고서 11월 3일")?.due.hasSuffix("-11-03") == true, "Korean date")
        check(parseDeadline("프로젝트 12.5")?.due.hasSuffix("-12-05") == true, "dotted date")
        check(parseDeadline("X 2031-02-01")?.due == "2031-02-01", "ISO date")
        check(parseDeadline("날짜 없음") == nil, "missing date rejected")
        check(parseDeadline("없는 날 2/30") == nil, "invalid date rejected")
        let jan = parseDeadline("겨울 학회 1/10", today: Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 10, day: 20))!)
        check(jan?.due == "\(year + 1)-01-10", "past month rolls to next year")
        let p = parseTag("리뷰 초안 #연구 @논문")
        check(p.title == "리뷰 초안" && p.tag == "연구" && p.mention == "논문", "#tag and @deadline")

        print("rollover")
        do {
            let s = store("rollover", items: [
                TodoItem(title: "unfinished", pickedDay: yesterday),
                TodoItem(title: "finished", pickedDay: yesterday, doneAt: Date().addingTimeInterval(-day)),
            ])
            let unfinished = s.items.first { $0.title == "unfinished" }!
            check(unfinished.pickedDay == nil && unfinished.bounced == 1, "unfinished task goes back to 생각함")
            check(s.items.first { $0.title == "finished" }!.pickedDay == yesterday, "finished task stays put")
        }

        print("deadlines")
        do {
            let a = Deadline(name: "A", due: yesterday), b = Deadline(name: "B", due: yesterday)
            let c = Deadline(name: "C", due: yesterday), d = Deadline(name: "D", due: today)
            let s = store("deadlines", items: [
                TodoItem(title: "a1", doneAt: Date(), deadlineID: a.id),
                TodoItem(title: "c1", doneAt: Date(), deadlineID: c.id),
                TodoItem(title: "c2", deadlineID: c.id),
                TodoItem(title: "d1", doneAt: Date(), deadlineID: d.id),
            ], deadlines: [a, b, c, d])
            let active = Set(s.activeDeadlines.map(\.name))
            check(!active.contains("A"), "overdue + split + all done → auto-finished")
            check(active.contains("B"), "overdue + never split → stays")
            check(active.contains("C"), "overdue + partly done → stays")
            check(active.contains("D"), "due today + all done → stays (asks instead)")
            check(s.resolveDeadline("c") == c.id, "@ mention resolves")
        }

        print("archive")
        do {
            let live = Deadline(name: "Live", due: TodoStore.dayKey(Date().addingTimeInterval(5 * day)))
            var old = Deadline(name: "Old", due: TodoStore.dayKey(longAgo))
            old.doneAt = longAgo
            let s = store("archive", items: [
                TodoItem(title: "old done", doneAt: longAgo, tag: "운동"),
                TodoItem(title: "recent done", doneAt: recently),
                TodoItem(title: "old but linked", doneAt: longAgo, deadlineID: live.id),
                TodoItem(title: "open", tag: "연구"),
            ], deadlines: [live, old])
            let titles = Set(s.items.map(\.title))
            check(!titles.contains("old done"), "done > 30 days ago → archived")
            check(titles.contains("recent done"), "done 10 days ago → kept")
            check(titles.contains("old but linked"), "kept while its deadline is active")
            check(titles.contains("open"), "open task kept")
            check(!s.deadlines.contains { $0.name == "Old" }, "finished deadline > 30 days → archived")

            let dir = s.dataDir.appendingPathComponent("archive")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            let text = files.compactMap { try? String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }.joined()
            check(text.contains("old done") && text.contains("\"Old\""), "archive file holds the records")
            check(s.knownTags.contains("운동"), "tag survives after its tasks are archived")

            let mode = { (path: String) in (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int) ?? -1 }
            check(mode(s.dataDir.path) == 0o700, "data folder is 0700")
            check(mode(s.dataDir.appendingPathComponent("tasks.json").path) == 0o600, "tasks.json is 0600")
            check(files.allSatisfy { mode(dir.appendingPathComponent($0).path) == 0o600 }, "archive files are 0600")
        }

        print("tags")
        do {
            let s = store("tags")
            s.add("a #연구")
            s.add("b #운동")
            let color = s.tagColor("운동")
            s.add("c #연구")
            check(s.tagColor("운동") == color, "tag color stays as usage changes")
            check(s.knownTags.first == "연구", "most used tag first")
            s.forgetTag("운동")
            check(!s.knownTags.contains("운동"), "forgotten tag removed")
        }

        print(failures == 0 ? "\n✅ All tests passed" : "\n❌ \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
