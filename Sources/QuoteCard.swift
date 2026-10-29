import SwiftUI
import AppKit

// MARK: Quote

struct QuoteCard: View {
    @EnvironmentObject var store: TodoStore
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let quote = store.latestQuote
        HStack(alignment: .top, spacing: 8) {
            Text("💌").font(.system(size: 15))
            if editing {
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.cute(12, .semibold))
                    .lineLimit(1...3)
                    .focused($focused)
                    .background(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("오늘의 한마디를 적어요 ⏎")
                                .font(.cute(12, .semibold))
                                .foregroundStyle(Pal.soft)
                                .allowsHitTesting(false)
                        }
                    }
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, f in if !f { commit() } }
                    .onAppear { focused = true }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    if let quote {
                        Text(quote.text)
                            .font(.cute(12, .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(3)
                        if !quote.isToday {
                            Text("✏️ 오늘의 한마디를 새로 써볼까요?")
                                .font(.cute(9, .bold))
                                .foregroundStyle(Pal.coral)
                        }
                    } else {
                        Text("오늘의 한마디를 적어보세요")
                            .font(.cute(12, .semibold))
                            .foregroundStyle(Pal.soft)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: 0xFFEFF0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(hex: 0xFFD3D6), style: StrokeStyle(lineWidth: 1.2, dash: editing ? [] : [4, 3]))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !editing else { return }
            text = (quote?.isToday ?? false) ? quote!.text : ""
            editing = true
        }
        .help("클릭해서 오늘의 한마디 쓰기")
    }

    private func commit() {
        guard editing else { return }
        store.setQuote(text)
        editing = false
    }
}
