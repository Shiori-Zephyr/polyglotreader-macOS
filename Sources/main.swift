import Cocoa
import UniformTypeIdentifiers

// ============================================================
// Configuration
// ============================================================

struct AppConfig: Codable {
    var fontName: String = "Menlo"
    var fontSize: CGFloat = 14
    var linesPerPage: Int = 40
    var windowWidth: CGFloat = 1200
    var windowHeight: CGFloat = 800
    var followSystemAppearance: Bool = true
}

let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".polyglot_reader")
let configPath = configDir.appendingPathComponent("config.json")
let libraryPath = configDir.appendingPathComponent("library.json")

let textExtensions: Set<String> = [
    "txt", "text", "md", "log", "csv", "json", "xml", "html",
    "py", "js", "c", "h", "cpp", "java", "rb", "go", "rs",
    "swift", "kt", "sh", "bat", "ini", "cfg", "yaml", "yml", "toml"
]

let supportedEncodings: [(name: String, encoding: String.Encoding)] = [
    ("UTF-8", .utf8),
    ("GB18030", String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))),
    ("GBK", String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GBK_95.rawValue)))),
    ("Shift_JIS", .shiftJIS),
    ("EUC-JP", .japaneseEUC),
    ("EUC-KR", String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))),
    ("Big5", String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))),
    ("ISO-8859-1", .isoLatin1),
    ("Windows-1252", .windowsCP1252),
]

// ============================================================
// Config & Library Management
// ============================================================

func ensureConfigDir() {
    try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
}

func loadConfig() -> AppConfig {
    ensureConfigDir()
    guard let data = try? Data(contentsOf: configPath),
          let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
        return AppConfig()
    }
    return config
}

func saveConfig(_ config: AppConfig) {
    ensureConfigDir()
    if let data = try? JSONEncoder().encode(config) {
        try? data.write(to: configPath)
    }
}

func loadLibrary() -> [String] {
    ensureConfigDir()
    guard let data = try? Data(contentsOf: libraryPath),
          let library = try? JSONDecoder().decode([String].self, from: data) else {
        return []
    }
    return library
}

func saveLibrary(_ library: [String]) {
    ensureConfigDir()
    if let data = try? JSONEncoder().encode(library) {
        try? data.write(to: libraryPath)
    }
}

// ============================================================
// Encoding Detection
// ============================================================

func detectEncoding(for url: URL) -> (encoding: String.Encoding, name: String) {
    guard let data = try? Data(contentsOf: url) else {
        return (.utf8, "UTF-8")
    }
    
    // Try UTF-8 first
    if String(data: data, encoding: .utf8) != nil {
        return (.utf8, "UTF-8")
    }
    
    // Try each encoding
    for (name, encoding) in supportedEncodings {
        if let decoded = String(data: data, encoding: encoding) {
            // Basic validation: check for replacement characters
            if !decoded.contains("\u{FFFD}") {
                return (encoding, name)
            }
        }
    }
    
    return (.utf8, "UTF-8")
}

func readFile(at url: URL, encoding: String.Encoding? = nil) -> (text: String, encoding: String.Encoding, encodingName: String) {
    guard let data = try? Data(contentsOf: url) else {
        return ("", .utf8, "UTF-8")
    }
    
    let (detectedEncoding, encodingName) = detectEncoding(for: url)
    let useEncoding = encoding ?? detectedEncoding
    let useName = encoding != nil ? supportedEncodings.first { $0.encoding == encoding }?.name ?? "Unknown" : encodingName
    
    if let text = String(data: data, encoding: useEncoding) {
        return (text, useEncoding, useName)
    }
    
    // Fallback with lossy conversion
    let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    return (text, .utf8, "UTF-8")
}

// ============================================================
// App Delegate
// ============================================================

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainController: ReaderController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        mainController = ReaderController()
        mainController?.showWindow()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// ============================================================
// Custom Window (handles keyboard)
// ============================================================

class KeyWindow: NSWindow {
    weak var controller: ReaderController?
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: // Left arrow
            controller?.prevPage(nil)
        case 124: // Right arrow
            controller?.nextPage(nil)
        default:
            super.keyDown(with: event)
        }
    }
}

// ============================================================
// Drop Table View
// ============================================================

class DropTableView: NSTableView {
    weak var controller: ReaderController?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        allowsMultipleSelection = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
        allowsMultipleSelection = true
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        
        for url in items {
            controller?.addPathToLibrary(url.path)
        }
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 0 && event.modifierFlags.contains(.command) {
            selectAll(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

// ============================================================
// Main Controller
// ============================================================

class ReaderController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var config: AppConfig
    var library: [String]
    
    var window: KeyWindow!
    var textView: NSTextView!
    var libraryTable: DropTableView!
    var pageLabel: NSTextField!
    var encodingDropdown: NSPopUpButton!
    var fontDropdown: NSPopUpButton!
    
    var currentFile: URL?
    var currentEncoding: String.Encoding = .utf8
    var currentEncodingName: String = "UTF-8"
    var currentText: String = ""
    var pages: [String] = []
    var currentPage: Int = 0
    
    var appearanceObserver: NSKeyValueObservation?
    var darkModeButton: NSButton!
    var isDarkModeEnabled: Bool = false
    
    override init() {
        config = loadConfig()
        library = loadLibrary()
        super.init()
    }
    
    func showWindow() {
        buildWindow()
        buildMenu()
        refreshLibraryTable()
        setupAppearanceObserver()
        applyAppearance()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func setupAppearanceObserver() {
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.applyAppearance()
        }
    }
    
    func applyAppearance() {
        if config.followSystemAppearance {
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            isDarkModeEnabled = isDark
        }
        
        updateDarkModeButton()
        applyColors()
    }
    
    func applyColors() {
        if isDarkModeEnabled {
            textView.backgroundColor = NSColor(white: 0.15, alpha: 1.0)
            textView.textColor = NSColor(white: 0.9, alpha: 1.0)
            libraryTable.backgroundColor = NSColor(white: 0.18, alpha: 1.0)
        } else {
            textView.backgroundColor = NSColor.textBackgroundColor
            textView.textColor = NSColor.textColor
            libraryTable.backgroundColor = NSColor.controlBackgroundColor
        }
        
        displayCurrentPage()
    }
    
    func updateDarkModeButton() {
        darkModeButton.title = isDarkModeEnabled ? "☀ Light" : "🌙 Dark"
        darkModeButton.state = isDarkModeEnabled ? .on : .off
    }
    
    @objc func toggleDarkMode(_ sender: NSButton) {
        isDarkModeEnabled.toggle()
        
        if config.followSystemAppearance {
            config.followSystemAppearance = false
            saveConfig(config)
            if let menu = NSApp.mainMenu?.item(withTitle: "View")?.submenu?.item(withTitle: "Follow System Appearance") {
                menu.state = .off
            }
        }
        
        updateDarkModeButton()
        applyColors()
    }
    
    // MARK: - Window Building
    
    func buildWindow() {
        let contentRect = NSRect(x: 100, y: 100, width: config.windowWidth, height: config.windowHeight)
        window = KeyWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.controller = self
        window.title = "Polyglot Reader"
        window.minSize = NSSize(width: 960, height: 600)
        window.backgroundColor = .windowBackgroundColor
        
        guard let content = window.contentView else { return }
        let frame = content.frame
        
        // Toolbar Container
        let toolbarHeight: CGFloat = 45
        let toolbarContainer = NSView(frame: NSRect(x: 0, y: frame.height - toolbarHeight, width: frame.width, height: toolbarHeight))
        toolbarContainer.autoresizingMask = [.width, .minYMargin]
        
        let openBtn = NSButton(frame: NSRect(x: 10, y: 7, width: 80, height: 30))
        openBtn.title = "Open"
        openBtn.bezelStyle = .rounded
        openBtn.target = self
        openBtn.action = #selector(openFile(_:))
        toolbarContainer.addSubview(openBtn)
        
        let openFolderBtn = NSButton(frame: NSRect(x: 95, y: 7, width: 100, height: 30))
        openFolderBtn.title = "Open Folder"
        openFolderBtn.bezelStyle = .rounded
        openFolderBtn.target = self
        openFolderBtn.action = #selector(openFolder(_:))
        toolbarContainer.addSubview(openFolderBtn)
        
        let encodingLabel = NSTextField(labelWithString: "Encoding:")
        encodingLabel.frame = NSRect(x: 205, y: 12, width: 70, height: 20)
        toolbarContainer.addSubview(encodingLabel)
        
        encodingDropdown = NSPopUpButton(frame: NSRect(x: 275, y: 7, width: 120, height: 30), pullsDown: false)
        for (name, _) in supportedEncodings {
            encodingDropdown.addItem(withTitle: name)
        }
        encodingDropdown.target = self
        encodingDropdown.action = #selector(encodingChanged(_:))
        toolbarContainer.addSubview(encodingDropdown)
        
        let fontLabel = NSTextField(labelWithString: "Font:")
        fontLabel.frame = NSRect(x: 405, y: 12, width: 40, height: 20)
        toolbarContainer.addSubview(fontLabel)
        
        fontDropdown = NSPopUpButton(frame: NSRect(x: 445, y: 7, width: 150, height: 30), pullsDown: false)
        let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
        for family in fontFamilies {
            fontDropdown.addItem(withTitle: family)
        }
        let idx = fontDropdown.indexOfItem(withTitle: config.fontName)
        if idx != NSNotFound {
            fontDropdown.selectItem(at: idx)
        }
        fontDropdown.target = self
        fontDropdown.action = #selector(fontChanged(_:))
        toolbarContainer.addSubview(fontDropdown)
        
        let smallerBtn = NSButton(frame: NSRect(x: 605, y: 7, width: 30, height: 30))
        smallerBtn.title = "-"
        smallerBtn.bezelStyle = .rounded
        smallerBtn.target = self
        smallerBtn.action = #selector(decreaseFont(_:))
        toolbarContainer.addSubview(smallerBtn)
        
        let biggerBtn = NSButton(frame: NSRect(x: 640, y: 7, width: 30, height: 30))
        biggerBtn.title = "+"
        biggerBtn.bezelStyle = .rounded
        biggerBtn.target = self
        biggerBtn.action = #selector(increaseFont(_:))
        toolbarContainer.addSubview(biggerBtn)
        
        // Dark Mode Toggle
        darkModeButton = NSButton(frame: NSRect(x: 690, y: 7, width: 100, height: 30))
        darkModeButton.setButtonType(.pushOnPushOff)
        darkModeButton.bezelStyle = .rounded
        darkModeButton.target = self
        darkModeButton.action = #selector(toggleDarkMode(_:))
        toolbarContainer.addSubview(darkModeButton)
        updateDarkModeButton()
        
        content.addSubview(toolbarContainer)
        
        // Split View
        let splitHeight = frame.height - 90
        let splitView = NSSplitView(frame: NSRect(x: 0, y: 50, width: frame.width, height: splitHeight))
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        
        // Library Panel
        let libraryWidth: CGFloat = 250
        let libraryView = NSView(frame: NSRect(x: 0, y: 0, width: libraryWidth, height: splitHeight))
        libraryView.autoresizingMask = [.height]
        
        let libLabel = NSTextField(labelWithString: "Library")
        libLabel.frame = NSRect(x: 10, y: splitHeight - 30, width: 100, height: 20)
        libLabel.autoresizingMask = [.minYMargin]
        libraryView.addSubview(libLabel)
        
        let removeBtn = NSButton(frame: NSRect(x: libraryWidth - 80, y: splitHeight - 35, width: 70, height: 25))
        removeBtn.title = "Remove"
        removeBtn.bezelStyle = .rounded
        removeBtn.target = self
        removeBtn.action = #selector(removeFromLibrary(_:))
        removeBtn.autoresizingMask = [.minYMargin]
        libraryView.addSubview(removeBtn)
        
        let tableScroll = NSScrollView(frame: NSRect(x: 5, y: 5, width: libraryWidth - 10, height: splitHeight - 45))
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder
        tableScroll.autoresizingMask = [.width, .height]
        
        libraryTable = DropTableView(frame: tableScroll.contentView.bounds)
        libraryTable.controller = self
        libraryTable.headerView = nil
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("filename"))
        column.width = libraryWidth - 30
        libraryTable.addTableColumn(column)
        
        libraryTable.dataSource = self
        libraryTable.delegate = self
        libraryTable.target = self
        libraryTable.doubleAction = #selector(libraryItemSelected(_:))
        libraryTable.action = #selector(libraryItemSelected(_:))
        
        tableScroll.documentView = libraryTable
        libraryView.addSubview(tableScroll)
        splitView.addSubview(libraryView)
        
        // Reader Panel
        let readerWidth = frame.width - libraryWidth
        let readerView = NSView(frame: NSRect(x: 0, y: 0, width: readerWidth, height: splitHeight))
        readerView.autoresizingMask = [.width, .height]
        
        let textScroll = NSScrollView(frame: NSRect(x: 5, y: 5, width: readerWidth - 10, height: splitHeight - 10))
        textScroll.hasVerticalScroller = true
        textScroll.borderType = .bezelBorder
        textScroll.autoresizingMask = [.width, .height]
        
        textView = NSTextView(frame: textScroll.contentView.bounds)
        textView.isEditable = false
        textView.isRichText = false
        textView.autoresizingMask = [.width]
        
        if let font = NSFont(name: config.fontName, size: config.fontSize) {
            textView.font = font
        }
        
        textScroll.documentView = textView
        readerView.addSubview(textScroll)
        splitView.addSubview(readerView)
        content.addSubview(splitView)
        
        // Page Navigation Container 
        let navHeight: CGFloat = 50
        let navContainer = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: navHeight))
        navContainer.autoresizingMask = [.width, .maxYMargin]
        
        let prevBtn = NSButton(frame: NSRect(x: navContainer.frame.width/2 - 120, y: 10, width: 80, height: 30))
        prevBtn.title = "← Prev"
        prevBtn.bezelStyle = .rounded
        prevBtn.target = self
        prevBtn.action = #selector(prevPage(_:))
        prevBtn.autoresizingMask = [.minXMargin, .maxXMargin]
        navContainer.addSubview(prevBtn)
        
        pageLabel = NSTextField(labelWithString: "Page 0 / 0")
        pageLabel.frame = NSRect(x: navContainer.frame.width/2 - 30, y: 15, width: 100, height: 20)
        pageLabel.autoresizingMask = [.minXMargin, .maxXMargin]
        navContainer.addSubview(pageLabel)
        
        let nextBtn = NSButton(frame: NSRect(x: navContainer.frame.width/2 + 70, y: 10, width: 80, height: 30))
        nextBtn.title = "Next →"
        nextBtn.bezelStyle = .rounded
        nextBtn.target = self
        nextBtn.action = #selector(nextPage(_:))
        nextBtn.autoresizingMask = [.minXMargin, .maxXMargin]
        navContainer.addSubview(nextBtn)
        
        content.addSubview(navContainer)
    }
    
    func buildMenu() {
        let menuBar = NSMenu()
        
        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        menuBar.addItem(appMenuItem)
        
        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        
        let openItem = NSMenuItem(title: "Open...", action: #selector(openFile(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        
        let openFolderItem = NSMenuItem(title: "Open Folder...", action: #selector(openFolder(_:)), keyEquivalent: "O")
        openFolderItem.target = self
        fileMenu.addItem(openFolderItem)
        
        fileMenu.addItem(.separator())
        
        let clearItem = NSMenuItem(title: "Clear Library", action: #selector(clearLibrary(_:)), keyEquivalent: "")
        clearItem.target = self
        fileMenu.addItem(clearItem)
        
        fileMenuItem.submenu = fileMenu
        menuBar.addItem(fileMenuItem)
        
        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        menuBar.addItem(editMenuItem)
        
        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        
        let darkModeItem = NSMenuItem(title: "Follow System Appearance", action: #selector(toggleFollowSystemAppearance(_:)), keyEquivalent: "")
        darkModeItem.target = self
        darkModeItem.state = config.followSystemAppearance ? .on : .off
        viewMenu.addItem(darkModeItem)
        
        viewMenuItem.submenu = viewMenu
        menuBar.addItem(viewMenuItem)
        
        NSApp.mainMenu = menuBar
    }
    
    // MARK: - Actions
    
    @objc func openFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open Text File"
        panel.allowedContentTypes = [.plainText, .sourceCode, .xml, .html, .json, .yaml]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            loadFile(url)
        }
    }
    
    @objc func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            addTxtFilesFromFolder(url)
        }
    }
    
    func addTxtFilesFromFolder(_ folderURL: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            return
        }
        
        var addedCount = 0
        for url in contents {
            if url.hasDirectoryPath { continue }
            let ext = url.pathExtension.lowercased()
            if textExtensions.contains(ext) {
                let path = url.path
                if !library.contains(path) {
                    library.append(path)
                    addedCount += 1
                }
            }
        }
        
        if addedCount > 0 {
            saveLibrary(library)
            refreshLibraryTable()
        }
    }
    
    func addPathToLibrary(_ path: String) {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }
        
        if isDir.boolValue {
            addTxtFilesFromFolder(url)
        } else {
            let ext = url.pathExtension.lowercased()
            if textExtensions.contains(ext) {
                if !library.contains(path) {
                    library.append(path)
                    saveLibrary(library)
                    refreshLibraryTable()
                }
                loadFile(url)
            }
        }
    }
    
    func loadFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        currentFile = url
        let result = readFile(at: url)
        currentText = result.text
        currentEncoding = result.encoding
        currentEncodingName = result.encodingName
        
        updateEncodingDropdown()
        
        let path = url.path
        if !library.contains(path) {
            library.append(path)
            saveLibrary(library)
            refreshLibraryTable()
        }
        
        paginateText()
        currentPage = 0
        displayCurrentPage()
        updatePageLabel()
        updateWindowTitle()
    }
    
    func updateEncodingDropdown() {
        for (index, (name, _)) in supportedEncodings.enumerated() {
            if name == currentEncodingName {
                encodingDropdown.selectItem(at: index)
                return
            }
        }
        encodingDropdown.selectItem(at: 0)
    }
    
    @objc func encodingChanged(_ sender: Any?) {
        guard let currentFile = currentFile else { return }
        
        let idx = encodingDropdown.indexOfSelectedItem
        let (name, encoding) = supportedEncodings[idx]
        
        let result = readFile(at: currentFile, encoding: encoding)
        currentText = result.text
        currentEncoding = encoding
        currentEncodingName = name
        
        paginateText()
        currentPage = 0
        displayCurrentPage()
        updatePageLabel()
        updateWindowTitle()
    }
    
    func paginateText() {
        let lines = currentText.components(separatedBy: "\n")
        let linesPerPage = config.linesPerPage
        
        pages = []
        for i in stride(from: 0, to: lines.count, by: linesPerPage) {
            let end = min(i + linesPerPage, lines.count)
            let pageLines = Array(lines[i..<end])
            pages.append(pageLines.joined(separator: "\n"))
        }
        
        if pages.isEmpty {
            pages = [""]
        }
    }
    
    func displayCurrentPage() {
        if currentPage >= 0 && currentPage < pages.count {
            textView.string = pages[currentPage]
            textView.textColor = isDarkModeEnabled ? NSColor(white: 0.9, alpha: 1.0) : NSColor.textColor
        }
    }
    
    func updatePageLabel() {
        let total = pages.count
        let current = currentPage + 1
        pageLabel.stringValue = "Page \(current) / \(total)"
    }
    
    func updateWindowTitle() {
        if let file = currentFile {
            let name = file.lastPathComponent
            window.title = "Polyglot Reader - \(name) [\(currentEncodingName)]"
        } else {
            window.title = "Polyglot Reader"
        }
    }
    
    @objc func prevPage(_ sender: Any?) {
        if currentPage > 0 {
            currentPage -= 1
            displayCurrentPage()
            updatePageLabel()
        }
    }
    
    @objc func nextPage(_ sender: Any?) {
        if currentPage < pages.count - 1 {
            currentPage += 1
            displayCurrentPage()
            updatePageLabel()
        }
    }
    
    @objc func increaseFont(_ sender: Any?) {
        config.fontSize = min(72, config.fontSize + 2)
        applyFont()
        saveConfig(config)
    }
    
    @objc func decreaseFont(_ sender: Any?) {
        config.fontSize = max(8, config.fontSize - 2)
        applyFont()
        saveConfig(config)
    }
    
    @objc func fontChanged(_ sender: Any?) {
        let idx = fontDropdown.indexOfSelectedItem
        if let title = fontDropdown.item(at: idx)?.title {
            config.fontName = title
            applyFont()
            saveConfig(config)
        }
    }
    
    func applyFont() {
        if let font = NSFont(name: config.fontName, size: config.fontSize) {
            textView.font = font
        }
    }
    
    @objc func toggleFollowSystemAppearance(_ sender: NSMenuItem) {
        config.followSystemAppearance.toggle()
        sender.state = config.followSystemAppearance ? .on : .off
        saveConfig(config)
        applyAppearance()
    }
    
    @objc func libraryItemSelected(_ sender: Any?) {
        let row = libraryTable.selectedRow
        if row >= 0 && row < library.count {
            let path = library[row]
            loadFile(URL(fileURLWithPath: path))
        }
    }
    
    @objc func removeFromLibrary(_ sender: Any?) {
        let selected = libraryTable.selectedRowIndexes
        if selected.isEmpty { return }
        
        let indices = selected.sorted().reversed()
        for idx in indices {
            if idx >= 0 && idx < library.count {
                library.remove(at: idx)
            }
        }
        
        saveLibrary(library)
        refreshLibraryTable()
    }
    
    @objc func clearLibrary(_ sender: Any?) {
        library = []
        saveLibrary(library)
        refreshLibraryTable()
        currentFile = nil
        currentText = ""
        pages = []
        currentPage = 0
        textView.string = ""
        updatePageLabel()
        window.title = "Polyglot Reader"
    }
    
    func refreshLibraryTable() {
        libraryTable.reloadData()
    }
    
    // MARK: - NSTableViewDataSource
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return library.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if row >= 0 && row < library.count {
            return URL(fileURLWithPath: library[row]).lastPathComponent
        }
        return nil
    }
}

// ============================================================
// Main
// ============================================================

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
