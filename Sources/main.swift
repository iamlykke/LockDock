import AppKit
import ApplicationServices
import ServiceManagement

// The Dock jumps to a display when the cursor is pushed against that display's
// Dock edge. LockDock keeps the cursor a couple of pixels away from that edge on
// every display except the chosen one, so the Dock never gets the trigger.

private let edgeMargin: CGFloat = 2
private let lockedDisplayKey = "LockedDisplayUUID"
private let enabledKey = "Enabled"
private let iconHiddenKey = "MenuBarIconHidden"

final class DockGuard {
    static let shared = DockGuard()

    enum Orientation { case bottom, left, right }

    var lockedUUID: String? {
        didSet { UserDefaults.standard.set(lockedUUID, forKey: lockedDisplayKey) }
    }
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: enabledKey) }
    }
    private(set) var orientation: Orientation = .bottom
    private var displays: [(id: CGDirectDisplayID, bounds: CGRect)] = []
    private(set) var lockedID: CGDirectDisplayID?
    var tap: CFMachPort?

    private init() {
        lockedUUID = UserDefaults.standard.string(forKey: lockedDisplayKey)
            ?? DockGuard.uuid(for: CGMainDisplayID())
        enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        refreshDisplays()
        refreshOrientation()
    }

    static func uuid(for id: CGDirectDisplayID) -> String? {
        guard let ref = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, ref) as String
    }

    func refreshDisplays() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        displays = ids.prefix(Int(count)).map { ($0, CGDisplayBounds($0)) }
        lockedID = displays.first { DockGuard.uuid(for: $0.id) == lockedUUID }?.id
    }

    func refreshOrientation() {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let value = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
        switch value {
        case "left": orientation = .left
        case "right": orientation = .right
        default: orientation = .bottom
        }
    }

    private func onAnyDisplay(_ p: CGPoint) -> Bool {
        displays.contains { $0.bounds.contains(p) }
    }

    /// Returns a corrected cursor position, or nil if the event can pass as is.
    func clamp(_ p: CGPoint) -> CGPoint? {
        guard enabled, let lockedID,
              let current = displays.first(where: { $0.bounds.contains(p) }),
              current.id != lockedID else { return nil }
        let b = current.bounds
        var q = p
        // Only outer edges count: an edge shared with another display must stay passable.
        switch orientation {
        case .bottom:
            let limit = b.maxY - 1 - edgeMargin
            if p.y > limit && !onAnyDisplay(CGPoint(x: p.x, y: b.maxY + 1)) { q.y = limit }
        case .left:
            let limit = b.minX + edgeMargin
            if p.x < limit && !onAnyDisplay(CGPoint(x: b.minX - 1, y: p.y)) { q.x = limit }
        case .right:
            let limit = b.maxX - 1 - edgeMargin
            if p.x > limit && !onAnyDisplay(CGPoint(x: b.maxX + 1, y: p.y)) { q.x = limit }
        }
        return q == p ? nil : q
    }
}

private let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = DockGuard.shared.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if let p = DockGuard.shared.clamp(event.location) {
        event.location = p
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
    return Unmanaged.passUnretained(event)
}

// MARK: - Menu bar icon

/// Monitor with the Dock bar; `locked` adds a padlock badge, otherwise the bar is hollow.
private func statusIcon(locked: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
        NSColor.black.set()

        let screen = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 4.5, width: 15, height: 11), xRadius: 2, yRadius: 2)
        screen.lineWidth = 1.5
        screen.stroke()
        NSBezierPath(roundedRect: NSRect(x: 6, y: 1.5, width: 6, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
        NSRect(x: 8.25, y: 2.5, width: 1.5, height: 2).fill()

        let bar = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 6.75, width: 9, height: 2.5), xRadius: 1.25, yRadius: 1.25)
        if locked {
            bar.fill()

            // Cut a gap around the padlock, then draw it.
            let ctx = NSGraphicsContext.current!
            ctx.compositingOperation = .clear
            NSBezierPath(roundedRect: NSRect(x: 11, y: 0, width: 9, height: 10.5), xRadius: 2.5, yRadius: 2.5).fill()
            ctx.compositingOperation = .sourceOver

            NSBezierPath(roundedRect: NSRect(x: 12.5, y: 1, width: 6.5, height: 5), xRadius: 1.2, yRadius: 1.2).fill()
            let shackle = NSBezierPath()
            shackle.move(to: NSPoint(x: 13.9, y: 5.5))
            shackle.line(to: NSPoint(x: 13.9, y: 7.2))
            shackle.appendArc(withCenter: NSPoint(x: 15.75, y: 7.2), radius: 1.85, startAngle: 180, endAngle: 0, clockwise: true)
            shackle.line(to: NSPoint(x: 17.6, y: 5.5))
            shackle.lineWidth = 1.3
            shackle.stroke()
        } else {
            bar.lineWidth = 1
            bar.stroke()
        }
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        // Without permission the icon is the only way to see what's wrong, so keep it then.
        statusItem.isVisible = !UserDefaults.standard.bool(forKey: iconHiddenKey) || !AXIsProcessTrusted()
        updateStatusIcon()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DockGuard.shared.refreshDisplays()
            self?.updateStatusIcon()
        }
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            DockGuard.shared.refreshOrientation()
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if !installTap() {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                if self?.installTap() == true { timer.invalidate() }
            }
        }
    }

    private func installTap() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let mask: CGEventMask = [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            .reduce(0) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: tapCallback, userInfo: nil
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        DockGuard.shared.tap = tap
        updateStatusIcon()
        return true
    }

    private var isActive: Bool {
        let guardian = DockGuard.shared
        return guardian.tap != nil && guardian.enabled && guardian.lockedID != nil
    }

    private func updateStatusIcon() {
        statusItem.button?.image = statusIcon(locked: isActive)
        statusItem.button?.toolTip = "LockDock"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        let guardian = DockGuard.shared
        guardian.refreshDisplays()
        menu.removeAllItems()

        menu.addItem(statusLine())

        if guardian.tap == nil {
            menu.addItem(actionItem("Открыть настройки доступа…", #selector(openAccessibilitySettings),
                                    symbol: "hand.raised"))
        } else {
            let toggle = actionItem("Блокировка Dock", #selector(toggleEnabled), key: "l")
            toggle.state = guardian.enabled ? .on : .off
            menu.addItem(toggle)
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Экран для Dock"))
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = DockGuard.uuid(for: number.uint32Value) else { continue }
            let item = actionItem(screen.localizedName, #selector(selectScreen(_:)),
                                  key: index < 9 ? "\(index + 1)" : "",
                                  symbol: CGDisplayIsBuiltin(number.uint32Value) != 0 ? "laptopcomputer" : "display")
            item.representedObject = uuid
            item.state = uuid == guardian.lockedUUID ? .on : .off
            var details = nativeResolution(of: number.uint32Value)
            if CGDisplayIsMain(number.uint32Value) != 0 { details += " · основной" }
            item.subtitle = details
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let login = actionItem("Открывать при входе", #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(actionItem("Скрыть значок в строке меню", #selector(hideIcon)))
        menu.addItem(actionItem("О программе LockDock", #selector(showAbout)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Завершить LockDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// Physical panel resolution, not the scaled "looks like" size NSScreen reports.
    private func nativeResolution(of id: CGDirectDisplayID) -> String {
        let nativeFlag: UInt32 = 0x0200_0000 // kDisplayModeNativeFlag
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
        if let native = modes.first(where: { $0.ioFlags & nativeFlag != 0 }) {
            return "\(native.pixelWidth)×\(native.pixelHeight)"
        }
        let current = CGDisplayCopyDisplayMode(id)
        return "\(current?.pixelWidth ?? 0)×\(current?.pixelHeight ?? 0)"
    }

    private func statusLine() -> NSMenuItem {
        let guardian = DockGuard.shared
        let (text, color): (String, NSColor)
        if guardian.tap == nil {
            (text, color) = ("Нужен «Универсальный доступ»", .systemOrange)
        } else if !guardian.enabled {
            (text, color) = ("Приостановлено", .secondaryLabelColor)
        } else if guardian.lockedID == nil {
            (text, color) = ("Выбранный экран не подключён", .systemOrange)
        } else {
            (text, color) = ("Dock закреплён", .systemGreen)
        }
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        let title = NSMutableAttributedString(string: "● ", attributes: [
            .foregroundColor: color, .font: NSFont.menuFont(ofSize: 0),
        ])
        title.append(NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.labelColor, .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
        ]))
        item.attributedTitle = title
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "", symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    @objc private func selectScreen(_ sender: NSMenuItem) {
        DockGuard.shared.lockedUUID = sender.representedObject as? String
        DockGuard.shared.refreshDisplays()
        updateStatusIcon()
    }

    @objc private func toggleEnabled() {
        DockGuard.shared.enabled.toggle()
        updateStatusIcon()
    }

    // Opening the app again (Finder, Spotlight, Launchpad) brings the icon back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UserDefaults.standard.set(false, forKey: iconHiddenKey)
        statusItem.isVisible = true
        return false
    }

    @objc private func hideIcon() {
        let alert = NSAlert()
        alert.messageText = "Скрыть значок LockDock?"
        alert.informativeText = "LockDock продолжит работать в фоне. Чтобы вернуть значок, снова откройте LockDock через Finder, Spotlight или Launchpad."
        alert.addButton(withTitle: "Скрыть")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.set(true, forKey: iconHiddenKey)
        statusItem.isVisible = false
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Не удалось изменить объекты входа"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Держит Dock на выбранном экране."),
        ])
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
