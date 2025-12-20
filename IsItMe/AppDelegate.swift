import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let stats = LatencyStats()
    private var autoStartMenuItem: NSMenuItem!
    private var latencyHistory: [Double?] = [] // Store last 2 minutes of readings
    private let maxHistoryCount = 120 // 2 minutes at 1 second intervals
    private var updateCheckTimer: Timer?
    private var lastUpdateInfo: UpdateChecker.UpdateInfo?
    private let updateCheckInterval: TimeInterval = 4 * 60 * 60 // 4 hours
    private var pingTarget: String {
        get { UserDefaults.standard.string(forKey: "PingTarget") ?? "1.1.1.1" }
        set { UserDefaults.standard.set(newValue, forKey: "PingTarget") }
    }
    private var pingInterval: TimeInterval {
        get { UserDefaults.standard.double(forKey: "PingInterval") != 0 ? UserDefaults.standard.double(forKey: "PingInterval") : 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: "PingInterval") }
    }
    private var lastUpdateCheckTime: Date? {
        get { UserDefaults.standard.object(forKey: "LastUpdateCheckTime") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "LastUpdateCheckTime") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enable launch at login by default on first run
        if !UserDefaults.standard.bool(forKey: "HasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "HasLaunchedBefore")
            setLaunchAtLogin(enabled: true)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "---"
            button.wantsLayer = true
        }

        createMenu()
        startPinging()
        checkForUpdatesOnLaunch()
        startUpdateCheckTimer()
    }

    private func createMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let currentItem = NSMenuItem(title: "Current: ---", action: nil, keyEquivalent: "")
        currentItem.tag = 1
        menu.addItem(currentItem)

        let avgItem = NSMenuItem(title: "Average: ---", action: nil, keyEquivalent: "")
        avgItem.tag = 2
        menu.addItem(avgItem)

        let minItem = NSMenuItem(title: "Min: ---", action: nil, keyEquivalent: "")
        minItem.tag = 3
        menu.addItem(minItem)

        let maxItem = NSMenuItem(title: "Max: ---", action: nil, keyEquivalent: "")
        maxItem.tag = 4
        menu.addItem(maxItem)

        menu.addItem(NSMenuItem.separator())

        // Ping Target submenu
        let pingTargetItem = NSMenuItem(title: "Ping Target", action: nil, keyEquivalent: "")
        let pingTargetMenu = NSMenu()

        let googleItem = NSMenuItem(title: "google.com", action: #selector(changePingTarget(_:)), keyEquivalent: "")
        googleItem.representedObject = "google.com"
        googleItem.state = pingTarget == "google.com" ? .on : .off
        pingTargetMenu.addItem(googleItem)

        let cloudflareItem = NSMenuItem(title: "1.1.1.1 (Cloudflare)", action: #selector(changePingTarget(_:)), keyEquivalent: "")
        cloudflareItem.representedObject = "1.1.1.1"
        cloudflareItem.state = pingTarget == "1.1.1.1" ? .on : .off
        pingTargetMenu.addItem(cloudflareItem)

        let googleDNSItem = NSMenuItem(title: "8.8.8.8 (Google DNS)", action: #selector(changePingTarget(_:)), keyEquivalent: "")
        googleDNSItem.representedObject = "8.8.8.8"
        googleDNSItem.state = pingTarget == "8.8.8.8" ? .on : .off
        pingTargetMenu.addItem(googleDNSItem)

        pingTargetMenu.addItem(NSMenuItem.separator())

        let customItem = NSMenuItem(title: "Custom...", action: #selector(setCustomPingTarget), keyEquivalent: "")
        pingTargetMenu.addItem(customItem)

        // Show custom target if it's not one of the presets
        if pingTarget != "google.com" && pingTarget != "1.1.1.1" && pingTarget != "8.8.8.8" {
            let currentCustomItem = NSMenuItem(title: pingTarget, action: #selector(changePingTarget(_:)), keyEquivalent: "")
            currentCustomItem.representedObject = pingTarget
            currentCustomItem.state = .on
            pingTargetMenu.insertItem(currentCustomItem, at: 3)
        }

        pingTargetItem.submenu = pingTargetMenu
        menu.addItem(pingTargetItem)

        // Ping Interval submenu
        let pingIntervalItem = NSMenuItem(title: "Ping Interval", action: nil, keyEquivalent: "")
        let pingIntervalMenu = NSMenu()

        let intervals: [(String, TimeInterval)] = [
            ("0.5 seconds", 0.5),
            ("1 second", 1.0),
            ("2 seconds", 2.0),
            ("5 seconds", 5.0)
        ]

        for (title, interval) in intervals {
            let item = NSMenuItem(title: title, action: #selector(changePingInterval(_:)), keyEquivalent: "")
            item.representedObject = interval
            item.state = abs(pingInterval - interval) < 0.01 ? .on : .off
            pingIntervalMenu.addItem(item)
        }

        pingIntervalItem.submenu = pingIntervalMenu
        menu.addItem(pingIntervalItem)

        menu.addItem(NSMenuItem.separator())

        // Version info (clickable to open releases)
        let versionItem = NSMenuItem(
            title: "Version v\(getCurrentVersion() ?? "1.0")",
            action: #selector(openReleasePage),
            keyEquivalent: ""
        )
        versionItem.tag = 100
        versionItem.target = self
        menu.addItem(versionItem)

        // Manual update check
        let updateCheckItem = NSMenuItem(
            title: "Check for Updates",
            action: #selector(manualUpdateCheck),
            keyEquivalent: ""
        )
        updateCheckItem.target = self
        menu.addItem(updateCheckItem)

        menu.addItem(NSMenuItem.separator())

        autoStartMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleAutoStart), keyEquivalent: "")
        autoStartMenuItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(autoStartMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func startPinging() {
        updateLatency()

        timer = Timer.scheduledTimer(withTimeInterval: pingInterval, repeats: true) { [weak self] _ in
            self?.updateLatency()
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        startPinging()
    }

    private func updateLatency() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let latency = PingService.ping(host: self.pingTarget)

            DispatchQueue.main.async {
                self.stats.update(latency: latency)

                // Update history
                self.latencyHistory.append(latency)
                if self.latencyHistory.count > self.maxHistoryCount {
                    self.latencyHistory.removeFirst()
                }

                self.updateUI()
            }
        }
    }

    private func updateUI() {
        let hasConnection = stats.current != nil

        // Always create sparkline background
        let sparklineImage = createSparklineImage(width: 48, height: 22, hasConnection: hasConnection)

        if hasConnection, let latency = stats.current {
            let text = String(format: "%.0f", latency)
            let color = colorForLatency(latency)

            let attributedString = NSMutableAttributedString(string: text)
            attributedString.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: text.count))
            attributedString.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 0), range: NSRange(location: 0, length: text.count))

            // Composite text over sparkline
            if let compositeImage = createCompositeImage(sparkline: sparklineImage, text: attributedString, hasConnection: hasConnection) {
                statusItem.button?.image = compositeImage
                statusItem.button?.attributedTitle = NSAttributedString(string: "")
            } else {
                statusItem.button?.attributedTitle = attributedString
                statusItem.button?.image = nil
            }

            statusItem.button?.layer?.backgroundColor = nil
            statusItem.button?.layer?.cornerRadius = 0
        } else {
            // Connection loss - show only sparkline with red background, no text
            statusItem.button?.image = sparklineImage
            statusItem.button?.attributedTitle = NSAttributedString(string: "")
            statusItem.button?.layer?.backgroundColor = NSColor.red.cgColor
            statusItem.button?.layer?.cornerRadius = 3
        }

        guard let menu = statusItem.menu else { return }

        if let current = stats.current {
            menu.item(withTag: 1)?.title = String(format: "Current: %.1f ms", current)
        } else {
            menu.item(withTag: 1)?.title = "Current: ---"
        }

        if let avg = stats.average {
            menu.item(withTag: 2)?.title = String(format: "Average: %.1f ms", avg)
        } else {
            menu.item(withTag: 2)?.title = "Average: ---"
        }

        if let min = stats.minimum {
            menu.item(withTag: 3)?.title = String(format: "Min: %.1f ms", min)
        } else {
            menu.item(withTag: 3)?.title = "Min: ---"
        }

        if let max = stats.maximum {
            menu.item(withTag: 4)?.title = String(format: "Max: %.1f ms", max)
        } else {
            menu.item(withTag: 4)?.title = "Max: ---"
        }
    }

    private func colorForLatency(_ latency: Double) -> NSColor {
        if latency < 30 {
            return NSColor.green
        } else if latency <= 100 {
            return NSColor.yellow
        } else {
            return NSColor.red
        }
    }

    private func createSparklineImage(width: CGFloat, height: CGFloat, hasConnection: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()

        guard NSGraphicsContext.current?.cgContext != nil else {
            image.unlockFocus()
            return image
        }

        // Only draw if we have history
        guard latencyHistory.count > 1 else {
            image.unlockFocus()
            return image
        }

        // Get valid latencies for scale calculation
        let validLatencies = latencyHistory.compactMap { $0 }
        guard !validLatencies.isEmpty else {
            image.unlockFocus()
            return image
        }

        let maxLatency = max(validLatencies.max() ?? 100, 100) // At least 100ms scale
        let minLatency = validLatencies.min() ?? 0

        // Choose color based on connection status - brighter for dark background
        let lineColor = hasConnection ? NSColor.lightGray.withAlphaComponent(0.7) : NSColor.white.withAlphaComponent(0.5)

        // Draw sparkline with gaps for disconnections
        let pointSpacing = width / CGFloat(max(latencyHistory.count - 1, 1))
        var currentPath = NSBezierPath()
        var pathStarted = false

        for (index, latency) in latencyHistory.enumerated() {
            let x = CGFloat(index) * pointSpacing

            if let latency = latency {
                let normalizedValue = CGFloat((latency - minLatency) / (maxLatency - minLatency))
                let y = height * 0.2 + (normalizedValue * height * 0.6)

                if !pathStarted {
                    currentPath.move(to: NSPoint(x: x, y: y))
                    pathStarted = true
                } else {
                    currentPath.line(to: NSPoint(x: x, y: y))
                }
            } else {
                // Connection lost - finish current path and draw a gap indicator
                if pathStarted {
                    // Draw the accumulated path
                    lineColor.setStroke()
                    currentPath.lineWidth = 1.5
                    currentPath.stroke()

                    // Start a new path
                    currentPath = NSBezierPath()
                    pathStarted = false
                }

                // Draw gap indicator - vertical bar
                if hasConnection {
                    // Red vertical bar for historical gap when connected
                    NSColor.red.withAlphaComponent(0.5).setFill()
                    let barRect = NSRect(x: x - 1, y: height * 0.15, width: 2, height: height * 0.7)
                    NSBezierPath(rect: barRect).fill()
                } else {
                    // White vertical bar for gap when disconnected (more visible)
                    NSColor.white.withAlphaComponent(0.6).setFill()
                    let barRect = NSRect(x: x - 1, y: height * 0.15, width: 2, height: height * 0.7)
                    NSBezierPath(rect: barRect).fill()
                }
            }
        }

        // Draw any remaining path
        if pathStarted {
            lineColor.setStroke()
            currentPath.lineWidth = 1.5
            currentPath.stroke()
        }

        image.unlockFocus()
        return image
    }

    private func createCompositeImage(sparkline: NSImage, text: NSAttributedString, hasConnection: Bool) -> NSImage? {
        let size = sparkline.size
        let composite = NSImage(size: size)

        composite.lockFocus()

        // Draw semi-transparent dark background for better visibility
        if hasConnection {
            NSColor.black.withAlphaComponent(0.65).setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 3, yRadius: 3).fill()
        } else {
            // Draw red background if no connection
            NSColor.red.setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 3, yRadius: 3).fill()
        }

        // Draw sparkline background
        sparkline.draw(in: NSRect(origin: .zero, size: size))

        // Draw text centered
        let textSize = text.size()
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect)

        composite.unlockFocus()

        return composite
    }

    @objc private func changePingTarget(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? String else { return }
        pingTarget = target
        stats.reset()
        latencyHistory.removeAll()
        createMenu() // Recreate menu to update checkmarks
        restartTimer()
    }

    @objc private func setCustomPingTarget() {
        let alert = NSAlert()
        alert.messageText = "Set Custom Ping Target"
        alert.informativeText = "Enter a hostname or IP address:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputTextField.stringValue = pingTarget
        inputTextField.placeholderString = "e.g., example.com or 1.2.3.4"
        alert.accessoryView = inputTextField

        alert.window.initialFirstResponder = inputTextField

        if alert.runModal() == .alertFirstButtonReturn {
            let target = inputTextField.stringValue.trimmingCharacters(in: .whitespaces)
            if !target.isEmpty {
                pingTarget = target
                stats.reset()
                latencyHistory.removeAll()
                createMenu()
                restartTimer()
            }
        }
    }

    @objc private func changePingInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        pingInterval = interval
        latencyHistory.removeAll()
        createMenu() // Recreate menu to update checkmarks
        restartTimer()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func toggleAutoStart() {
        let isEnabled = isLaunchAtLoginEnabled()
        setLaunchAtLogin(enabled: !isEnabled)
        autoStartMenuItem.state = !isEnabled ? .on : .off
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "LaunchAtLogin")
    }

    private func setLaunchAtLogin(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "LaunchAtLogin")

        if #available(macOS 13.0, *) {
            if enabled {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        updateCheckTimer?.invalidate()
    }

    private func checkForUpdatesOnLaunch() {
        // Throttle: only check if last check > 1 hour ago
        if let lastCheck = lastUpdateCheckTime,
           Date().timeIntervalSince(lastCheck) < 3600 {
            return
        }
        performUpdateCheck()
    }

    private func startUpdateCheckTimer() {
        updateCheckTimer = Timer.scheduledTimer(
            withTimeInterval: updateCheckInterval,
            repeats: true
        ) { [weak self] _ in
            self?.performUpdateCheck()
        }
    }

    private func performUpdateCheck() {
        guard let version = getCurrentVersion() else { return }

        UpdateChecker.checkForUpdates(currentVersion: version) { [weak self] updateInfo in
            DispatchQueue.main.async {
                self?.lastUpdateInfo = updateInfo
                self?.lastUpdateCheckTime = Date()
                self?.updateVersionMenuItem()
            }
        }
    }

    @objc private func manualUpdateCheck() {
        guard let version = getCurrentVersion() else { return }

        UpdateChecker.checkForUpdates(currentVersion: version) { [weak self] updateInfo in
            DispatchQueue.main.async {
                self?.lastUpdateInfo = updateInfo
                self?.lastUpdateCheckTime = Date()
                self?.updateVersionMenuItem()

                // Show notification about update status
                let alert = NSAlert()
                if let info = updateInfo {
                    if info.isUpdateAvailable {
                        alert.messageText = "Update Available"
                        alert.informativeText = "Version \(info.latestVersion) is available. Click OK to view the release."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.addButton(withTitle: "Cancel")

                        if alert.runModal() == .alertFirstButtonReturn {
                            if let url = URL(string: info.releaseURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } else {
                        alert.messageText = "You're Up to Date"
                        alert.informativeText = "You have the latest version (\(version)) installed."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                } else {
                    alert.messageText = "Update Check Failed"
                    alert.informativeText = "Unable to check for updates. Please check your internet connection and try again."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    @objc private func openReleasePage() {
        let urlString = lastUpdateInfo?.releaseURL ?? "https://github.com/dvdpearson/IsItMe/releases"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func getCurrentVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private func updateVersionMenuItem() {
        guard let menu = statusItem.menu else { return }

        let versionItem = menu.item(withTag: 100)
        guard let version = getCurrentVersion() else { return }

        if let updateInfo = lastUpdateInfo {
            if updateInfo.isUpdateAvailable {
                versionItem?.title = "Update Available (v\(updateInfo.latestVersion))"
            } else {
                versionItem?.title = "Version v\(version) (up to date)"
            }
        } else {
            versionItem?.title = "Version v\(version)"
        }
    }
}

// MARK: - NSMenuDelegate
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Menu is opening, keep the timer running
    }

    func menuDidClose(_ menu: NSMenu) {
        // Menu closed, timer continues running
    }
}
