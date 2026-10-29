// Renders README screenshots from made-up sample data. Run with `./build.sh screenshots`.
// Korean shots go to docs/, English shots to docs/en/.
import SwiftUI
import AppKit

@main
struct Screenshots {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = CommandLine.arguments.dropFirst().first ?? "docs"
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TODOPICK_DIR"] ?? NSTemporaryDirectory())

        for lang in AppLanguage.allCases {
            UserDefaults.standard.set(lang.rawValue, forKey: AppLanguage.defaultsKey)
            let dir = root.appendingPathComponent(lang.rawValue)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            setenv("TODOPICK_DIR", dir.path, 1)
            let store = TodoStore()
            fill(store, lang)

            let target = lang == .ko ? out : "\(out)/en"
            try? FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
            let focus = store.activeDeadlines.first?.id
            render(WidgetView(tab: .today), store, to: "\(target)/today.png")
            render(WidgetView(tab: .inbox), store, to: "\(target)/inbox.png")
            render(WidgetView(tab: .inbox, focusDeadline: focus), store, to: "\(target)/breakdown.png")
            print("✅ Wrote \(target)/today.png, inbox.png, breakdown.png")
        }
        UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey)
    }

    static func fill(_ store: TodoStore, _ lang: AppLanguage) {
        let day: TimeInterval = 86_400
        let md = { (days: Double) -> String in
            let p = TodoStore.dayKey(Date().addingTimeInterval(days * day)).split(separator: "-")
            return "\(Int(p[1])!)/\(Int(p[2])!)"
        }
        let ko = lang == .ko
        store.addDeadline((ko ? "논문 리뷰 " : "Paper review ") + md(3))
        store.addDeadline((ko ? "기말 프로젝트 " : "Final project ") + md(12))
        store.addDeadline((ko ? "학회 발표 준비 " : "Conference talk ") + md(20))
        store.add(ko ? """
        주간 미팅 안건 정리 #회의
        헬스 하체 #운동
        실험 결과 그래프 #연구 @기말
        과제 채점 #수업
        관련 연구 정리 #연구 @기말
        리뷰 코멘트 초안 #연구 @논문
        """ : """
        Weekly meeting agenda #meeting
        Leg day #gym
        Plot experiment results #research @final
        Grade homework #teaching
        Related work notes #research @final
        Draft review comments #research @paper
        """)
        store.add(ko ? "리뷰 점수 제출 #연구 @논문" : "Submit review scores #research @paper")
        let picks = ko ? ["리뷰 코멘트 초안", "과제 채점", "실험 결과 그래프"]
                       : ["Draft review comments", "Grade homework", "Plot experiment results"]
        for title in picks {
            if let item = store.items.first(where: { $0.title == title }) { store.pick(item.id) }
        }
        if let item = store.items.first(where: { $0.title == picks[1] }) { store.toggleDone(item.id) }
        store.setQuote(ko ? "작게 쪼개면 결국 다 할 수 있다" : "Small steps still get you there")
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
