import AppKit
import SwiftUI
import Combine
import Carbon

func selfTest() {
    func check(_ condition: Bool, _ description: String) {
        guard condition else { fputs("FAIL: \(description)\n", stderr); exit(1) }
        print("PASS: \(description)")
    }
    var state = CapsPressState()
    check(state.update(device: 1, pressed: true), "first press switches")
    check(!state.update(device: 1, pressed: true), "held key does not repeat")
    check(!state.update(device: 1, pressed: false), "release does not switch")
    check(state.update(device: 1, pressed: true), "second press switches")
    check(state.update(device: 2, pressed: true), "second keyboard is independent")
    state.remove(device: 1)
    check(state.update(device: 1, pressed: true), "reconnected keyboard resets")
    check(InputSources.nextID(in: ["en", "ru", "ka"], current: "ru") == "ka", "cycle follows enabled order")
    check(InputSources.nextID(in: ["en", "ru"], current: "ru") == "en", "cycle wraps")
    check(InputSources.nextID(in: ["en"], current: "en") == nil, "single layout does not switch")
    check(InputSources.nextID(in: [], current: "en") == nil, "empty list is safe")
    check(InputSources.nextID(in: ["en", "ru"], current: "removed") == "en", "removed current source recovers")
}
if CommandLine.arguments.contains("--self-test") { selfTest(); exit(0) }
if CommandLine.arguments.contains("--diagnose") {
    print("Accessibility: \(CapsMonitor.hasAccessibility)")
    print("Input Monitoring: \(CapsMonitor.hasInputMonitoring)")
    print("Current: \(InputSources.current.id) — \(InputSources.current.name)")
    for source in InputSources.enabled { print("Enabled: \(source.id) — \(source.name) [\(source.badge)]") }
    exit(0)
}
if CommandLine.arguments.contains("--smoke-test") {
    _ = NSApplication.shared
    let original = InputSources.current
    let status = InputSources.selectNext()
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    let changed = InputSources.current
    let restore = TISSelectInputSource(original.source)
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    print("Switch status: \(status); \(original.name) → \(changed.name)")
    print("Restore status: \(restore); current: \(InputSources.current.name)")
    exit(status == noErr && changed.id != original.id && restore == noErr && InputSources.current.id == original.id ? 0 : 1)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    private var item: NSStatusItem!
    private var window: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { others.first?.activate(); NSApp.terminate(nil); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "capslock", accessibilityDescription: "CapsFlow")
        item.button?.toolTip = "CapsFlow — переключение раскладки"
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        model.$current.sink { [weak self] source in self?.item?.button?.title = " \(source.badge)" }.store(in: &subscriptions)
        if !model.running { showSettings() }
        if CommandLine.arguments.contains("--preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.model.hud.show(self.model.current, duration: 6, position: self.model.position)
            }
        }
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "CapsFlow · \(model.current.name)", action: nil, keyEquivalent: "")
        menu.addItem(title)
        add(menu, model.paused ? "Возобновить Caps Lock" : "Приостановить Caps Lock", #selector(togglePause))
        menu.addItem(.separator())
        add(menu, "Переключить раскладку", #selector(switchLayout))
        add(menu, "Показать плашку", #selector(preview))
        add(menu, "Настройки…", #selector(showSettings), key: ",")
        menu.addItem(.separator())
        add(menu, "Выйти из CapsFlow", #selector(quit), key: "q")
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
    }
    @objc func showSettings() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let view = NSWindow(contentViewController: controller)
            view.title = "CapsFlow"; view.styleMask = [.titled, .closable, .miniaturizable]
            view.isReleasedWhenClosed = false; view.center(); window = view
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc func togglePause() { model.togglePause() }
    @objc func switchLayout() { model.switchLayout() }
    @objc func preview() { model.preview() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.monitor.stop() }
}
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
