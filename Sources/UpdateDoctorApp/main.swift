import AppKit
import ServiceManagement
import UpdateDoctorKit
import UpdateDoctorMenuCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = MenuViewModel()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.updatedoctor.menu.check")
    private var window: NSWindow?
    private var windowText: NSTextView?
    private var windowScroll: NSScrollView?
    static let interval: TimeInterval = 30 * 60
    static let welcomedKey = "WelcomeShown"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "UpdateDoctor"
        rebuild()
        if CommandLine.arguments.contains("--self-test") {
            print("UpdateDoctor menu \(UpdateDoctorVersion.current) ok")
            NSApp.terminate(nil)
            return
        }
        checkNow()
        // An LSUIElement app has no Dock icon, so opening it can look like nothing
        // happened, and a crowded menu bar can hide the dot behind the notch.
        // Show the status window on the first launch and whenever it is opened again.
        if !UserDefaults.standard.bool(forKey: Self.welcomedKey) {
            UserDefaults.standard.set(true, forKey: Self.welcomedKey)
            showStatusWindow()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.checkNow()
        }
    }

    // MARK: Checks

    @objc func checkNow() {
        if model.isChecking { return }
        model.beginCheck()
        rebuild()
        queue.async {
            // Same checks as `updatedoctor doctor`, run in process without root.
            let report = Doctor(probe: LiveProbe(), options: DoctorOptions()).run()
            DispatchQueue.main.async {
                self.model.apply(report)
                self.rebuild()
            }
        }
    }

    @objc func runAdminCheck() {
        guard let cli = Bundle.main.path(forResource: "updatedoctor", ofType: nil) else {
            model.fail("The bundled updatedoctor command is missing.")
            rebuild()
            return
        }
        model.beginCheck()
        rebuild()
        let script = AdminRunner.appleScript(cliPath: cli)
        queue.async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            let out = Pipe(), err = Pipe()
            task.standardOutput = out
            task.standardError = err
            var message: String?
            var report: Report?
            do {
                try task.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    report = try? AdminRunner.decode(data)
                    if report == nil { message = "Could not read the full check result." }
                } else {
                    let text = String(decoding: errData, as: UTF8.self)
                    message = text.contains("-128") ? "Full check cancelled." : "Full check failed: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
                }
            } catch {
                message = "Could not start osascript: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                if let report { self.model.apply(report, admin: true) } else { self.model.fail(message ?? "Unknown error") }
                self.rebuild()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showStatusWindow()
        return true
    }

    // MARK: Status window

    @objc func showStatusWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 400),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "UpdateDoctor"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 420, height: 240)

            // A real text view in a scroll view: it reports its own laid out height,
            // so the window can size itself to the content without clipping.
            let scroll = NSTextView.scrollableTextView()
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            scroll.borderType = .noBorder
            let text = scroll.documentView as! NSTextView
            text.isEditable = false
            text.isSelectable = true
            text.drawsBackground = false
            text.textContainerInset = NSSize(width: Self.textInset, height: Self.textInset)
            text.textContainer?.lineFragmentPadding = 0
            scroll.translatesAutoresizingMaskIntoConstraints = false

            let check = NSButton(title: "Check now", target: self, action: #selector(checkNow))
            let admin = NSButton(title: "Run full check (admin)...", target: self, action: #selector(runAdminCheck))
            let close = NSButton(title: "Close", target: w, action: #selector(NSWindow.performClose(_:)))
            close.keyEquivalent = "\r"
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let buttons = NSStackView(views: [check, admin, spacer, close])
            buttons.orientation = .horizontal
            buttons.translatesAutoresizingMaskIntoConstraints = false

            let content = NSView()
            content.addSubview(scroll)
            content.addSubview(buttons)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
                buttons.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
                buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            ])
            w.contentView = content
            window = w
            windowText = text
            windowScroll = scroll
            updateStatusWindow()
            fitWindowToContent()
            w.center()
        } else {
            updateStatusWindow()
        }
        scrollStatusToTop()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in self?.scrollStatusToTop() }
    }

    static let windowWidth: CGFloat = 620
    static let textInset: CGFloat = 10
    /// Space taken by the window chrome around the text: top gap, button row, gaps.
    static let chromeHeight: CGFloat = 8 + 12 + 32 + 16

    /// Height the text needs at the given width, including its insets.
    static func textHeight(_ text: NSTextView, width: CGFloat) -> CGFloat {
        guard let container = text.textContainer, let layout = text.layoutManager else { return 0 }
        container.containerSize = NSSize(width: width - 2 * textInset, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height) + 2 * textInset + 2
    }

    /// Size the window to fit all text, capped at 85 percent of the visible screen height.
    private func fitWindowToContent(growOnly: Bool = false) {
        guard let w = window, let text = windowText else { return }
        let width = w.contentLayoutRect.width - 24
        let needed = Self.textHeight(text, width: width) + Self.chromeHeight
        let screen = (w.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let height = min(max(needed, 240), floor(screen * 0.85) - 28)
        if growOnly && height <= w.contentLayoutRect.height { return }
        var frame = w.frame
        let newFrame = w.frameRect(forContentRect: NSRect(x: 0, y: 0, width: w.contentLayoutRect.width, height: height))
        frame.origin.y += frame.height - newFrame.height
        frame.size = newFrame.size
        w.setFrame(frame, display: true)
        scrollStatusToTop()
    }

    private func scrollStatusToTop() {
        guard let scroll = windowScroll else { return }
        windowText?.scroll(.zero)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func updateStatusWindow() {
        guard let text = windowText else { return }
        let out = NSMutableAttributedString()
        func add(_ s: String, _ font: NSFont, _ color: NSColor = .labelColor) {
            out.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color]))
        }
        add("\(model.headline)\n", .boldSystemFont(ofSize: 15))
        add("\(model.isChecking ? "Checking..." : model.lastCheckedText())\n", .systemFont(ofSize: 11), .secondaryLabelColor)
        if let summary = model.report?.summary { add("\(summary)\n", .systemFont(ofSize: 12)) }
        if let error = model.lastError { add("\(error)\n", .systemFont(ofSize: 12), .systemRed) }
        add("\n", .systemFont(ofSize: 6))
        for row in model.rows {
            add("\(Self.mark(row))  \(row.title): \(row.statusLabel)\n", .systemFont(ofSize: 12))
            add("      \(row.detail)\n", .systemFont(ofSize: 11), .secondaryLabelColor)
        }
        add("\nUpdateDoctor lives in the menu bar as a colored dot and has no Dock icon. "
            + "If you cannot see the dot, the notch or other menu bar icons may be hiding it: "
            + "quit a few menu bar apps, or hold Command and drag icons to make room. "
            + "Open UpdateDoctor again from Applications at any time to show this window.",
            .systemFont(ofSize: 11), .secondaryLabelColor)
        text.textStorage?.setAttributedString(out)
        // Grow the window when results arrive so the last row is not clipped.
        fitWindowToContent(growOnly: true)
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
        updateStatusWindow()
        statusItem.button?.image = Self.icon(for: model.health, checking: model.isChecking)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let head = NSMenuItem(title: model.headline, action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        if let summary = model.report?.summary {
            menu.addItem(Self.wrapped(summary, size: 11, color: .secondaryLabelColor))
        }
        let last = NSMenuItem(title: model.isChecking ? "Checking..." : model.lastCheckedText(), action: nil, keyEquivalent: "")
        last.isEnabled = false
        menu.addItem(last)
        if let error = model.lastError {
            menu.addItem(Self.wrapped(error, size: 11, color: .systemRed))
        }
        menu.addItem(.separator())

        for row in model.rows {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let text = NSMutableAttributedString(string: "\(Self.mark(row))  \(row.title): \(row.statusLabel)\n",
                                                 attributes: [.font: NSFont.menuFont(ofSize: 13)])
            text.append(NSAttributedString(string: "     \(Self.trim(row.detail))",
                                           attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = text
            item.toolTip = row.fix.map { "\(row.detail)\n\nFix: \($0)" } ?? row.detail
            item.isEnabled = true
            menu.addItem(item)
        }
        if !model.rows.isEmpty { menu.addItem(.separator()) }

        let check = NSMenuItem(title: "Check now", action: #selector(checkNow), keyEquivalent: "r")
        check.target = self
        check.isEnabled = !model.isChecking
        menu.addItem(check)
        let admin = NSMenuItem(title: "Run full check (admin)...", action: #selector(runAdminCheck), keyEquivalent: "")
        admin.target = self
        admin.isEnabled = !model.isChecking
        menu.addItem(admin)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let show = NSMenuItem(title: "Show status window", action: #selector(showStatusWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let about = NSMenuItem(title: "About UpdateDoctor", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit UpdateDoctor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            model.fail("Start at login: \(error.localizedDescription)")
        }
        rebuild()
    }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Read only diagnosis of why a Mac did not install a macOS update.\n\(UpdateDoctorVersion.repositoryURL)\n\nIf it helps, please star it on GitHub and share it with a Mac admin friend.",
            attributes: [.font: NSFont.systemFont(ofSize: 11)])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationVersion: UpdateDoctorVersion.current])
    }

    // MARK: Drawing

    static func mark(_ row: CheckRow) -> String {
        if row.needsAdmin { return "\u{1F512}" }
        switch row.status {
        case .pass: return "\u{1F7E2}"
        case .info, .skipped: return "\u{26AA}"
        case .warn: return "\u{1F7E1}"
        case .fail: return "\u{1F534}"
        }
    }

    static func trim(_ s: String, max: Int = 90) -> String {
        s.count > max ? String(s.prefix(max - 3)) + "..." : s
    }

    static func wrapped(_ text: String, size: CGFloat, color: NSColor) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: trim(text, max: 110),
                                                  attributes: [.font: NSFont.menuFont(ofSize: size), .foregroundColor: color])
        item.isEnabled = false
        return item
    }

    static func icon(for health: MenuHealth, checking: Bool) -> NSImage {
        let color: NSColor
        switch health {
        case .healthy: color = .systemGreen
        case .atRisk: color = .systemYellow
        case .blocked: color = .systemRed
        case .unknown: color = .systemGray
        }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5))
            (checking && health == .unknown ? color.withAlphaComponent(0.5) : color).setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "UpdateDoctor \(health.title)"
        return image
    }
}

/// Top aligned document view, so the status window scrolls from the top.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
