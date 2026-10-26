import AppKit
import IOKit.hid
import IOKit.hidsystem
import Carbon

final class CapsMonitor {
    private var manager: IOHIDManager?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var connection: io_connect_t = 0
    private var presses = CapsPressState()
    private var clearQueued = false
    var onPress: (() -> Void)?
    var isRunning: Bool { manager != nil && tap != nil }
    static var hasAccessibility: Bool { AXIsProcessTrusted() }
    static var hasInputMonitoring: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    func start() -> Bool {
        if isRunning { return true }
        guard Self.hasAccessibility, Self.hasInputMonitoring else { return false }
        stop()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let mask = [CGEventType.flagsChanged, .keyDown, .keyUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<CapsMonitor>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                if event.flags.contains(.maskAlphaShift) {
                    event.flags.remove(.maskAlphaShift)
                    monitor.queueClearLock()
                }
                if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_CapsLock) { return nil }
                return Unmanaged.passUnretained(event)
            }, userInfo: context) else { return false }
        tap = newTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        if service != 0 {
            IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
            IOObjectRelease(service)
        }
        clearLock()
        let hid = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(hid, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                          kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        IOHIDManagerSetInputValueMatching(hid, [kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad,
                                              kIOHIDElementUsageKey: kHIDUsage_KeyboardCapsLock] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(hid, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let monitor = Unmanaged<CapsMonitor>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == kHIDPage_KeyboardOrKeypad,
                  IOHIDElementGetUsage(element) == kHIDUsage_KeyboardCapsLock else { return }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(IOHIDElementGetDevice(element)), &id)
            if monitor.presses.update(device: id, pressed: IOHIDValueGetIntegerValue(value) != 0) {
                monitor.onPress?()
                monitor.queueClearLock()
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hid, { context, _, _, device in
            guard let context else { return }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
            Unmanaged<CapsMonitor>.fromOpaque(context).takeUnretainedValue().presses.remove(device: id)
        }, context)
        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        manager = hid
        guard IOHIDManagerOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            stop(); return false
        }
        return true
    }
    private func queueClearLock() {
        guard !clearQueued else { return }
        clearQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.clearQueued = false
            self?.clearLock()
        }
    }
    private func clearLock() {
        guard connection != 0 else { return }
        var locked = false
        if IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &locked) == kIOReturnSuccess, locked {
            IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), false)
        }
    }
    func stop() {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        }
        manager = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil; tap = nil
        if connection != 0 { IOServiceClose(connection); connection = 0 }
        presses = CapsPressState()
    }
    deinit { stop() }
}
