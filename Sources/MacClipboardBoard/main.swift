import AppKit
import Carbon
import ApplicationServices

final class ClipboardItem: Equatable {
    let text: String
    let date: Date

    init(text: String, date: Date = Date()) {
        self.text = text
        self.date = date
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.text == rhs.text
    }
}

final class ClipboardStore {
    private(set) var items: [ClipboardItem] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let maxItems = 40

    func start() {
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string) else { return }
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        items.removeAll { $0.text == text }
        items.insert(ClipboardItem(text: text), at: 0)

        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
    }

    func setClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }
}

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

protocol BoardSearchFieldKeyDelegate: AnyObject {
    func boardSearchFieldDidPressEscape()
    func boardSearchFieldDidPressEnter()
    func boardSearchFieldDidPressArrowUp()
    func boardSearchFieldDidPressArrowDown()
}

final class BoardSearchField: NSSearchField {
    weak var keyDelegate: BoardSearchFieldKeyDelegate?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            keyDelegate?.boardSearchFieldDidPressEscape()
        case 36, 76:
            keyDelegate?.boardSearchFieldDidPressEnter()
        case 126:
            keyDelegate?.boardSearchFieldDidPressArrowUp()
        case 125:
            keyDelegate?.boardSearchFieldDidPressArrowDown()
        default:
            super.keyDown(with: event)
        }
    }
}

final class ClipboardWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, BoardSearchFieldKeyDelegate {
    private let store: ClipboardStore
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let searchField = BoardSearchField()
    private let emptyLabel = NSTextField(labelWithString: "Clipboard history is empty")
    private var filteredItems: [ClipboardItem] = []
    private weak var targetApplication: NSRunningApplication?
    private var targetFocusedElement: AXUIElement?
    private var isOpeningBoard = false
    private var localKeyMonitor: Any?

    init(store: ClipboardStore) {
        self.store = store

        let window = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 390),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Clipboard"
        window.level = .popUpMenu
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        removeLocalKeyMonitor()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        searchField.placeholderString = "Search clipboard"
        searchField.delegate = self
        searchField.keyDelegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clipboard"))
        column.title = ""
        column.width = 430

        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 58
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(useSelectedItem)
        tableView.doubleAction = #selector(useSelectedItem)
        tableView.allowsEmptySelection = false
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 44),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])

        refresh()
    }

    func showBoard() {
        capturePasteTarget()
        isOpeningBoard = true
        refresh()
        positionNearMouse()
        installLocalKeyMonitor()
        window?.orderFrontRegardless()
        window?.makeKey()
        searchField.stringValue = ""
        searchField.becomeFirstResponder()

        if !filteredItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isOpeningBoard = false
        }
    }

    private func installLocalKeyMonitor() {
        removeLocalKeyMonitor()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true else { return event }

            switch event.keyCode {
            case 53:
                self.closeBoardAndRestoreTarget()
                return nil
            case 36, 76:
                self.useSelectedItem()
                return nil
            case 126:
                self.selectPreviousItem()
                return nil
            case 125:
                self.selectNextItem()
                return nil
            default:
                return event
            }
        }
    }

    private func removeLocalKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func capturePasteTarget() {
        targetFocusedElement = nil
        let currentApp = NSRunningApplication.current
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.processIdentifier != currentApp.processIdentifier else { return }

        targetApplication = frontmostApp

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var focusedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)

        if result == .success, let focusedValue {
            targetFocusedElement = (focusedValue as! AXUIElement)
        }
    }

    private func positionNearMouse() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = window.frame.size

        var x = mouse.x - size.width / 2
        var y = mouse.y - size.height - 14

        if x < visibleFrame.minX + 12 { x = visibleFrame.minX + 12 }
        if x + size.width > visibleFrame.maxX - 12 { x = visibleFrame.maxX - size.width - 12 }
        if y < visibleFrame.minY + 12 { y = mouse.y + 14 }
        if y + size.height > visibleFrame.maxY - 12 { y = visibleFrame.maxY - size.height - 12 }

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func refresh() {
        let selectedText = selectedItemText()
        let query = searchField.stringValue.lowercased()

        if query.isEmpty {
            filteredItems = store.items
        } else {
            filteredItems = store.items.filter { $0.text.lowercased().contains(query) }
        }

        emptyLabel.isHidden = !filteredItems.isEmpty
        tableView.reloadData()

        if filteredItems.isEmpty {
            tableView.deselectAll(nil)
            return
        }

        if let selectedText, let index = filteredItems.firstIndex(where: { $0.text == selectedText }) {
            selectRow(index)
        } else {
            selectRow(0)
        }
    }

    private func selectedItemText() -> String? {
        let row = tableView.selectedRow
        guard row >= 0 && row < filteredItems.count else { return nil }
        return filteredItems[row].text
    }

    func controlTextDidChange(_ obj: Notification) {
        refresh()
    }

    func boardSearchFieldDidPressEscape() {
        closeBoardAndRestoreTarget()
    }

    func boardSearchFieldDidPressEnter() {
        useSelectedItem()
    }

    func boardSearchFieldDidPressArrowUp() {
        selectPreviousItem()
    }

    func boardSearchFieldDidPressArrowDown() {
        selectNextItem()
    }

    private func selectPreviousItem() {
        guard !filteredItems.isEmpty else { return }
        let currentRow = tableView.selectedRow
        let nextRow = currentRow <= 0 ? filteredItems.count - 1 : currentRow - 1
        selectRow(nextRow)
    }

    private func selectNextItem() {
        guard !filteredItems.isEmpty else { return }
        let currentRow = tableView.selectedRow
        let nextRow = currentRow < 0 || currentRow >= filteredItems.count - 1 ? 0 : currentRow + 1
        selectRow(nextRow)
    }

    private func selectRow(_ row: Int) {
        guard row >= 0 && row < filteredItems.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0 && row < filteredItems.count else { return nil }

        let item = filteredItems[row]
        let cell = ClipboardCell()
        cell.configure(with: item)
        return cell
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            closeBoardAndRestoreTarget()
        case 36, 76:
            useSelectedItem()
        case 126:
            selectPreviousItem()
        case 125:
            selectNextItem()
        default:
            super.keyDown(with: event)
        }
    }

    private func closeBoardAndRestoreTarget() {
        removeLocalKeyMonitor()
        window?.orderOut(nil)
        restorePasteTarget()
    }

    @objc private func useSelectedItem() {
        guard !isOpeningBoard else { return }

        let clickedRow = tableView.clickedRow
        let selectedRow = clickedRow >= 0 ? clickedRow : tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < filteredItems.count else { return }

        let item = filteredItems[selectedRow]
        store.setClipboard(item.text)
        removeLocalKeyMonitor()
        window?.orderOut(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.restorePasteTarget()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            Self.sendPasteShortcut()
        }
    }

    private func restorePasteTarget() {
        if let targetApplication, !targetApplication.isTerminated {
            targetApplication.activate(options: [.activateIgnoringOtherApps])
        }

        if let targetFocusedElement {
            AXUIElementSetAttributeValue(targetFocusedElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }

    private static func sendPasteShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

final class ClipboardCell: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
        ])
    }

    func configure(with item: ClipboardItem) {
        titleLabel.stringValue = item.text.replacingOccurrences(of: "\n", with: " ")
        detailLabel.stringValue = formatDate(item.date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func register() {
        var hotKeyID = EventHotKeyID(signature: OSType(0x4D43424F), id: UInt32(1))
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(kVK_ANSI_V)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            manager.callback()
            return noErr
        }, 1, &eventType, selfPointer, &handlerRef)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipboardStore()
    private var windowController: ClipboardWindowController?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        requestAccessibilityIfNeeded()

        store.start()

        windowController = ClipboardWindowController(store: store)
        hotKeyManager = HotKeyManager { [weak self] in
            DispatchQueue.main.async {
                self?.store.checkClipboard()
                self?.windowController?.showBoard()
            }
        }
        hotKeyManager?.register()

        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if let icon = loadStatusIcon() {
                button.image = icon
                button.imagePosition = .imageOnly
                button.title = ""
            } else {
                button.title = "⌘V"
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Clipboard", action: #selector(openBoard), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func loadStatusIcon() -> NSImage? {
        let candidates: [(name: String, isTemplate: Bool)] = [
            ("StatusIconTemplate", true),
            ("StatusIcon", false),
            ("MenuBarIcon", false)
        ]

        for candidate in candidates {
            if let iconURL = Bundle.main.url(forResource: candidate.name, withExtension: "png"), let icon = NSImage(contentsOf: iconURL) {
                icon.isTemplate = candidate.isTemplate
                icon.size = NSSize(width: 18, height: 18)
                return icon
            }
        }

        return nil
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc private func openBoard() {
        store.checkClipboard()
        windowController?.showBoard()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
