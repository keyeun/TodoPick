import SwiftUI
import AppKit

// MARK: Today

struct TodayView: View {
    @EnvironmentObject var store: TodoStore
    var goInbox: () -> Void

    var body: some View {
        if store.todayOpen.isEmpty && store.todayDone.isEmpty {
            EmptyState(emoji: "🌱", title: "아직 오늘 할 일이 없어요",
                       subtitle: "생각함에서 오늘 할 일을 골라보세요",
                       button: "골라보러 가기 →", action: goInbox)
        } else {
            VStack(spacing: 6) {
            List {
                ForEach(Array(store.todayOpen.enumerated()), id: \.element.id) { idx, item in
                    TodayRow(item: item, rank: idx)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                }
                .onMove { store.moveToday(from: $0, to: $1) }

                if store.todayOpen.isEmpty {
                    Text("오늘 할 일 끝! 푹 쉬어요 🛋️")
                        .font(.cute(12, .semibold))
                        .foregroundStyle(Pal.soft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if !store.todayDone.isEmpty {
                    Text("완료 \(store.todayDone.count)")
                        .font(.cute(11, .bold))
                        .foregroundStyle(Pal.soft)
                        .padding(.top, 6)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))
                    ForEach(store.todayDone) { item in
                        DoneRow(item: item)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)

            if store.todayOpen.count > 1 {
                Text("끌어서 순서를 바꿀 수 있어요 · 위가 먼저!")
                    .font(.cute(10, .medium))
                    .foregroundStyle(Pal.soft.opacity(0.8))
            }
            }
        }
    }
}

struct CheckCircle: View {
    var done: Bool
    var tint: Color
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: { withAnimation(.spring(duration: 0.35, bounce: 0.5)) { action() } }) {
            ZStack {
                Circle()
                    .strokeBorder(tint, lineWidth: 2)
                    .background(Circle().fill(done ? tint : (hover ? tint.opacity(0.2) : .clear)))
                if done || hover {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(done ? .white : tint)
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct TodayRow: View {
    @EnvironmentObject var store: TodoStore
    var item: TodoItem
    var rank: Int
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            CheckCircle(done: false, tint: Pal.soft.opacity(0.7)) { store.toggleDone(item.id) }
            // Only #1 gets the accent; the rest stay quiet.
            Text("\(rank + 1)")
                .font(.cute(13, .heavy))
                .foregroundStyle(rank == 0 ? Pal.coral : Pal.soft.opacity(0.6))
                .frame(width: 14)
            TitleWithTag(item: item)
            Spacer(minLength: 4)
            if hover {
                IconButton(symbol: "arrow.uturn.backward", help: "생각함으로 돌려보내기") {
                    withAnimation { store.unpick(item.id) }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Pal.card)
                .shadow(color: Pal.ink.opacity(hover ? 0.10 : 0.05), radius: hover ? 4 : 2, y: 1)
        )
        .onHover { hover = $0 }
        .contextMenu {
            Button("우선순위 올리기 ↑") { store.nudge(item.id, by: -1) }
            Button("우선순위 내리기 ↓") { store.nudge(item.id, by: 1) }
            Divider()
            TagMenu(item: item)
            DeadlineMenu(item: item)
            Divider()
            Button("생각함으로 돌려보내기") { store.unpick(item.id) }
            Button("삭제", role: .destructive) { store.delete(item.id) }
        }
    }
}

struct DoneRow: View {
    @EnvironmentObject var store: TodoStore
    var item: TodoItem

    var body: some View {
        HStack(spacing: 10) {
            CheckCircle(done: true, tint: Pal.mint) { store.toggleDone(item.id) }
            Text(item.title)
                .font(.cute(12, .medium))
                .strikethrough(true, color: Pal.soft)
                .foregroundStyle(Pal.soft)
                .lineLimit(1)
            if let tag = item.tag { TagPill(name: tag, faded: true) }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .contextMenu {
            Button("다시 하기") { store.toggleDone(item.id) }
            Button("삭제", role: .destructive) { store.delete(item.id) }
        }
    }
}
