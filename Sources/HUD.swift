import AppKit
import SwiftUI

enum HUDPosition: String, CaseIterable, Identifiable {
    case center, bottom
    var id: String { rawValue }
    var title: String { self == .center ? "По центру" : "Снизу" }
}
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
struct HUDView: View {
    let source: KeyboardSource
    var body: some View {
        HStack(spacing: 14) {
            Text(source.badge)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .frame(width: 64, height: 58)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text("Раскладка клавиатуры").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 304, height: 94)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
final class HUDController {
    private let panel = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: 304, height: 94),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var hide: DispatchWorkItem?
    private var generation = 0
    init() {
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
    }
    func show(_ source: KeyboardSource, duration: Double = 0.5, position: HUDPosition = .center) {
        hide?.cancel(); generation += 1
        let token = generation
        panel.contentView = NSHostingView(rootView: HUDView(source: source))
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let screen {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 152,
                y: position == .center ? frame.midY - 47 : frame.minY + 90))
        }
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.09
            panel.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == token else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
                self.panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self, generation == token else { return }
                self.panel.orderOut(nil)
            }
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
