import SwiftUI
import AppKit

// MARK: Shared bits

struct EditableTitle: View {
    @EnvironmentObject var store: TodoStore
    var item: TodoItem
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.cute(13, .semibold))
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: focused) { _, f in if !f { commit() } }
                .onAppear { focused = true }
        } else {
            Text(item.title)
                .font(.cute(13, .semibold))
                .lineLimit(2)
                .onTapGesture(count: 2) {
                    text = item.title + (item.tag.map { " #\($0)" } ?? "")
                        + (store.deadline(item.deadlineID).map { " @\($0.label)" } ?? "")
                    editing = true
                }
                .help(L("더블클릭해서 고치기 · #종류 · @마감", "Double-click to edit · #type · @deadline"))
        }
    }

    private func commit() {
        store.rename(item.id, to: text)
        editing = false
    }
}

struct IconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Pal.soft)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Pal.line.opacity(0.8)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct EmptyState: View {
    var emoji: String
    var title: String
    var subtitle: String
    var button: String? = nil
    var action: (() -> Void)? = nil
    @State private var bob = false

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(emoji)
                .font(.system(size: 44))
                .offset(y: bob ? -4 : 2)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bob)
                .onAppear { bob = true }
            Text(title).font(.cute(14, .bold))
            Text(subtitle).font(.cute(11, .medium)).foregroundStyle(Pal.soft)
            if let button, let action {
                Button(action: action) {
                    Text(button)
                        .font(.cute(12, .heavy))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Pal.coral))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
