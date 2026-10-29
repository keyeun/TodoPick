// Records the README demo GIFs from scripted sample data (no screen recording needed).
// Run with `./build.sh gifs` → docs/demo-today.gif, docs/demo-deadline.gif (+ docs/en/).
//
// Each frame is the real widget rendered offscreen; the cursor, clicks, and the dragged
// row are drawn on top. Coordinates are in widget points (320 × 610).
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Recorder

@MainActor
final class Recorder {
    let store: TodoStore
    var caption = ""
    var cursor = CGPoint(x: 250, y: 420)
    private(set) var frames: [(image: CGImage, delay: Double)] = []

    /// The widget sits at this offset inside each frame (below the caption).
    static let widgetOrigin = CGPoint(x: 20, y: 64)
    static let scale: CGFloat = 2

    init(store: TodoStore) { self.store = store }

    // Rendering

    func render(_ tab: Tab, focus: UUID? = nil, inbox: String? = nil, deadline: String? = nil) -> CGImage {
        let view = DemoFrame(caption: caption,
                             widget: WidgetView(tab: tab, focusDeadline: focus))
            .environmentObject(store)
            .environment(\.demoInput, DemoInput(inbox: inbox, deadline: deadline))
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: 0), size: host.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        return rep.cgImage!
    }

    // Frame building

    func hold(_ base: CGImage, _ seconds: Double, click: Bool = false) {
        frames.append((overlay(base, click: click), seconds))
    }

    func move(_ base: CGImage, to target: CGPoint, duration: Double = 0.45) {
        let steps = 7
        let start = cursor
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2   // ease in-out
            cursor = CGPoint(x: start.x + (target.x - start.x) * e, y: start.y + (target.y - start.y) * e)
            hold(base, duration / Double(steps))
        }
    }

    func click(_ base: CGImage) {
        hold(base, 0.12, click: true)
    }

    /// Types `text` one character at a time; `make` renders the state for a partial string.
    func type(_ text: String, perChar: Double = 0.07, _ make: (String) -> CGImage) {
        var typed = ""
        for ch in text {
            typed.append(ch)
            hold(make(typed), perChar)
        }
    }

    /// Lifts `row` out of `base` and slides it to `toY` (top edge), cursor riding along.
    func drag(_ base: CGImage, row: CGRect, toY: CGFloat, grab: CGPoint) {
        let steps = 10
        cursor = grab
        hold(base, 0.2, click: true)
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let e = 1 - pow(1 - t, 3)
            let dy = (toY - row.minY) * e
            cursor = CGPoint(x: grab.x, y: grab.y + dy)
            frames.append((overlay(lift(base, row: row, dy: dy)), 0.05))
        }
    }

    // Drawing

    private func px(_ p: CGPoint, height: Int) -> CGPoint {
        let s = Self.scale, o = Self.widgetOrigin
        return CGPoint(x: (p.x + o.x) * s, y: CGFloat(height) - (p.y + o.y) * s)
    }

    private func context(for image: CGImage) -> CGContext {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx
    }

    private func overlay(_ base: CGImage, click: Bool = false) -> CGImage {
        let ctx = context(for: base)
        let s = Self.scale
        let tip = px(cursor, height: base.height)
        if click {
            ctx.setFillColor(CGColor(red: 1, green: 0.55, blue: 0.48, alpha: 0.28))
            ctx.fillEllipse(in: CGRect(x: tip.x - 15 * s, y: tip.y - 15 * s, width: 30 * s, height: 30 * s))
        }
        // Classic arrow cursor, tip at `tip`.
        let shape: [CGPoint] = [(0, 0), (0, 17), (4.2, 13.2), (7, 19.6), (9.6, 18.5), (6.9, 12.2), (12.2, 12.2)]
            .map { CGPoint(x: tip.x + $0.0 * s * 1.15, y: tip.y - $0.1 * s * 1.15) }
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addLines(between: shape)
        ctx.closePath()
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(1.6 * s)
        ctx.setLineJoin(.round)
        ctx.drawPath(using: .fillStroke)
        return ctx.makeImage()!
    }

    private func lift(_ base: CGImage, row: CGRect, dy: CGFloat) -> CGImage {
        let s = Self.scale, o = Self.widgetOrigin
        let src = CGRect(x: (row.minX + o.x) * s, y: (row.minY + o.y) * s, width: row.width * s, height: row.height * s)
        let piece = base.cropping(to: src)!
        let ctx = context(for: base)
        let h = CGFloat(base.height)
        // Leave a soft gap where the row was.
        ctx.setFillColor(CGColor(red: 1, green: 0.969, blue: 0.925, alpha: 1))
        ctx.fill(CGRect(x: src.minX, y: h - src.maxY, width: src.width, height: src.height))
        ctx.setStrokeColor(CGColor(red: 0.945, green: 0.894, blue: 0.827, alpha: 1))
        ctx.setLineWidth(1.5 * s)
        ctx.setLineDash(phase: 0, lengths: [4 * s, 3 * s])
        ctx.stroke(CGRect(x: src.minX, y: h - src.maxY, width: src.width, height: src.height).insetBy(dx: 2 * s, dy: 2 * s))
        ctx.setLineDash(phase: 0, lengths: [])
        // The row, lifted and tilted slightly.
        let dest = CGRect(x: src.minX, y: h - src.maxY - dy * s, width: src.width, height: src.height)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6 * s), blur: 14 * s, color: CGColor(gray: 0, alpha: 0.22))
        ctx.translateBy(x: dest.midX, y: dest.midY)
        ctx.rotate(by: -0.015)
        ctx.draw(piece, in: CGRect(x: -dest.width / 2, y: -dest.height / 2, width: dest.width, height: dest.height))
        ctx.restoreGState()
        return ctx.makeImage()!
    }

    // Output

    func writeGIF(to path: String, width: Int = 400) {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (image, delay) in frames {
            let h = Int(Double(image.height) * Double(width) / Double(image.width))
            let ctx = CGContext(data: nil, width: width, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: h))
            let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                         kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
            CGImageDestinationAddImage(dest, ctx.makeImage()!, props)
        }
        CGImageDestinationFinalize(dest)
        let total = frames.reduce(0) { $0 + $1.delay }
        print("✅ Wrote \(path) — \(frames.count) frames, \(String(format: "%.1f", total))s")
    }

    /// Saves the latest frame as PNG (for lining up coordinates).
    func probe(_ image: CGImage, _ path: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

/// Caption pill above the widget, on a warm backdrop.
struct DemoFrame: View {
    var caption: String
    var widget: WidgetView

    var body: some View {
        VStack(spacing: 10) {
            Text(caption)
                .font(.cute(14, .heavy))
                .foregroundStyle(Pal.ink)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(Capsule().fill(Color.white))
                .shadow(color: Pal.ink.opacity(0.08), radius: 3, y: 1)
            widget
                .shadow(color: Pal.ink.opacity(0.12), radius: 10, y: 4)
        }
        .padding(20)
        .frame(width: 360)
        .background(Color(hex: 0xF3E6D6))
    }
}

// MARK: - Scenes

@MainActor
enum Scenes {
    static func freshStore(_ name: String) -> TodoStore {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TODOPICK_DIR"] ?? NSTemporaryDirectory())
        let dir = root.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("TODOPICK_DIR", dir.path, 1)
        return TodoStore()
    }

    static func item(_ store: TodoStore, _ title: String) -> UUID {
        store.items.first { $0.title == title }!.id
    }

    /// GIF 1: jot things down → pick for today → reorder → check off.
    static func today(out: String, probe: String?) {
        let store = freshStore("gif-today")
        store.add(L("장보기", "Groceries"))
        store.add(L("치과 예약 전화 #생활", "Call the dentist #life"))
        let r = Recorder(store: store)

        // ① Jot down
        r.caption = L("① 생각나는 대로 적기", "① Jot down anything")
        var frame = r.render(.inbox)
        r.cursor = Geo.inboxField
        r.hold(frame, 0.8)
        let entries = [L("논문 2편 읽기 #연구", "Read 2 papers #research"),
                       L("과제 채점 #수업", "Grade homework #teaching"),
                       L("헬스 #운동", "Leg day #gym")]
        for entry in entries {
            r.type(entry) { r.render(.inbox, inbox: $0) }
            store.add(entry)
            frame = r.render(.inbox)
            r.hold(frame, 0.45)
        }
        if let probe { r.probe(frame, "\(probe)/inbox.png") }

        // ② Pick for today: the newest is on top, so click the top row three times.
        r.caption = L("② 오늘 할 일만 고르기", "② Pick today's few")
        frame = r.render(.inbox)
        for _ in 0..<3 {
            r.move(frame, to: Geo.inboxTopPick)
            r.click(frame)
            store.pick(store.inbox.first!.id)
            frame = r.render(.inbox)
            r.hold(frame, 0.3)
        }
        r.move(frame, to: Geo.todayTab)
        r.click(frame)
        frame = r.render(.today)
        r.hold(frame, 0.7)
        if let probe { r.probe(frame, "\(probe)/today.png") }

        // ③ Reorder: drag the third row to the top.
        r.caption = L("③ 끌어서 순서 정하기 · 위가 먼저", "③ Drag to order · top goes first")
        frame = r.render(.today)
        r.move(frame, to: Geo.todayRowGrab(2))
        r.drag(frame, row: Geo.todayRow(2), toY: Geo.todayRow(0).minY, grab: Geo.todayRowGrab(2))
        r.cursor = Geo.todayRowGrab(0)
        store.moveToday(from: IndexSet(integer: 2), to: 0)
        frame = r.render(.today)
        r.hold(frame, 0.8)

        // ④ Check off
        r.caption = L("④ 끝내면 체크 ✓", "④ Check it off ✓")
        frame = r.render(.today)
        r.move(frame, to: Geo.todayCheck(0))
        r.click(frame)
        store.toggleDone(store.todayOpen.first!.id)
        frame = r.render(.today)
        r.hold(frame, 2.2)

        r.writeGIF(to: out)
    }

    /// GIF 2: add a big task with a deadline → break it into steps → pick one for today.
    static func deadline(out: String, probe: String?) {
        let store = freshStore("gif-deadline")
        store.add(L("주간 미팅 안건 정리 #회의", "Weekly meeting agenda #meeting"))
        store.pick(store.items[0].id)
        let r = Recorder(store: store)
        let dueKey = TodoStore.dayKey(Date().addingTimeInterval(40 * 86_400)).split(separator: "-")
        let due = "\(Int(dueKey[1])!)/\(Int(dueKey[2])!)"

        // ① Add a big task
        r.caption = L("① 마감 있는 큰 일 추가", "① Add a big task with a deadline")
        var frame = r.render(.today)
        r.cursor = CGPoint(x: 230, y: 300)
        r.hold(frame, 0.7)
        r.move(frame, to: Geo.addDeadline)
        r.click(frame)
        let name = L("기말 프로젝트 ", "Final project ") + due
        frame = r.render(.today, deadline: "")
        r.hold(frame, 0.3)
        r.type(name) { r.render(.today, deadline: $0) }
        store.addDeadline(name)
        frame = r.render(.today)
        r.hold(frame, 1.0)
        if let probe { r.probe(frame, "\(probe)/strip.png") }

        // ② Click it and break it down
        r.caption = L("② 눌러서 작게 쪼개기", "② Click it, break it down")
        let id = store.activeDeadlines[0].id
        r.move(frame, to: Geo.firstCard)
        r.click(frame)
        frame = r.render(.inbox, focus: id)
        r.hold(frame, 0.5)
        let steps = [L("관련 연구 정리", "Related work notes"),
                     L("실험 설계", "Design the experiment"),
                     L("초안 쓰기", "Write the first draft")]
        for step in steps {
            r.type(step) { r.render(.inbox, focus: id, inbox: $0) }
            store.add(step, defaultDeadline: id)
            frame = r.render(.inbox, focus: id)
            r.hold(frame, 0.4)
        }
        r.hold(frame, 0.6)
        if let probe { r.probe(frame, "\(probe)/breakdown.png") }

        // ③ Pick a step for today
        r.caption = L("③ 오늘 할 조각만 고르기", "③ Pick a step for today")
        r.move(frame, to: Geo.focusRowPick(2))
        r.click(frame)
        store.pick(item(store, steps[0]))
        frame = r.render(.inbox, focus: id)
        r.hold(frame, 0.3)
        r.move(frame, to: Geo.todayTabWithCards)
        r.click(frame)
        frame = r.render(.today)
        r.hold(frame, 2.2)
        if let probe { r.probe(frame, "\(probe)/today2.png") }

        r.writeGIF(to: out)
    }
}

/// Click targets, in widget points. Measured from rendered frames (`./build.sh gifs --probe`).
enum Geo {
    static let inboxField = CGPoint(x: 165, y: 167)
    static let inboxTopPick = CGPoint(x: 262, y: 250)
    /// The 오늘 tab sits lower once the strip holds cards.
    static let todayTab = CGPoint(x: 90, y: 120)
    static let todayTabWithCards = CGPoint(x: 90, y: 138)
    static let addDeadline = CGPoint(x: 160, y: 76)
    static let firstCard = CGPoint(x: 78, y: 86)
    static func todayRow(_ i: Int) -> CGRect { CGRect(x: 24, y: 153 + CGFloat(i) * 56, width: 271, height: 50) }
    static func todayRowGrab(_ i: Int) -> CGPoint { CGPoint(x: 200, y: todayRow(i).midY) }
    static func todayCheck(_ i: Int) -> CGPoint { CGPoint(x: 44, y: todayRow(i).midY) }
    static func focusRowPick(_ i: Int) -> CGPoint { CGPoint(x: 262, y: 298 + CGFloat(i) * 54) }
}

// MARK: - Entry

@main
struct Gifs {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let args = CommandLine.arguments.dropFirst()
        let out = args.first { !$0.hasPrefix("--") } ?? "docs"
        let probe = args.contains("--probe") ? out : nil
        for lang in AppLanguage.allCases {
            UserDefaults.standard.set(lang.rawValue, forKey: AppLanguage.defaultsKey)
            let dir = lang == .ko ? out : "\(out)/en"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            Scenes.today(out: "\(dir)/demo-today.gif", probe: probe.map { _ in dir })
            Scenes.deadline(out: "\(dir)/demo-deadline.gif", probe: probe.map { _ in dir })
            if probe != nil { break }   // probing: Korean only
        }
        UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey)
    }
}
