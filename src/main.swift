import AppKit
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

// This mode runs out of process, so a difficult PDF cannot block the UI.
func renderCheck(_ input: String, _ directory: String) -> Int32 {
    guard let document = CGPDFDocument(URL(fileURLWithPath: input) as CFURL) else { return 2 }
    do {
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
    } catch { return 3 }
    for index in 1...document.numberOfPages {
        let ok: Bool = autoreleasepool {
            guard let page = document.page(at: index) else { return false }
            let box = page.getBoxRect(.cropBox)
            let rotated = abs(page.rotationAngle) % 180 == 90
            let w = rotated ? box.height : box.width
            let h = rotated ? box.width : box.height
            let scale = min(1.0, 1200 / max(w, h))
            let width = max(1, Int(ceil(w * scale)))
            let height = max(1, Int(ceil(h * scale)))
            guard
                let context = CGContext(
                    data: nil, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            let target = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(target)
            context.concatenate(
                page.getDrawingTransform(
                    .cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            guard let image = context.makeImage() else { return false }
            let path = URL(fileURLWithPath: directory).appendingPathComponent("page-\(index).png")
            guard
                let destination = CGImageDestinationCreateWithURL(
                    path as CFURL, "public.png" as CFString, 1, nil)
            else { return false }
            CGImageDestinationAddImage(destination, image, nil)
            return CGImageDestinationFinalize(destination)
        }
        if !ok { return 4 }
    }
    return 0
}

if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--render-check" {
    exit(renderCheck(CommandLine.arguments[2], CommandLine.arguments[3]))
}

if CommandLine.arguments.contains("--localization-self-test") {
    let cases: [(String, [String], String)] = [
        ("system", ["de-DE", "en-US"], "de"), ("system", ["it-IT", "fr-FR"], "fr"),
        ("system", ["ru_RU"], "ru"), ("system", ["es-MX"], "es"),
        ("system", ["ja-JP"], "ja"), ("system", ["zh-Hant-TW"], "zh-Hans"),
        ("system", ["pt-BR"], "en"), ("en", ["ru-RU"], "en"),
        ("unknown", ["de-DE"], "de"), ("system", [], "en"),
    ]
    for (preference, languages, expected) in cases {
        guard Localization.resolve(preference: preference, languages: languages) == expected else {
            exit(1)
        }
    }
    guard Localization.shared.parseTarget("9,5") == 9.5,
        Localization.shared.parseTarget("9.5") == 9.5,
        Localization.shared.parseTarget("1,000.5") == nil
    else { exit(2) }
    print("Locale matching and decimal input: passed")
    exit(0)
}

let ink = NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.19, alpha: 1)
let muted = NSColor(calibratedRed: 0.43, green: 0.46, blue: 0.49, alpha: 1)
let accent = NSColor(calibratedRed: 0.28, green: 0.31, blue: 0.85, alpha: 1)
let cream = NSColor(calibratedRed: 0.965, green: 0.961, blue: 0.949, alpha: 1)
let lineColor = NSColor(calibratedRed: 0.86, green: 0.87, blue: 0.85, alpha: 1)

func label(
    _ text: String, _ size: CGFloat = 13, _ weight: NSFont.Weight = .regular,
    _ color: NSColor = ink
) -> NSTextField {
    let view = NSTextField(labelWithString: text)
    view.font = .systemFont(ofSize: size, weight: weight)
    view.textColor = color
    view.maximumNumberOfLines = 0
    view.lineBreakMode = .byWordWrapping
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}

func stack(_ views: [NSView], vertical: Bool = true, spacing: CGFloat = 12) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = vertical ? .vertical : .horizontal
    s.alignment = vertical ? .leading : .centerY
    s.spacing = spacing
    s.translatesAutoresizingMaskIntoConstraints = false
    return s
}

final class Panel: NSView {
    init(_ color: NSColor, radius: CGFloat = 16) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = radius
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class DropZone: NSView {
    var onDrop: ((URL) -> Void)?
    var onClick: (() -> Void)?
    var enabled = true
    private var hover = false
    let title = localizedLabel("drop.title", 14, .semibold)
    let subtitle = localizedLabel("drop.subtitle", 11, .regular, muted)
    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        registerForDraggedTypes([.fileURL])
        let symbol = NSImageView(
            image: NSImage(systemSymbolName: "doc.badge.arrow.up", accessibilityDescription: nil)!)
        symbol.contentTintColor = accent
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 29, weight: .regular)
        let content = stack([symbol, title, subtitle], spacing: 7)
        content.alignment = .centerX
        addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            heightAnchor.constraint(equalToConstant: 128),
        ])
        setAccessibilityElement(true)
        setAccessibilityLabel(tr("drop.accessibility"))
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
        (hover ? accent.withAlphaComponent(0.06) : NSColor.white.withAlphaComponent(0.6)).setFill()
        path.fill()
        (hover ? accent : lineColor).setStroke()
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        path.stroke()
    }
    override func mouseDown(with event: NSEvent) { if enabled { onClick?() } }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard enabled, fileURL(sender) != nil else { return [] }
        hover = true
        needsDisplay = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        hover = false
        needsDisplay = true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hover = false
        needsDisplay = true
        guard enabled, let url = fileURL(sender) else { return false }
        onDrop?(url)
        return true
    }
    private func fileURL(_ sender: NSDraggingInfo) -> URL? {
        guard
            let urls = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        else { return nil }
        return urls.first { $0.pathExtension.lowercased() == "pdf" }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var process: Process?
    var input: URL?
    var resultURL: URL?
    var savedURL: URL?
    var result: [String: Any]?
    var jobDirectory: URL?
    var pendingFile: URL?
    var busy = false
    var lastProgress: [String: Any]?
    var lastError: (String, [String: String])?
    var wasCancelled = false
    let drop = DropZone(frame: .zero)
    let fileName = localizedLabel("file.none", 13, .medium)
    let fileInfo = localizedLabel("file.local", 11, .regular, muted)
    let target = NSTextField(string: "9")
    let mode = NSPopUpButton()
    let modeDescription = localizedLabel("mode.balanced.description", 11, .regular, muted)
    let repair = localizedButton("repair.title", checkbox: true)
    let optimizeButton = localizedButton("action.optimize")
    let saveButton = localizedButton("action.save")
    let revealButton = localizedButton("action.reveal")
    let status = localizedLabel("status.ready", 12, .medium)
    let detail = localizedLabel("detail.original_safe", 11, .regular, muted)
    let spinner = NSProgressIndicator()
    let cancel = localizedButton("action.cancel")
    let preview = PDFView()
    let emptyView = Panel(NSColor.clear)
    let previewTitle = localizedLabel("preview.title", 13, .medium)
    let pageCounter = label("", 11, .regular, muted)
    let beforeAfter = NSSegmentedControl(
        labels: [tr("preview.original"), tr("preview.result")], trackingMode: .selectOne,
        target: nil,
        action: nil)
    let sizeLabel = label("—", 26, .semibold)
    let savingsLabel = localizedLabel("metrics.choose", 11, .regular, muted)
    let checksLabel = localizedLabel("checks.intro", 11, .regular, muted)
    let previousPage = NSButton()
    let nextPage = NSButton()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        setupWindow()
        if let file = pendingFile { load(file) }
        if let index = CommandLine.arguments.firstIndex(of: "--open"),
            CommandLine.arguments.count > index + 1
        {
            load(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
    }

    func setupMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        bar.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: tr("menu.about"), action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: tr("menu.quit"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        let fileItem = NSMenuItem()
        bar.addItem(fileItem)
        let fileMenu = NSMenu(title: tr("menu.file"))
        fileItem.submenu = fileMenu
        fileMenu.addItem(
            withTitle: tr("menu.open"), action: #selector(chooseFile), keyEquivalent: "o")
        fileMenu.addItem(withTitle: tr("action.save"), action: #selector(save), keyEquivalent: "s")
        let editItem = NSMenuItem()
        bar.addItem(editItem)
        let edit = NSMenu(title: tr("menu.edit"))
        editItem.submenu = edit
        edit.addItem(
            withTitle: tr("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(
            withTitle: tr("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(
            withTitle: tr("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
            withTitle: tr("menu.select_all"), action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a")
        let languageItem = NSMenuItem()
        bar.addItem(languageItem)
        let languages = NSMenu(title: tr("menu.language"))
        languageItem.submenu = languages
        for code in ["system"] + Localization.supported {
            let item = NSMenuItem(
                title: code == "system" ? tr("language.system") : Localization.names[code]!,
                action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = Localization.shared.preference == code ? .on : .off
            languages.addItem(item)
            if code == "system" { languages.addItem(.separator()) }
        }
        NSApp.mainMenu = bar
    }

    @objc func changeLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        let selectedMode = mode.indexOfSelectedItem
        let previewSegment = beforeAfter.selectedSegment
        Localization.shared.select(code)
        setupMenu()
        mode.removeAllItems()
        mode.addItems(withTitles: [tr("mode.lossless"), tr("mode.balanced"), tr("mode.compact")])
        mode.selectItem(at: selectedMode)
        modeChanged()
        mode.setAccessibilityLabel(tr("mode.accessibility"))
        target.setAccessibilityLabel(tr("target.accessibility"))
        drop.setAccessibilityLabel(tr("drop.accessibility"))
        repair.toolTip = tr("repair.tooltip")
        beforeAfter.setLabel(tr("preview.original"), forSegment: 0)
        beforeAfter.setLabel(tr("preview.result"), forSegment: 1)
        previousPage.setAccessibilityLabel(tr("preview.previous"))
        nextPage.setAccessibilityLabel(tr("preview.next"))
        if let file = input {
            fileName.stringValue = file.lastPathComponent
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            fileInfo.stringValue = tr(
                "file.info",
                ["size": formatBytes(size), "count": String(preview.document?.pageCount ?? 0)])
            sizeLabel.stringValue = formatBytes(size)
            savingsLabel.stringValue = tr("metrics.original")
            checksLabel.stringValue = tr("checks.pending")
            status.stringValue = tr("status.loaded")
        }
        if let event = result {
            handle(event)
            beforeAfter.selectedSegment = previewSegment
            switchPreview()
        }
        if let saved = savedURL {
            status.stringValue = tr("status.saved")
            detail.stringValue = saved.lastPathComponent
        }
        if wasCancelled {
            status.stringValue = tr("status.cancelled")
            detail.stringValue = tr("detail.original_safe")
        }
        if busy {
            if let event = lastProgress {
                handle(event)
            } else {
                status.stringValue = tr("status.checking")
            }
            detail.stringValue = tr("detail.background")
        }
        if let error = lastError { showLocalizedError(error.0, error.1) }
    }

    func setupWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
            defer: false)
        window.title = "PDF Light"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = cream
        window.minSize = NSSize(width: 1000, height: 780)
        window.delegate = self
        window.appearance = NSAppearance(named: .aqua)
        guard let root = window.contentView else { return }
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 370),
        ])
        let brand = label("PDF Light", 29, .semibold)
        let sub = localizedLabel("app.tagline", 12, .regular, muted)
        let heading = stack([brand, sub], spacing: 4)
        fileName.lineBreakMode = .byTruncatingMiddle
        fileName.maximumNumberOfLines = 1
        fileInfo.maximumNumberOfLines = 2
        let fileStack = stack([fileName, fileInfo], spacing: 4)
        target.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        target.alignment = .center
        target.focusRingType = .none
        target.translatesAutoresizingMaskIntoConstraints = false
        target.widthAnchor.constraint(equalToConstant: 70).isActive = true
        target.heightAnchor.constraint(equalToConstant: 31).isActive = true
        target.setAccessibilityLabel(tr("target.accessibility"))
        let targetRow = stack(
            [
                localizedLabel("target.label", 13, .medium), target,
                localizedLabel("unit.mb", 13, .regular, muted),
            ], vertical: false, spacing: 10)
        mode.addItems(withTitles: [tr("mode.lossless"), tr("mode.balanced"), tr("mode.compact")])
        mode.selectItem(at: 1)
        mode.target = self
        mode.action = #selector(modeChanged)
        mode.controlSize = .large
        mode.translatesAutoresizingMaskIntoConstraints = false
        mode.setAccessibilityLabel(tr("mode.accessibility"))
        repair.state = .on
        repair.font = .systemFont(ofSize: 11)
        repair.toolTip = tr("repair.tooltip")
        let settings = stack([targetRow, mode, modeDescription, repair], spacing: 10)
        mode.widthAnchor.constraint(equalTo: settings.widthAnchor).isActive = true
        modeDescription.widthAnchor.constraint(equalTo: settings.widthAnchor).isActive = true
        optimizeButton.bezelStyle = .rounded
        optimizeButton.controlSize = .large
        optimizeButton.contentTintColor = .white
        optimizeButton.bezelColor = accent
        optimizeButton.font = .systemFont(ofSize: 14, weight: .semibold)
        optimizeButton.target = self
        optimizeButton.action = #selector(optimize)
        optimizeButton.keyEquivalent = "\r"
        optimizeButton.isEnabled = false
        optimizeButton.translatesAutoresizingMaskIntoConstraints = false
        optimizeButton.heightAnchor.constraint(equalToConstant: 42).isActive = true
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        cancel.bezelStyle = .inline
        cancel.font = .systemFont(ofSize: 11)
        cancel.target = self
        cancel.action = #selector(cancelJob)
        cancel.isHidden = true
        let statusRow = stack([spinner, status, cancel], vertical: false, spacing: 7)
        status.maximumNumberOfLines = 2
        let statusStack = stack([statusRow, detail], spacing: 5)
        let left = stack(
            [heading, drop, fileStack, settings, optimizeButton, statusStack], spacing: 20)
        sidebar.addSubview(left)
        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 24),
            left.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 26),
            left.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -26),
            drop.widthAnchor.constraint(equalTo: left.widthAnchor),
            fileStack.widthAnchor.constraint(equalTo: left.widthAnchor),
            fileName.widthAnchor.constraint(equalTo: left.widthAnchor),
            settings.widthAnchor.constraint(equalTo: left.widthAnchor),
            optimizeButton.widthAnchor.constraint(equalTo: left.widthAnchor),
            statusStack.widthAnchor.constraint(equalTo: left.widthAnchor),
            statusRow.widthAnchor.constraint(equalTo: left.widthAnchor),
            detail.widthAnchor.constraint(equalTo: left.widthAnchor),
        ])
        let local = localizedLabel("footer.local", 10, .medium, muted)
        sidebar.addSubview(local)
        NSLayoutConstraint.activate([
            local.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            local.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -22),
        ])
        let main = Panel(.white, radius: 18)
        root.addSubview(main)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            main.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            main.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            main.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
        ])
        beforeAfter.target = self
        beforeAfter.action = #selector(switchPreview)
        beforeAfter.selectedSegment = 0
        beforeAfter.setEnabled(false, forSegment: 1)
        beforeAfter.controlSize = .small
        let head = stack([previewTitle, beforeAfter], vertical: false, spacing: 16)
        main.addSubview(head)
        NSLayoutConstraint.activate([
            head.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 22),
            head.topAnchor.constraint(equalTo: main.topAnchor, constant: 18),
        ])
        let canvas = Panel(NSColor(calibratedWhite: 0.945, alpha: 1), radius: 10)
        main.addSubview(canvas)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.autoScales = true
        preview.displayMode = .singlePage
        preview.displayBox = .cropBox
        preview.backgroundColor = NSColor(calibratedWhite: 0.945, alpha: 1)
        canvas.addSubview(preview)
        canvas.addSubview(emptyView)
        let emptyIcon = NSImageView(
            image: NSImage(
                systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)!)
        emptyIcon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 48, weight: .ultraLight)
        emptyIcon.contentTintColor = muted.withAlphaComponent(0.5)
        let emptyTitle = localizedLabel("preview.empty_title", 21, .medium)
        let emptySub = localizedLabel("preview.empty_detail", 12, .regular, muted)
        let emptyStack = stack([emptyIcon, emptyTitle, emptySub], spacing: 14)
        emptyStack.alignment = .centerX
        emptyView.addSubview(emptyStack)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 18),
            canvas.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -18),
            canvas.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 16),
            canvas.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -200),
            preview.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 10),
            preview.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -10),
            preview.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 10),
            preview.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -10),
            emptyView.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            emptyView.topAnchor.constraint(equalTo: canvas.topAnchor),
            emptyView.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            emptyStack.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor),
        ])
        previousPage.image = NSImage(
            systemSymbolName: "chevron.left", accessibilityDescription: tr("preview.previous"))
        nextPage.image = NSImage(
            systemSymbolName: "chevron.right", accessibilityDescription: tr("preview.next"))
        for button in [previousPage, nextPage] {
            button.bezelStyle = .inline
            button.target = self
        }
        previousPage.action = #selector(previous)
        nextPage.action = #selector(next)
        let nav = stack([previousPage, pageCounter, nextPage], vertical: false, spacing: 12)
        main.addSubview(nav)
        NSLayoutConstraint.activate([
            nav.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            nav.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 8),
        ])
        let metrics = stack([sizeLabel, savingsLabel, checksLabel], spacing: 5)
        main.addSubview(metrics)
        NSLayoutConstraint.activate([
            metrics.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 24),
            metrics.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -24),
            metrics.topAnchor.constraint(equalTo: nav.bottomAnchor, constant: 9),
            checksLabel.widthAnchor.constraint(equalTo: metrics.widthAnchor),
        ])
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .large
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.isEnabled = false
        revealButton.bezelStyle = .inline
        revealButton.target = self
        revealButton.action = #selector(reveal)
        revealButton.isHidden = true
        let actions = stack([saveButton, revealButton], vertical: false, spacing: 14)
        main.addSubview(actions)
        NSLayoutConstraint.activate([
            actions.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -22),
            actions.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -15),
        ])
        drop.onClick = { [weak self] in self?.chooseFile() }
        drop.onDrop = { [weak self] url in self?.load(url) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: preview)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func chooseFile() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { self.load(url) }
        }
    }

    func load(_ url: URL) {
        guard !busy else { return }
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            showLocalizedError("error.open")
            return
        }
        if document.isLocked {
            showLocalizedError("error.encrypted")
            return
        }
        cleanup()
        lastError = nil
        lastProgress = nil
        wasCancelled = false
        input = url
        result = nil
        resultURL = nil
        savedURL = nil
        fileName.stringValue = url.lastPathComponent
        let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        fileInfo.stringValue = tr(
            "file.info", ["size": formatBytes(size), "count": String(document.pageCount)])
        preview.document = document
        preview.autoScales = true
        emptyView.isHidden = true
        beforeAfter.selectedSegment = 0
        beforeAfter.setEnabled(false, forSegment: 1)
        optimizeButton.isEnabled = true
        saveButton.isEnabled = false
        revealButton.isHidden = true
        sizeLabel.stringValue = formatBytes(size)
        savingsLabel.stringValue = tr("metrics.original")
        checksLabel.stringValue = tr("checks.pending")
        status.stringValue = tr("status.loaded")
        status.textColor = ink
        detail.stringValue = tr("detail.original_safe")
        pageChanged()
    }

    @objc func modeChanged() {
        modeDescription.stringValue =
            [
                tr("mode.lossless.description"),
                tr("mode.balanced.description"),
                tr("mode.compact.description"),
            ][mode.indexOfSelectedItem]
    }

    @objc func optimize() {
        guard !busy, let source = input else { return }
        guard let limit = Localization.shared.parseTarget(target.stringValue), limit.isFinite,
            limit >= 0.1, limit <= 10000
        else {
            showLocalizedError("error.target")
            return
        }
        guard let resources = Bundle.main.resourceURL, let helper = Bundle.main.executableURL else {
            return
        }
        cleanup()
        lastError = nil
        lastProgress = nil
        wasCancelled = false
        result = nil
        resultURL = nil
        savedURL = nil
        saveButton.isEnabled = false
        revealButton.isHidden = true
        beforeAfter.selectedSegment = 0
        beforeAfter.setEnabled(false, forSegment: 1)
        preview.document = PDFDocument(url: source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PDFLight-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        } catch {
            showLocalizedError("error.launch", ["reason": error.localizedDescription])
            return
        }
        jobDirectory = directory
        let destination = directory.appendingPathComponent(
            source.deletingPathExtension().lastPathComponent + " — optimized.pdf")
        let task = Process()
        process = task
        task.executableURL = resources.appendingPathComponent("Python/bin/python3.12")
        task.arguments = [
            "-I", "-B", resources.appendingPathComponent("optimizer.py").path, "--input",
            source.path,
            "--output", destination.path, "--target", String(limit), "--mode",
            ["lossless", "balanced", "compact"][mode.indexOfSelectedItem], "--native-helper",
            helper.path, "--language", Localization.shared.code,
        ]
        if repair.state == .on { task.arguments?.append("--repair") }
        var env = ProcessInfo.processInfo.environment
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env.removeValue(forKey: "PYTHONPATH")
        env.removeValue(forKey: "PYTHONHOME")
        task.environment = env
        let output = Pipe()
        let errors = Pipe()
        task.standardOutput = output
        task.standardError = errors
        // Drain stderr independently to avoid a full pipe blocking the worker.
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        setBusy(true)
        status.stringValue = tr("status.checking")
        detail.stringValue = tr("detail.background")
        do { try task.run() } catch {
            setBusy(false)
            process = nil
            showLocalizedError("error.launch", ["reason": error.localizedDescription])
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var pending = Data()
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    let line = pending[..<newline]
                    pending.removeSubrange(...newline)
                    if let event = try? JSONSerialization.jsonObject(with: Data(line))
                        as? [String: Any]
                    {
                        DispatchQueue.main.async { if self.process === task { self.handle(event) } }
                    }
                }
            }
            task.waitUntilExit()
            errors.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard self.process === task else { return }
                self.process = nil
                self.setBusy(false)
                if self.result == nil && self.status.textColor != NSColor.systemRed {
                    self.showLocalizedError(
                        task.terminationStatus == 15 ? "error.cancelled" : "error.no_result")
                }
            }
        }
    }

    func handle(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "progress":
            lastProgress = event
            let values = (event["values"] as? [String: Any] ?? [:]).mapValues {
                String(describing: $0)
            }
            status.stringValue = tr(event["message_key"] as? String ?? "status.processing", values)
        case "error": showLocalizedError(event["message_key"] as? String ?? "error.generic")
        case "result":
            result = event
            guard let path = event["output"] as? String else { return }
            resultURL = URL(fileURLWithPath: path)
            let old = event["original_bytes"] as? Int ?? 0
            let new = event["output_bytes"] as? Int ?? 0
            let percent = old > 0 ? max(0, 100 * (1 - Double(new) / Double(old))) : 0
            sizeLabel.stringValue = "\(formatBytes(old)) → \(formatBytes(new))"
            let met = event["target_met"] as? Bool ?? false
            savingsLabel.stringValue = tr(
                "metrics.savings",
                [
                    "percent": Localization.shared.number(percent.rounded()),
                    "target": tr(met ? "metrics.met" : "metrics.missed"),
                ])
            savingsLabel.textColor = met ? NSColor.systemGreen : NSColor.systemOrange
            let native = event["native"] as? [String: Any] ?? [:]
            let bad = native["bad_pages"] as? [Int] ?? []
            let checked = native["checked"] as? Bool ?? false
            let maskCount = event["masks"] as? Int ?? 0
            let pages = event["pages"] as? Int ?? 0
            if !bad.isEmpty {
                checksLabel.stringValue = tr(
                    "checks.review", ["pages": bad.map(String.init).joined(separator: ", ")])
                checksLabel.textColor = .systemOrange
                detail.stringValue = tr("detail.render_difference")
            } else if checked {
                checksLabel.stringValue =
                    tr("checks.success", ["count": String(pages)])
                    + (maskCount > 0 ? tr("checks.masks", ["count": String(maskCount)]) : "")
                checksLabel.textColor = muted
                detail.stringValue = met ? tr("detail.save") : tr("detail.target_missed")
            } else {
                checksLabel.stringValue = tr("checks.unavailable")
                checksLabel.textColor = .systemOrange
                detail.stringValue = tr("detail.preview_check")
            }
            status.stringValue = met ? tr("status.done") : tr("status.above_target")
            status.textColor = ink
            beforeAfter.setEnabled(true, forSegment: 1)
            beforeAfter.selectedSegment = 1
            switchPreview()
            saveButton.isEnabled = true
        default: break
        }
    }

    func setBusy(_ value: Bool) {
        busy = value
        optimizeButton.isEnabled = !value && input != nil
        target.isEnabled = !value
        mode.isEnabled = !value
        repair.isEnabled = !value
        drop.enabled = !value
        cancel.isHidden = !value
        if value {
            spinner.startAnimation(nil)
            status.textColor = ink
        } else {
            spinner.stopAnimation(nil)
        }
    }

    @objc func cancelJob() {
        guard let task = process else { return }
        process = nil
        task.terminate()
        setBusy(false)
        wasCancelled = true
        lastError = nil
        status.stringValue = tr("status.cancelled")
        detail.stringValue = tr("detail.original_safe")
        // Delay cleanup until the process has actually stopped writing.
        let directory = jobDirectory
        jobDirectory = nil
        DispatchQueue.global().async {
            task.waitUntilExit()
            if let d = directory { try? FileManager.default.removeItem(at: d) }
        }
    }

    @objc func switchPreview() {
        let page = preview.currentPage.flatMap { preview.document?.index(for: $0) } ?? 0
        guard let url = beforeAfter.selectedSegment == 1 ? resultURL : input else { return }
        preview.document = PDFDocument(url: url)
        preview.autoScales = true
        if let destination = preview.document?.page(at: page) { preview.go(to: destination) }
        pageChanged()
    }
    @objc func pageChanged() {
        guard let doc = preview.document, let page = preview.currentPage else {
            pageCounter.stringValue = ""
            return
        }
        let index = doc.index(for: page)
        pageCounter.stringValue = "\(index+1) / \(doc.pageCount)"
        previousPage.isEnabled = index > 0
        nextPage.isEnabled = index + 1 < doc.pageCount
    }
    @objc func previous() { preview.goToPreviousPage(nil) }
    @objc func next() { preview.goToNextPage(nil) }

    @objc func save() {
        guard !busy, let generated = resultURL, let source = input else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue =
            source.deletingPathExtension().lastPathComponent + " — optimized.pdf"
        panel.directoryURL = source.deletingLastPathComponent()
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            if destination.resolvingSymlinksInPath().standardizedFileURL
                == source.resolvingSymlinksInPath().standardizedFileURL
            {
                self.showLocalizedError("error.overwrite_source")
                return
            }
            do {
                // NSSavePanel has already handled confirmation for an existing destination.
                let bytes = try Data(contentsOf: generated)
                try bytes.write(to: destination, options: .atomic)
                self.savedURL = destination
                self.revealButton.isHidden = false
                self.lastError = nil
                self.status.stringValue = tr("status.saved")
                self.detail.stringValue = destination.lastPathComponent
                self.status.textColor = ink
            } catch {
                self.showLocalizedError("error.save", ["reason": error.localizedDescription])
            }
        }
    }
    @objc func reveal() {
        if let url = savedURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    func formatBytes(_ bytes: Int) -> String {
        Localization.shared.number(Double(bytes) / 1_000_000, decimals: 2) + " " + tr("unit.mb")
    }
    func showLocalizedError(_ key: String, _ values: [String: String] = [:]) {
        lastError = (key, values)
        status.stringValue = tr("status.failed")
        status.textColor = .systemRed
        detail.stringValue = tr(key, values)
    }
    @objc func about() {
        let alert = NSAlert()
        alert.messageText = "PDF Light 1.1.0"
        alert.informativeText = tr("about.description")
        alert.runModal()
    }
    func cleanup() {
        if let directory = jobDirectory { try? FileManager.default.removeItem(at: directory) }
        jobDirectory = nil
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let name = filenames.first {
            let url = URL(fileURLWithPath: name)
            if window == nil { pendingFile = url } else { load(url) }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        process?.terminate()
        cleanup()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
