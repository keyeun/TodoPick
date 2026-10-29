import SwiftUI
import AppKit

// MARK: Deadlines

func dDayText(_ days: Int) -> String {
    days > 0 ? "D-\(days)" : days == 0 ? "D-day" : "D+\(-days)"
}

/// "🏔 논문 D-5" on a task row.
struct DeadlineMeta: View {
    @EnvironmentObject var store: TodoStore
    var id: UUID
    var body: some View {
        if let d = store.deadline(id) {
            let days = store.daysLeft(d)
            Text("🏔 \(d.label) \(d.doneAt == nil ? dDayText(days) : L("끝", "done"))")
                .font(.cute(10, .semibold))
                .foregroundStyle(d.doneAt == nil && days <= 3 ? Pal.coral : Pal.soft)
                .fixedSize()
        }
    }
}

struct DeadlineMenu: View {
    @EnvironmentObject var store: TodoStore
    var item: TodoItem
    var body: some View {
        if !store.activeDeadlines.isEmpty {
            Menu(L("마감", "Deadline")) {
                ForEach(store.activeDeadlines) { d in
                    Button((item.deadlineID == d.id ? "✓ " : "") + d.name) { store.setDeadline(item.id, d.id) }
                }
                if item.deadlineID != nil {
                    Divider()
                    Button(L("마감 없음", "No deadline")) { store.setDeadline(item.id, nil) }
                }
            }
        }
    }
}

/// Always-visible row of big tasks with D-days, nearest first.
struct DeadlineStrip: View {
    @EnvironmentObject var store: TodoStore
    var onOpen: (UUID) -> Void

    @State private var adding = false
    @State private var editingID: UUID? = nil
    @State private var draft = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    @Environment(\.demoInput) private var demo

    var body: some View {
        Group {
            if adding || editingID != nil {
                editor
            } else if store.activeDeadlines.isEmpty {
                Button { startAdding() } label: {
                    Text(L("🏔  큰 일 · 마감 추가하기", "🏔  Add a big task with a deadline"))
                        .font(.cute(11, .bold))
                        .foregroundStyle(Pal.soft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Pal.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(store.activeDeadlines) { d in
                            DeadlineCard(deadline: d, onOpen: { onOpen(d.id) }, onEdit: { startEditing(d) })
                        }
                        Button { startAdding() } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Pal.soft)
                                .frame(width: 30, height: 46)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Pal.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L("큰 일 · 마감 추가", "Add a big task with a deadline"))
                    }
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.never)
            }
        }
        .onAppear {
            if demo.deadline != nil { adding = true }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("🏔").font(.system(size: 12))
                if let typed = demo.deadline, !typed.isEmpty {
                    DemoTypedText(text: typed, font: .cute(12, .semibold))
                } else {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.cute(12, .semibold))
                    .focused($focused)
                    .background(alignment: .leading) {
                        if draft.isEmpty {
                            Text(L("논문 리뷰 11/5 ⏎", "Paper review 11/5 ⏎"))
                                .font(.cute(12, .semibold))
                                .foregroundStyle(Pal.soft)
                                .allowsHitTesting(false)
                        }
                    }
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, f in if !f { close() } }
                    .onChange(of: draft) { _, _ in invalid = false }
                    .onAppear { focused = true }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(invalid ? Pal.coral : Pal.coral.opacity(0.5), lineWidth: 1.5))
            Text(invalid ? L("날짜도 같이 적어주세요 · 예: 10/28, 11월 5일", "Add a date too · e.g. 10/28, Nov 5") : L("이름 뒤에 날짜를 적어요 · 비우고 ⏎ 하면 취소", "Name, then date · empty ⏎ cancels"))
                .font(.cute(9, .semibold))
                .foregroundStyle(invalid ? Pal.coral : Pal.soft)
                .padding(.leading, 4)
        }
    }

    private func startAdding() {
        draft = ""
        editingID = nil
        withAnimation(.spring(duration: 0.25)) { adding = true }
    }

    private func startEditing(_ d: Deadline) {
        let parts = d.due.split(separator: "-").compactMap { Int($0) }
        draft = parts.count == 3 ? "\(d.name) \(parts[1])/\(parts[2])" : d.name
        adding = false
        withAnimation(.spring(duration: 0.25)) { editingID = d.id }
    }

    private func commit() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return close() }
        let ok = editingID.map { store.editDeadline($0, text) } ?? store.addDeadline(text)
        if ok {
            close()
        } else {
            invalid = true
            focused = true
        }
    }

    private func close() {
        withAnimation(.spring(duration: 0.25)) {
            adding = false
            editingID = nil
        }
        draft = ""
        invalid = false
    }
}

struct DeadlineCard: View {
    @EnvironmentObject var store: TodoStore
    var deadline: Deadline
    var onOpen: () -> Void
    var onEdit: () -> Void
    @State private var hover = false
    @State private var askOverdue = false

    var body: some View {
        let days = store.daysLeft(deadline)
        let urgent = days <= 3
        let p = store.pieces(of: deadline.id)

        VStack(alignment: .leading, spacing: 4) {
            Text(deadline.name)
                .font(.cute(11, .bold))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(days < 0 ? L("지남", "Overdue") : dDayText(days))
                    .font(.cute(11, .heavy))
                    .fixedSize()
                    .foregroundStyle(urgent ? Pal.coral : Pal.soft)
                Spacer(minLength: 2)
                if p.total > 0 && p.done == p.total {
                    // Everything split off is done, but more pieces may come; just ask.
                    Button {
                        withAnimation { store.finishDeadline(deadline.id) }
                    } label: {
                        Text(L("✓ 다 했어요?", "✓ All done?"))
                            .font(.cute(9, .heavy))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 4).padding(.vertical, 1.5)
                            .background(Capsule().fill(Pal.mint.opacity(0.35)))
                            .foregroundStyle(Pal.ink.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .help(L("쪼갠 할 일을 다 끝냈어요 · 누르면 이 큰 일을 끝냄으로 정리해요", "Every step is done · click to finish this big task"))
                } else if p.total == 0 {
                    Text(L("⚠︎ 안 쪼갬", "⚠︎ not split"))
                        .font(.cute(9, .bold))
                        .foregroundStyle(Pal.peach)
                        .help(L("아직 쪼갠 할 일이 없어요 · 눌러서 쪼개기", "No steps yet · click to break it down"))
                } else if p.total <= 5 {
                    HStack(spacing: 2) {
                        ForEach(0..<p.total, id: \.self) { i in
                            Circle()
                                .fill(i < p.done ? Pal.soft : .clear)
                                .overlay(Circle().strokeBorder(Pal.soft.opacity(0.7), lineWidth: 1))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .help(L("쪼갠 할 일 \(p.total)개 중 \(p.done)개 완료", "\(p.done) of \(p.total) steps done"))
                } else {
                    Text("\(p.done)/\(p.total)")
                        .font(.cute(9, .bold))
                        .foregroundStyle(Pal.soft)
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(width: 122, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card.opacity(hover ? 1 : 0.8)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(urgent ? Pal.coral.opacity(0.55) : Pal.line, lineWidth: 1.2))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            if days < 0 { askOverdue = true } else { onOpen() }
        }
        .help(days < 0 ? L("마감이 지났어요 · 눌러서 정리하기", "Past due · click to settle it") : L("\(deadline.due) 마감 · 눌러서 할 일로 쪼개기", "Due \(deadline.due) · click to break down"))
        .popover(isPresented: $askOverdue, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("\(deadline.name) 마감이 지났어요", "\(deadline.name) is past due")).font(.cute(12, .bold))
                Button(L("✓ 끝냈어요", "✓ Finished")) { askOverdue = false; withAnimation { store.finishDeadline(deadline.id) } }
                Button(L("하루 연장", "Extend 1 day")) { askOverdue = false; store.extendDeadline(deadline.id, days: 1) }
                Button(L("3일 연장", "Extend 3 days")) { askOverdue = false; store.extendDeadline(deadline.id, days: 3) }
                Button(L("일주일 연장", "Extend 1 week")) { askOverdue = false; store.extendDeadline(deadline.id, days: 7) }
            }
            .buttonStyle(.link)
            .padding(12)
        }
        .contextMenu {
            Button(L("할 일로 쪼개기", "Break down")) { onOpen() }
            Button(L("✓ 끝냈어요", "✓ Finished")) { withAnimation { store.finishDeadline(deadline.id) } }
            Menu(L("연장", "Extend")) {
                Button(L("하루", "1 day")) { store.extendDeadline(deadline.id, days: 1) }
                Button(L("3일", "3 days")) { store.extendDeadline(deadline.id, days: 3) }
                Button(L("일주일", "1 week")) { store.extendDeadline(deadline.id, days: 7) }
            }
            Button(L("이름 · 날짜 고치기", "Edit name · date")) { onEdit() }
            Divider()
            Button(L("삭제", "Delete"), role: .destructive) { withAnimation { store.deleteDeadline(deadline.id) } }
        }
    }
}
