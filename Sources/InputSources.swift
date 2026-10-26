import AppKit
import Carbon

struct KeyboardSource: Identifiable {
    let source: TISInputSource
    let id: String
    let name: String
    let language: String
    var badge: String {
        let code = language.split(separator: "-").first.map(String.init) ?? ""
        return code.isEmpty ? String(name.prefix(2)).uppercased() : code.uppercased()
    }
    init(_ source: TISInputSource) {
        self.source = source
        func property(_ key: CFString) -> AnyObject? {
            guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
            return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
        }
        id = property(kTISPropertyInputSourceID) as? String ?? ""
        name = property(kTISPropertyLocalizedName) as? String ?? "Keyboard"
        language = (property(kTISPropertyInputSourceLanguages) as? [String])?.first ?? ""
    }
}

enum InputSources {
    static var current: KeyboardSource { KeyboardSource(TISCopyCurrentKeyboardInputSource().takeRetainedValue()) }
    static var enabled: [KeyboardSource] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceIsEnabled as String: true
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.map(KeyboardSource.init)
    }
    static func nextID(in ids: [String], current: String) -> String? {
        guard ids.count > 1 else { return nil }
        guard let index = ids.firstIndex(of: current) else { return ids.first }
        return ids[(index + 1) % ids.count]
    }
    @discardableResult static func selectNext() -> OSStatus {
        let sources = enabled
        guard let id = nextID(in: sources.map(\.id), current: current.id),
              let source = sources.first(where: { $0.id == id }) else { return -1 }
        return TISSelectInputSource(source.source)
    }
}

// Tracks physical down/up edges per keyboard. Holding the key never repeats.
struct CapsPressState {
    private var down: Set<UInt64> = []
    mutating func update(device: UInt64, pressed: Bool) -> Bool {
        if pressed { return down.insert(device).inserted }
        down.remove(device)
        return false
    }
    mutating func remove(device: UInt64) { down.remove(device) }
}
