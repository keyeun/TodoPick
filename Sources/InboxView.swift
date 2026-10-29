import SwiftUI
import AppKit

// MARK: Inbox

struct InboxView: View {
    @EnvironmentObject var store: TodoStore
    @State private var draft = ""
    @Binding var deadline: UUID?
    @State private var selectedTag: String? = nil
    @FocusState private var focused: Bool

    private var focusDeadline: Deadline? { store.deadline(deadline) }

    /// While breaking down a deadline, show only its pieces.
    private var visible: [TodoItem] {
        guard let id = deadline else { return store.inbox }
        return store.inbox.filter { $0.deadlineID == id }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let d = focusDeadline {
                HStack(spacing: 6) {
                    Text("🏔").font(.system(size: 12))
                    Text(d.name).font(.cute(12, .heavy)).lineLimit(1)
                    Text(dDayText(store.daysLeft(d)))
                        .font(.cute(11, .heavy))
                        .foregroundStyle(store.daysLeft(d) <= 3 ? Pal.coral : Pal.soft)
                    Text("쪼개는 중").font(.cute(10, .semibold)).foregroundStyle(Pal.soft)
                    Spacer()
                    IconButton(symbol: "xmark", help: "전체 생각함 보기") {
                        withAnimation(.spring(duration: 0.3)) { deadline = nil }
                    }
                }
                .padding(.horizontal, 4)
            }
            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .foregroundStyle(Pal.coral)
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.cute(13, .medium))
                    .focused($focused)
                    .background(alignment: .leading) {
                        if draft.isEmpty {
                            Text(focusDeadline.map { "\($0.label) 쪼개서 하나씩 적고 ⏎" }
                                 ?? selectedTag.map { "#\($0) 할 일 적고 ⏎" }
                                 ?? "생각나는 대로 쭉 적고 ⏎")
                                .font(.cute(13, .medium))
                                .foregroundStyle(Pal.soft)
                                .allowsHitTesting(false)
                        }
                    }
                    .onSubmit {
                        withAnimation(.spring(duration: 0.3)) { store.add(draft, defaultTag: selectedTag, defaultDeadline: deadline) }
                        draft = ""
                        focused = true
                    }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Pal.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(focused ? Pal.coral.opacity(0.6) : Pal.line, style: StrokeStyle(lineWidth: 1.5, dash: focused ? [] : [4, 3]))
                    )
            )

            TagChips(selected: $selectedTag)

            if visible.isEmpty, let d = focusDeadline {
                EmptyState(emoji: "🪓", title: "\(d.label), 어떻게 쪼개볼까요?",
                           subtitle: "작게 나눈 할 일을 위에 하나씩 적어요")
            } else if visible.isEmpty {
                EmptyState(emoji: "☁️", title: "머릿속이 깨끗해요",
                           subtitle: "떠오르는 일을 위에 쭉 적어두세요")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visible) { item in
                            InboxRow(item: item)
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                        removal: .scale(scale: 0.8).combined(with: .opacity)))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
            }
        }
        .onAppear { focused = true }
    }
}

struct InboxRow: View {
    @EnvironmentObject var store: TodoStore
    var item: TodoItem
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            TitleWithTag(item: item)
            if item.bounced > 0 {
                Text("🔁\(item.bounced)")
                    .font(.cute(9, .bold))
                    .foregroundStyle(Pal.peach)
                    .help("오늘 못 끝내서 \(item.bounced)번 돌아왔어요")
            }
            Spacer(minLength: 4)
            if hover {
                IconButton(symbol: "trash", help: "삭제") {
                    withAnimation { store.delete(item.id) }
                }
            }
            Button {
                withAnimation(.spring(duration: 0.35)) { store.pick(item.id) }
            } label: {
                Text("오늘 할래 ☀️")
                    .font(.cute(10, .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(hover ? Pal.butter : Pal.butter.opacity(0.45)))
                    .foregroundStyle(Pal.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Pal.card.opacity(hover ? 1 : 0.75))
        )
        .onHover { hover = $0 }
        .contextMenu {
            Button("오늘 할래") { store.pick(item.id) }
            Button("바로 완료") { store.toggleDone(item.id) }
            TagMenu(item: item)
            DeadlineMenu(item: item)
            Divider()
            Button("삭제", role: .destructive) { store.delete(item.id) }
        }
    }
}
