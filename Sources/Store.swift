import SwiftUI
import AppKit

final class TodoStore: ObservableObject {
    @Published var items: [TodoItem] = [] { didSet { save() } }
    @Published private(set) var today: String = TodoStore.dayKey()
    /// 오늘의 한마디, keyed by day.
    @Published var quotes: [String: String] = [:] { didSet { saveQuotes() } }
    @Published var deadlines: [Deadline] = [] { didSet { saveDeadlines() } }
    /// Every tag ever made, in creation order (= color order), with use counts.
    @Published private(set) var tagRegistry: [TagInfo] = [] { didSet { saveTags() } }

    /// Completed tasks / finished deadlines older than this move to `archive/`.
    static let archiveAfterDays = 30

    let dataDir: URL
    private let fileURL: URL
    private let quotesURL: URL
    private let deadlinesURL: URL
    private let tagsURL: URL
    private var timer: Timer?
    private var lastArchiveDay: String?

    static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    init() {
        let dir = ProcessInfo.processInfo.environment["TODOPICK_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TodoPick", isDirectory: true)
        dataDir = dir
        // Only your macOS account can read the data folder.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        fileURL = dir.appendingPathComponent("tasks.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
            items = decoded
        }
        quotesURL = dir.appendingPathComponent("quotes.json")
        if let data = try? Data(contentsOf: quotesURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            quotes = decoded
        }
        deadlinesURL = dir.appendingPathComponent("deadlines.json")
        if let data = try? Data(contentsOf: deadlinesURL),
           let decoded = try? JSONDecoder().decode([Deadline].self, from: data) {
            deadlines = decoded
        }
        tagsURL = dir.appendingPathComponent("tags.json")
        if let data = try? Data(contentsOf: tagsURL),
           let decoded = try? JSONDecoder().decode([TagInfo].self, from: data) {
            tagRegistry = decoded
        } else {
            tagRegistry = Self.registryFromItems(items)
        }
        if !FileManager.default.fileExists(atPath: tagsURL.path) { saveTags() }
        // Tighten files written by older versions (0644 → 0600).
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasSuffix(".json") {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent(name).path)
        }
        rollover()

        let nc = NotificationCenter.default
        nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in self?.rollover() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.rollover() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.rollover() }
    }

    /// Atomic write, readable only by you (0600).
    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func save() { write(items, to: fileURL) }
    private func saveDeadlines() { write(deadlines, to: deadlinesURL) }
    private func saveQuotes() { write(quotes, to: quotesURL) }
    private func saveTags() { write(tagRegistry, to: tagsURL) }

    /// First run after upgrading: rebuild the registry from existing tasks.
    private static func registryFromItems(_ items: [TodoItem]) -> [TagInfo] {
        var registry: [TagInfo] = []
        for item in items.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let t = item.tag else { continue }
            if let i = registry.firstIndex(where: { $0.name == t }) { registry[i].uses += 1 }
            else { registry.append(TagInfo(name: t, uses: 1)) }
        }
        return registry
    }

    private func registerTag(_ tag: String?) {
        guard let tag else { return }
        if let i = tagRegistry.firstIndex(where: { $0.name == tag }) { tagRegistry[i].uses += 1 }
        else { tagRegistry.append(TagInfo(name: tag, uses: 1)) }
    }

    // MARK: Archive

    /// Moves old completed tasks and finished deadlines out of the live files into
    /// `archive/YYYY-MM.jsonl` (one JSON record per line, by completion month).
    /// Tasks still linked to an active deadline stay, so its progress stays right.
    func archiveOld(now: Date = Date()) {
        guard let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -Self.archiveAfterDays, to: now) else { return }
        let activeIDs = Set(activeDeadlines.map(\.id))

        let oldItems = items.filter { item in
            guard let done = item.doneAt, done < cutoff, item.pickedDay != today else { return false }
            return item.deadlineID.map { !activeIDs.contains($0) } ?? true
        }
        let oldItemIDs = Set(oldItems.map(\.id))
        let stillLinked = Set(items.filter { !oldItemIDs.contains($0.id) }.compactMap(\.deadlineID))
        let oldDeadlines = deadlines.filter { d in
            guard let done = d.doneAt, done < cutoff else { return false }
            return !stillLinked.contains(d.id)
        }
        guard !oldItems.isEmpty || !oldDeadlines.isEmpty else { return }

        let records = oldItems.map { ArchiveRecord(task: $0, doneAt: $0.doneAt!) }
            + oldDeadlines.map { ArchiveRecord(deadline: $0, doneAt: $0.doneAt!) }
        // Only drop from the live files once the archive write succeeded.
        guard appendToArchive(records) else { return }
        items.removeAll { oldItemIDs.contains($0.id) }
        let oldDeadlineIDs = Set(oldDeadlines.map(\.id))
        deadlines.removeAll { oldDeadlineIDs.contains($0.id) }
    }

    private func appendToArchive(_ records: [ArchiveRecord]) -> Bool {
        let dir = dataDir.appendingPathComponent("archive", isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let month = DateFormatter()
            month.locale = Locale(identifier: "en_US_POSIX")
            month.dateFormat = "yyyy-MM"
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            for (key, group) in Dictionary(grouping: records, by: { month.string(from: $0.doneAt) }) {
                let url = dir.appendingPathComponent("\(key).jsonl")
                if !fm.fileExists(atPath: url.path) {
                    fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
                }
                var lines = Data()
                for r in group {
                    lines.append(try encoder.encode(r))
                    lines.append(0x0A)
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: lines)
            }
            return true
        } catch {
            NSLog("TodoPick: archive write failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Unfinished items picked for a past day go back to the inbox.
    func rollover() {
        let now = Self.dayKey()
        if now != today { today = now }
        var changed = items
        var touched = false
        for i in changed.indices where changed[i].doneAt == nil {
            if let day = changed[i].pickedDay, day != now {
                changed[i].pickedDay = nil
                changed[i].bounced += 1
                touched = true
            }
        }
        if touched { items = changed }
        autoFinishDeadlines()
        if lastArchiveDay != now {
            lastArchiveDay = now
            archiveOld()
        }
    }

    /// Past due, broken into tasks, and every task done → it's finished; archive it.
    /// Deadlines never broken down stay as "지남" for you to settle by hand.
    private func autoFinishDeadlines() {
        let finished = activeDeadlines.filter { d in
            let p = pieces(of: d.id)
            return daysLeft(d) < 0 && p.total > 0 && p.done == p.total
        }
        guard !finished.isEmpty else { return }
        var changed = deadlines
        for i in changed.indices where finished.contains(where: { $0.id == changed[i].id }) {
            changed[i].doneAt = Date()
        }
        deadlines = changed
    }

    // MARK: Queries

    var inbox: [TodoItem] {
        items.filter { $0.pickedDay == nil && $0.doneAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var todayOpen: [TodoItem] {
        items.filter { $0.pickedDay == today && $0.doneAt == nil }
            .sorted { $0.order < $1.order }
    }

    var todayDone: [TodoItem] {
        items.filter { $0.pickedDay == today && $0.doneAt != nil }
            .sorted { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }
    }

    /// Every tag, most used first.
    var knownTags: [String] {
        tagRegistry.sorted { $0.uses != $1.uses ? $0.uses > $1.uses : $0.name < $1.name }.map(\.name)
    }

    /// Colors follow creation order, so a tag keeps its color even after its tasks are archived.
    func tagColor(_ tag: String) -> Color {
        let i = tagRegistry.firstIndex { $0.name == tag } ?? 0
        return Pal.tagColors[i % Pal.tagColors.count]
    }

    /// Today's 한마디, or the most recent one if today's isn't written yet.
    var latestQuote: (text: String, isToday: Bool)? {
        if let t = quotes[today] { return (t, true) }
        guard let last = quotes.keys.filter({ $0 < today }).max(), let t = quotes[last] else { return nil }
        return (t, false)
    }

    // MARK: Mutations

    func setQuote(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { quotes[today] = nil } else { quotes[today] = t }
    }

    private func update(_ id: UUID, _ change: (inout TodoItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    /// Adds one item per line. `#태그` / `@마감` in the line win over the defaults.
    func add(_ text: String, defaultTag: String? = nil, defaultDeadline: UUID? = nil) {
        let parsed = text.split(whereSeparator: \.isNewline)
            .map { parseTag($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.title.isEmpty }
        guard !parsed.isEmpty else { return }
        let base = Date()
        for p in parsed { registerTag(p.tag ?? defaultTag) }
        items.append(contentsOf: parsed.enumerated().map { i, p in
            TodoItem(title: p.title, createdAt: base.addingTimeInterval(Double(i) * 0.001), tag: p.tag ?? defaultTag,
                     deadlineID: p.mention.flatMap(resolveDeadline) ?? defaultDeadline)
        })
    }

    // MARK: Deadlines

    var activeDeadlines: [Deadline] {
        deadlines.filter { $0.doneAt == nil }.sorted { $0.due < $1.due }
    }

    func deadline(_ id: UUID?) -> Deadline? {
        guard let id else { return nil }
        return deadlines.first { $0.id == id }
    }

    /// Days from today to the due date (0 = D-day, negative = overdue).
    func daysLeft(_ d: Deadline) -> Int {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let due = f.date(from: d.due), let now = f.date(from: today) else { return 0 }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: now, to: due).day ?? 0
    }

    func pieces(of id: UUID) -> (done: Int, total: Int) {
        let linked = items.filter { $0.deadlineID == id }
        return (linked.filter { $0.doneAt != nil }.count, linked.count)
    }

    /// `@논문` → the active deadline whose label or name matches best.
    func resolveDeadline(_ token: String) -> UUID? {
        let t = token.lowercased()
        let active = activeDeadlines
        let squash = { (s: String) in s.lowercased().replacingOccurrences(of: " ", with: "") }
        return (active.first { $0.label.lowercased() == t }
            ?? active.first { squash($0.name).hasPrefix(t) }
            ?? active.first { squash($0.name).contains(t) })?.id
    }

    @discardableResult
    func addDeadline(_ text: String) -> Bool {
        guard let p = parseDeadline(text) else { return false }
        deadlines.append(Deadline(name: p.name, due: p.due))
        return true
    }

    @discardableResult
    func editDeadline(_ id: UUID, _ text: String) -> Bool {
        guard let p = parseDeadline(text), let i = deadlines.firstIndex(where: { $0.id == id }) else { return false }
        deadlines[i].name = p.name
        deadlines[i].due = p.due
        return true
    }

    func extendDeadline(_ id: UUID, days: Int) {
        guard let i = deadlines.firstIndex(where: { $0.id == id }) else { return }
        // Overdue ones are pushed from today, not from the missed date.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let base = max(f.date(from: deadlines[i].due) ?? Date(), f.date(from: today) ?? Date())
        if let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: base) {
            deadlines[i].due = Self.dayKey(d)
        }
    }

    func finishDeadline(_ id: UUID) {
        guard let i = deadlines.firstIndex(where: { $0.id == id }) else { return }
        deadlines[i].doneAt = Date()
    }

    func deleteDeadline(_ id: UUID) {
        var changed = items
        for i in changed.indices where changed[i].deadlineID == id { changed[i].deadlineID = nil }
        items = changed
        deadlines.removeAll { $0.id == id }
    }

    func setDeadline(_ itemID: UUID, _ deadlineID: UUID?) {
        update(itemID) { $0.deadlineID = deadlineID }
    }

    func setTag(_ id: UUID, _ tag: String?) {
        registerTag(tag)
        update(id) { $0.tag = tag }
    }

    /// Removes a tag from every item, so it disappears from the chip list.
    func forgetTag(_ tag: String) {
        var changed = items
        for i in changed.indices where changed[i].tag == tag { changed[i].tag = nil }
        items = changed
        tagRegistry.removeAll { $0.name == tag }
    }

    func pick(_ id: UUID) {
        let next = (todayOpen.map(\.order).max() ?? -1) + 1
        update(id) { $0.pickedDay = today; $0.order = next }
    }

    func unpick(_ id: UUID) {
        update(id) { $0.pickedDay = nil; $0.doneAt = nil }
    }

    func toggleDone(_ id: UUID) {
        update(id) {
            if $0.doneAt == nil {
                $0.doneAt = Date()
                if $0.pickedDay == nil { $0.pickedDay = today }
            } else {
                $0.doneAt = nil
            }
        }
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Renames; the `#태그` / `@마감` in the edited text replace the old ones (none = cleared).
    func rename(_ id: UUID, to text: String) {
        let p = parseTag(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !p.title.isEmpty else { return }
        let linked = p.mention.flatMap(resolveDeadline)
        if let tag = p.tag, items.first(where: { $0.id == id })?.tag != tag { registerTag(tag) }
        update(id) {
            $0.title = p.title
            $0.tag = p.tag
            $0.deadlineID = linked
        }
    }

    func moveToday(from source: IndexSet, to destination: Int) {
        var list = todayOpen
        list.move(fromOffsets: source, toOffset: destination)
        reorder(list)
    }

    func nudge(_ id: UUID, by delta: Int) {
        var list = todayOpen
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let j = max(0, min(list.count - 1, i + delta))
        guard i != j else { return }
        list.swapAt(i, j)
        reorder(list)
    }

    private func reorder(_ list: [TodoItem]) {
        var changed = items
        for (rank, item) in list.enumerated() {
            if let i = changed.firstIndex(where: { $0.id == item.id }) { changed[i].order = rank }
        }
        items = changed
    }
}
