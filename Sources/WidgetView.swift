import SwiftUI
import AppKit

// MARK: - Views

enum Tab { case today, inbox }

struct WidgetView: View {
    @EnvironmentObject var store: TodoStore
    @State var tab: Tab = .today
    /// Deadline whose pieces you're writing in 생각함.
    @State var focusDeadline: UUID? = nil

    var body: some View {
        VStack(spacing: 12) {
            header
            DeadlineStrip { id in
                withAnimation(.spring(duration: 0.3)) {
                    focusDeadline = id
                    tab = .inbox
                }
            }
            tabs
            Group {
                switch tab {
                case .today: TodayView(goInbox: { withAnimation(.spring(duration: 0.3)) { tab = .inbox } })
                case .inbox: InboxView(deadline: $focusDeadline)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            QuoteCard()
        }
        .padding(16)
        .frame(width: 320, height: 610)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Pal.cream)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Pal.line, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .foregroundStyle(Pal.ink)
    }

    private var header: some View {
        let total = store.todayOpen.count + store.todayDone.count
        let done = store.todayDone.count
        return HStack(alignment: .center, spacing: 10) {
            Text(mascot(done: done, total: total))
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 1) {
                Text(dateTitle)
                    .font(.cute(17, .heavy))
                Text(total == 0 ? L("오늘은 뭘 해볼까요?", "What's on for today?") : L("\(total)개 중 \(done)개 완료!", "\(done) of \(total) done!"))
                    .font(.cute(11, .medium))
                    .foregroundStyle(Pal.soft)
            }
            Spacer()
            if total > 0 {
                ProgressRing(value: Double(done) / Double(total))
                    .frame(width: 30, height: 30)
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            TabPill(title: L("☀️ 오늘", "☀️ Today"), count: store.todayOpen.count, selected: tab == .today) { tab = .today }
            TabPill(title: L("💭 생각함", "💭 Inbox"), count: store.inbox.count, selected: tab == .inbox) { tab = .inbox }
        }
        .padding(4)
        .background(Capsule().fill(Pal.line.opacity(0.7)))
    }

    private var dateTitle: String {
        let f = DateFormatter()
        switch AppLanguage.current {
        case .ko:
            f.locale = Locale(identifier: "ko_KR")
            f.dateFormat = "M월 d일 EEEE"
        case .en:
            f.locale = Locale(identifier: "en_US")
            f.dateFormat = "EEEE, MMM d"
        }
        return f.string(from: Date())
    }

    private func mascot(done: Int, total: Int) -> String {
        if total == 0 { return "🐣" }
        if done == total { return "🎉" }
        if done == 0 { return "🐥" }
        return "🐤"
    }
}

struct ProgressRing: View {
    var value: Double
    var body: some View {
        ZStack {
            Circle().stroke(Pal.line, lineWidth: 5)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Pal.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.4), value: value)
        }
    }
}

struct TabPill: View {
    var title: String
    var count: Int
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: { withAnimation(.spring(duration: 0.3)) { action() } }) {
            HStack(spacing: 5) {
                Text(title).font(.cute(12, .bold))
                if count > 0 {
                    Text("\(count)")
                        .font(.cute(10, .heavy))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(selected ? Pal.coral.opacity(0.18) : Color.white.opacity(0.6)))
                        .foregroundStyle(selected ? Pal.coral : Pal.soft)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? Pal.card : .clear))
            .shadow(color: selected ? Pal.ink.opacity(0.08) : .clear, radius: 3, y: 1)
            .foregroundStyle(selected ? Pal.ink : Pal.soft)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
