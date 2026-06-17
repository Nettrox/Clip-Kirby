import AppKit
import Carbon
import ApplicationServices

extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255,
            alpha: 1
        )
    }
}

enum Theme {
    static let pink = NSColor(hex: "#f06993")
    static let darkPink = NSColor(hex: "#d84e7a")
    static let palePink = NSColor(hex: "#ffd3e1")
    static let text = NSColor.white
    static let secondaryText = NSColor.white.withAlphaComponent(0.78)
    static let card = NSColor.white.withAlphaComponent(0.16)
    static let cardBorder = NSColor.white.withAlphaComponent(0.18)
}

struct ClipboardItem: Equatable {
    let text: String
    let date: Date
}

final class ClipboardStore {
    private(set) var items: [ClipboardItem] = []
    private var changeCount = NSPasteboard.general.changeCount
    private let maxItems = 8

    func start() {
        Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.sync()
        }
    }

    func sync() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string) else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0.text == text }
        items.insert(ClipboardItem(text: text, date: Date()), at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
    }

    func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        changeCount = pasteboard.changeCount
    }
}

final class PasteTarget {
    private weak var app: NSRunningApplication?
    private var focusedElement: AXUIElement?

    func capture() {
        let currentPid = NSRunningApplication.current.processIdentifier
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        guard frontmost.processIdentifier != currentPid else { return }
        app = frontmost
        focusedElement = nil

        let axApp = AXUIElementCreateApplication(frontmost.processIdentifier)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &value) == .success, let value {
            focusedElement = (value as! AXUIElement)
        }
    }

    func restore() {
        guard let app, !app.isTerminated else { return }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if let focusedElement {
            AXUIElementSetAttributeValue(focusedElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }
}

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

protocol SearchFieldKeys: AnyObject {
    func searchPressedEscape()
    func searchPressedEnter()
    func searchPressedUp()
    func searchPressedDown()
}

final class SearchField: NSSearchField {
    weak var keys: SearchFieldKeys?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: keys?.searchPressedEscape()
        case 36, 76: keys?.searchPressedEnter()
        case 126: keys?.searchPressedUp()
        case 125: keys?.searchPressedDown()
        default: super.keyDown(with: event)
        }
    }
}

final class RowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        Theme.darkPink.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 4), xRadius: 14, yRadius: 14).fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {}
}

final class CellView: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = Theme.card.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.cardBorder.cgColor

        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = Theme.text
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = Theme.secondaryText
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        addSubview(title)
        addSubview(subtitle)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func render(_ item: ClipboardItem) {
        title.stringValue = item.text.replacingOccurrences(of: "\n", with: " ")
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        subtitle.stringValue = formatter.localizedString(for: item.date, relativeTo: Date())
    }
}

final class ClipboardWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, SearchFieldKeys {
    private let store: ClipboardStore
    private let target: PasteTarget
    private let search = SearchField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let empty = NSTextField(labelWithString: "Clipboard history is empty")
    private var filtered: [ClipboardItem] = []
    private var keyMonitor: Any?
    private var opening = false
    private var pasting = false

    init(store: ClipboardStore, target: PasteTarget) {
        self.store = store
        self.target = target

        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 390),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        removeKeyMonitor()
    }

    private func buildUI() {
        guard let view = window?.contentView else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.pink.cgColor
        view.layer?.cornerRadius = 22
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = Theme.palePink.withAlphaComponent(0.75).cgColor

        search.placeholderString = "Search clipboard"
        search.delegate = self
        search.keys = self
        search.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(search)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.width = 430
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 62
        table.intercellSpacing = NSSize(width: 0, height: 5)
        table.backgroundColor = .clear
        table.focusRingType = .none
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clickedRow)

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        empty.textColor = Theme.secondaryText
        empty.alignment = .center
        empty.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(empty)

        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            search.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            search.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            search.heightAnchor.constraint(equalToConstant: 34),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
    }

    func showBoard() {
        target.capture()
        store.sync()
        opening = true
        pasting = false
        search.stringValue = ""
        reload()
        moveNearMouse()
        installKeyMonitor()
        window?.orderFrontRegardless()
        window?.makeKey()
        search.becomeFirstResponder()
        if !filtered.isEmpty { select(0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.opening = false
        }
    }

    private func reload() {
        let selected = selectedText()
        let query = search.stringValue.lowercased()
        filtered = query.isEmpty ? store.items : store.items.filter { $0.text.lowercased().contains(query) }
        empty.isHidden = !filtered.isEmpty
        table.reloadData()
        guard !filtered.isEmpty else { return table.deselectAll(nil) }
        if let selected, let index = filtered.firstIndex(where: { $0.text == selected }) {
            select(index)
        } else {
            select(0)
        }
    }

    private func selectedText() -> String? {
        let row = table.selectedRow
        return row >= 0 && row < filtered.count ? filtered[row].text : nil
    }

    private func select(_ row: Int) {
        guard row >= 0 && row < filtered.count else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    private func moveNearMouse() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? .zero
        let size = window.frame.size
        var x = mouse.x - size.width / 2
        var y = mouse.y - size.height - 14
        x = max(frame.minX + 12, min(x, frame.maxX - size.width - 12))
        if y < frame.minY + 12 { y = mouse.y + 14 }
        y = min(y, frame.maxY - size.height - 12)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true else { return event }
            switch event.keyCode {
            case 53: self.closeBoard(); return nil
            case 36, 76: self.pasteSelected(); return nil
            case 126: self.moveSelection(-1); return nil
            case 125: self.moveSelection(1); return nil
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func moveSelection(_ offset: Int) {
        guard !filtered.isEmpty else { return }
        let current = table.selectedRow < 0 ? 0 : table.selectedRow
        let next = (current + offset + filtered.count) % filtered.count
        select(next)
    }

    private func closeBoard() {
        removeKeyMonitor()
        window?.orderOut(nil)
        target.restore()
    }

    @objc private func clickedRow() {
        pasteSelected()
    }

    private func pasteSelected() {
        guard !opening, !pasting else { return }
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard row >= 0 && row < filtered.count else { return }
        pasting = true
        let text = filtered[row].text
        removeKeyMonitor()
        window?.orderOut(nil)
        store.write(text)
        target.restore()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.target.restore()
            Self.sendCommandV()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.pasting = false
        }
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    func controlTextDidChange(_ obj: Notification) { reload() }
    func searchPressedEscape() { closeBoard() }
    func searchPressedEnter() { pasteSelected() }
    func searchPressedUp() { moveSelection(-1) }
    func searchPressedDown() { moveSelection(1) }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = CellView()
        cell.render(filtered[row])
        return cell
    }
}

final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func register() {
        let id = EventHotKeyID(signature: OSType(0x434B4259), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKey)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().callback()
            return noErr
        }, 1, &eventType, pointer, &handler)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipboardStore()
    private let target = PasteTarget()
    private var board: ClipboardWindow?
    private var hotKey: HotKeyManager?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        store.start()
        board = ClipboardWindow(store: store, target: target)
        hotKey = HotKeyManager { [weak self] in
            DispatchQueue.main.async {
                self?.board?.showBoard()
            }
        }
        hotKey?.register()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            if let image = loadStatusIcon() {
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.title = "⌘V"
                button.contentTintColor = Theme.pink
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Clipboard", action: #selector(openBoardFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func loadStatusIcon() -> NSImage? {
        for name in ["StatusIconTemplate", "StatusIcon", "MenuBarIcon"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) else { continue }
            image.size = NSSize(width: 18, height: 18)
            return tinted(image)
        }
        return nil
    }

    private func tinted(_ image: NSImage) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        Theme.pink.setFill()
        rect.fill(using: .sourceAtop)
        result.unlockFocus()
        return result
    }

    @objc private func openBoardFromMenu() {
        board?.showBoard()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
