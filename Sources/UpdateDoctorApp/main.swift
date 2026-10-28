import AppKit
import ServiceManagement
import UpdateDoctorKit
import UpdateDoctorMenuCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = MenuViewModel()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.updatedoctor.menu.check")
    static let interval: TimeInterval = 30 * 60

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

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
