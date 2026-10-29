// Renders README screenshots from made-up sample data. Run with `./build.sh screenshots`.
import SwiftUI
import AppKit

@main
struct Screenshots {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = CommandLine.arguments.dropFirst().first ?? "docs"
        let day: TimeInterval = 86_400
        let due = { (days: Double) in TodoStore.dayKey(Date().addingTimeInterval(days * day)) }

        let store = TodoStore()   // TODOPICK_DIR points at an empty temp folder
        store.addDeadline("논문 리뷰 \(md(due(3)))")
        store.addDeadline("기말 프로젝트 \(md(due(12)))")
        store.addDeadline("학회 발표 준비 \(md(due(20)))")

        store.add("""
        주간 미팅 안건 정리 #회의
        헬스 하체 #운동
        실험 결과 그래프 #연구 @기말
        과제 채점 #수업
        관련 연구 정리 #연구 @기말
        리뷰 코멘트 초안 #연구 @논문
        """)
        store.add("리뷰 점수 제출 #연구 @논문")
        for title in ["리뷰 코멘트 초안", "과제 채점", "실험 결과 그래프"] {
            if let item = store.items.first(where: { $0.title == title }) { store.pick(item.id) }
        }
        if let item = store.items.first(where: { $0.title == "과제 채점" }) { store.toggleDone(item.id) }
        store.setQuote("작게 쪼개면 결국 다 할 수 있다")

        let review = store.activeDeadlines.first { $0.label == "논문" }?.id
        render(WidgetView(tab: .today), store, to: "\(out)/today.png")
        render(WidgetView(tab: .inbox), store, to: "\(out)/inbox.png")
        render(WidgetView(tab: .inbox, focusDeadline: review), store, to: "\(out)/breakdown.png")
        print("✅ Wrote \(out)/today.png, inbox.png, breakdown.png")
    }

    static func md(_ key: String) -> String {
        let p = key.split(separator: "-")
        return "\(Int(p[1])!)/\(Int(p[2])!)"
    }

    @MainActor static func render(_ view: WidgetView, _ store: TodoStore, to path: String) {
        let host = NSHostingView(rootView: view.environmentObject(store))
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: 0), size: host.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
