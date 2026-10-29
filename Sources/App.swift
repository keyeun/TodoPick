import SwiftUI
import AppKit
import ServiceManagement
import Carbon.HIToolbox

// MARK: - Window & App

final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// System-wide shortcut via Carbon; needs no Accessibility permission.
final class HotKey {
    private static var action: (() -> Void)?
    private var ref: EventHotKeyRef?

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x54445043), id: 1)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("TodoPick: hotkey registration failed (\(status))") }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TodoStore()
    var window: WidgetWindow!
    private var hotKey: HotKey?
    /// True while the widget has been pulled in front of other windows.
    private var summoned = false
    private var previousApp: NSRunningApplication?

    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    static let shortcutLabel = "⌃⌥T"

    var floatsOnTop: Bool {
        get { UserDefaults.standard.bool(forKey: "floatsOnTop") }
        set { UserDefaults.standard.set(newValue, forKey: "floatsOnTop"); applyLevel() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingView(rootView: WidgetView().environmentObject(store))
        window = WidgetWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if !window.setFrameUsingName("TodoPickWidget") {
            if let screen = NSScreen.main?.visibleFrame {
                window.setFrameOrigin(NSPoint(x: screen.maxX - 340, y: screen.maxY - 560))
            }
        }
        // The saved frame may predate a size change; keep the top-left corner fixed.
        let top = window.frame.maxY
        window.setContentSize(host.fittingSize)
        window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
        window.setFrameAutosaveName("TodoPickWidget")
        // Esc anywhere in the widget (even while typing) sends it back.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == UInt16(kVK_Escape), event.window === self.window else { return event }
            self.dismiss()
            return nil
        }
        applyLevel()
        window.orderFrontRegardless()

        // `open TodoPick.app --args --enable-login-item` turns on launch at login.
        if CommandLine.arguments.contains("--enable-login-item") {
            do { try SMAppService.mainApp.register() } catch { NSLog("TodoPick: login item failed: \(error)") }
        }
        // Used by `./build.sh uninstall`: remove the login item, then quit.
        if CommandLine.arguments.contains("--disable-login-item") {
            try? SMAppService.mainApp.unregister()
            NSApp.terminate(nil)
            return
        }

        hotKey = HotKey(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [weak self] in self?.toggle() }

        // Going back to another app sends the widget back to the desktop.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.summoned = false
            self?.applyLevel()
        }
    }

    func applyLevel() {
        window?.level = (floatsOnTop || summoned) ? .floating : Self.desktopLevel
    }

    func toggle() {
        if summoned && NSApp.isActive { dismiss() } else { showWidget() }
    }

    /// Pulls the widget in front of every window and focuses it.
    func showWidget() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        summoned = true
        applyLevel()
        window.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 1
        }
    }

    /// Back to the desktop and to whatever app you were using.
    func dismiss() {
        summoned = false
        applyLevel()
        if let app = previousApp, !app.isTerminated {
            app.activate()
        } else {
            NSApp.hide(nil)
            NSApp.unhideWithoutActivation()
        }
    }
}

#if !TODOPICK_TOOL
@main
#endif
struct TodoPickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(delegate: delegate)
        } label: {
            MenuBarLabel(store: delegate.store)
        }
    }
}

/// Today's #1 task right in the menu bar, so you can see it from any app.
struct MenuBarLabel: View {
    @ObservedObject var store: TodoStore

    var body: some View {
        if let top = store.todayOpen.first {
            let title = top.title.count > 16 ? String(top.title.prefix(15)) + "…" : top.title
            Text("☀️ \(title)  \(store.todayDone.count)/\(store.todayOpen.count + store.todayDone.count)")
        } else if !store.todayDone.isEmpty {
            Text("🎉 \(store.todayDone.count)/\(store.todayDone.count)")
        } else {
            Image(systemName: "checklist")
        }
    }
}

struct MenuContent: View {
    let delegate: AppDelegate
    @State private var onTop = UserDefaults.standard.bool(forKey: "floatsOnTop")
    @State private var atLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Button("위젯 앞으로 불러오기  \(AppDelegate.shortcutLabel)") { delegate.showWidget() }
        Toggle("항상 위에 띄우기", isOn: $onTop)
            .onChange(of: onTop) { _, v in delegate.floatsOnTop = v }
        Toggle("로그인 시 자동 실행", isOn: $atLogin)
            .onChange(of: atLogin) { _, v in
                do {
                    if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    atLogin = SMAppService.mainApp.status == .enabled
                }
            }
        Divider()
        Button("데이터 폴더 열기") { NSWorkspace.shared.open(delegate.store.dataDir) }
        Divider()
        Button("종료") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
