import AppKit
import SwiftUI
import ServiceManagement
import Carbon
import IOKit.hidsystem

final class AppModel: ObservableObject {
    @Published var running = false
    @Published var paused = false
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published var current = InputSources.current
    @Published var error: String?
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var position: HUDPosition = HUDPosition(rawValue: UserDefaults.standard.string(forKey: "hudPosition") ?? "") ?? .center {
        didSet { UserDefaults.standard.set(position.rawValue, forKey: "hudPosition") }
    }
    let monitor = CapsMonitor()
    let hud = HUDController()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    init() {
        monitor.onPress = { [weak self] in self?.switchLayout() }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in self?.current = InputSources.current }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }
    func refresh() {
        accessibility = CapsMonitor.hasAccessibility
        inputMonitoring = CapsMonitor.hasInputMonitoring
        if !accessibility || !inputMonitoring || paused {
            monitor.stop(); running = false
        } else {
            running = monitor.start()
        }
        current = InputSources.current
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
    func switchLayout() {
        guard InputSources.enabled.count > 1 else {
            error = "Добавьте вторую раскладку в настройках клавиатуры macOS."
            return
        }
        let status = InputSources.selectNext()
        guard status == noErr else { error = "Не удалось переключить раскладку (\(status))."; return }
        error = nil
        current = InputSources.current
        hud.show(current, position: position)
    }
    func preview() { hud.show(current, position: position) }
    func togglePause() { paused.toggle(); refresh() }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings("Privacy_Accessibility")
    }
    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openSettings("Privacy_ListenEvent")
    }
    func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }
    func keyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
        } catch { self.error = error.localizedDescription }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "capslock.fill").font(.system(size: 29)).foregroundStyle(.blue)
                    .frame(width: 58, height: 58).background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("CapsFlow").font(.system(size: 26, weight: .semibold))
                    Text("Одна клавиша. Нужная раскладка.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                Circle().fill(model.running ? .green : .orange).frame(width: 8, height: 8)
                Text(model.running ? "Caps Lock работает во всех приложениях" : model.paused ? "Переключение приостановлено" : "Нужны разрешения macOS")
                    .font(.system(size: 12, weight: .medium))
            }
            GroupBox {
                VStack(spacing: 14) {
                    permission("Универсальный доступ", detail: "Чтобы перехватывать Caps Lock", granted: model.accessibility, action: model.requestAccessibility)
                    Divider()
                    permission("Мониторинг ввода", detail: "Чтобы реагировать на каждое нажатие", granted: model.inputMonitoring, action: model.requestInputMonitoring)
                }.padding(10)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Положение плашки")
                        Spacer()
                        Picker("Положение", selection: $model.position) {
                            ForEach(HUDPosition.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 146)
                    }
                    HStack {
                        Text("Быстро появляется, плавно исчезает").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Показать") { model.preview() }
                    }
                    Divider()
                    Toggle("Запускать при входе в macOS", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                }.padding(10)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Отключите системное переключение Caps Lock").font(.system(size: 13, weight: .semibold))
                Text("Настройки системы → Клавиатура → Ввод текста → Изменить → «Все источники ввода». Выключите «Использовать Caps Lock для переключения…».")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Открыть настройки клавиатуры…", action: model.keyboardSettings).buttonStyle(.link)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Text("Сейчас: \(model.current.name)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.paused ? "Возобновить" : "Пауза", action: model.togglePause)
            }
        }
        .padding(28).frame(width: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    func permission(_ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted { Text("Разрешено").font(.caption).foregroundStyle(.secondary) }
            else { Button("Разрешить…", action: action) }
        }
    }
}
