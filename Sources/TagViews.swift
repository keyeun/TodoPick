import SwiftUI
import AppKit

// MARK: Tags

struct TagPill: View {
    @EnvironmentObject var store: TodoStore
    var name: String
    var faded = false
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(store.tagColor(name)).frame(width: 6, height: 6)
            Text(name).font(.cute(10, .semibold))
        }
        .foregroundStyle(Pal.soft)
        .opacity(faded ? 0.6 : 1)
        .fixedSize()
    }
}

struct TitleWithTag: View {
    var item: TodoItem
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if item.tag != nil || item.deadlineID != nil {
                HStack(spacing: 6) {
                    if let tag = item.tag { TagPill(name: tag) }
                    if let id = item.deadlineID { DeadlineMeta(id: id) }
                }
            }
            EditableTitle(item: item)
        }
    }
}

/// Context-menu section for changing an item's tag.
struct TagMenu: View {
    @EnvironmentObject var store: TodoStore
    var item: TodoItem
    var body: some View {
        Menu("종류") {
            ForEach(store.knownTags, id: \.self) { tag in
                Button((item.tag == tag ? "✓ " : "") + tag) { store.setTag(item.id, tag) }
            }
            if item.tag != nil {
                Divider()
                Button("종류 없음") { store.setTag(item.id, nil) }
            }
        }
    }
}

/// Chips under the input: picking one tags everything you type next.
struct TagChips: View {
    @EnvironmentObject var store: TodoStore
    @Binding var selected: String?

    var body: some View {
        let tags = store.knownTags
        if tags.isEmpty {
            Text("#운동 처럼 붙여 적으면 종류가 생겨요")
                .font(.cute(10, .medium))
                .foregroundStyle(Pal.soft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(tags, id: \.self) { tag in
                        let on = selected == tag
                        Button {
                            withAnimation(.spring(duration: 0.25)) { selected = on ? nil : tag }
                        } label: {
                            HStack(spacing: 4) {
                                Circle().fill(store.tagColor(tag)).frame(width: 6, height: 6)
                                Text(tag).font(.cute(11, .bold))
                            }
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(on ? Pal.ink.opacity(0.85) : Pal.card.opacity(0.7)))
                            .foregroundStyle(on ? Color.white : Pal.soft)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("이 종류 지우기", role: .destructive) {
                                if selected == tag { selected = nil }
                                store.forgetTag(tag)
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.never)
        }
    }
}
