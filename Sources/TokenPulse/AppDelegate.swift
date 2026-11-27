import AppKit
import SwiftUI
import Combine

private let showPanelNotificationName = Notification.Name("com.mango.TokenPulse.showPanel")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var fallbackWindow: NSWindow?
    private let engine = MonitorEngine()
    private var cancellables = Set<AnyCancellable>()
    private var animationTimer: Timer?
    private var pulsePhase: Double = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: if already running, ask the existing instance to show its panel and exit.
        if let bundleId = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                DistributedNotificationCenter.default().postNotificationName(
                    showPanelNotificationName,
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
                NSApp.terminate(nil)
                return
            }
        }

        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageOnly
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 590)
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = WebDashboardViewController(engine: engine, onQuit: {
            NSApp.terminate(nil)
        })

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExternalShowRequest),
            name: showPanelNotificationName,
            object: nil
        )

        // Observe state changes to update the menu bar icon immediately
        engine.$allSessions
            .combineLatest(engine.$allRecords, engine.$menuBarDisplayMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)

        let dt = 0.05
        animationTimer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch self.engine.overallState {
                case .idle:
                    // Gentle, calm sleeping-Mac breathing pulse (~0.36 Hz, ~2.8s per breath)
                    self.pulsePhase = (self.pulsePhase + dt * 0.36).truncatingRemainder(dividingBy: 1.0)
                    self.updateStatusItemAppearance()
                case .running:
                    // Scale sweep frequency smoothly with live unfiltered TPS (10..180 t/s -> 0.42..1.75 Hz)
                    let tps = self.engine.liveLatestTPS ?? 45.0
                    let clamped = max(10.0, min(180.0, tps))
                    let hz = 0.42 + (clamped - 10.0) / 170.0 * 1.33
                    self.pulsePhase = (self.pulsePhase + dt * hz).truncatingRemainder(dividingBy: 1.0)
                    self.updateStatusItemAppearance()
                case .needsAction:
                    // Gentle 0.55 Hz breathing cadence
                    self.pulsePhase = (self.pulsePhase + dt * 0.55).truncatingRemainder(dividingBy: 1.0)
                    self.updateStatusItemAppearance()
                }
            }
        }

        updateStatusItemAppearance()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanelSmart()
        return true
    }

    @objc private func handleExternalShowRequest() {
        showPanelSmart()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let win = fallbackWindow, win.isVisible {
            win.close()
        } else {
            showPanelSmart()
        }
    }

    /// Shows the popover anchored to the menu bar icon if visible,
    /// or falls back to a top-right floating window when the menu bar icon is hidden behind a notch.
    private func showPanelSmart() {
        engine.refresh()
        if let button = statusItem.button,
           let btnWin = button.window,
           btnWin.isVisible,
           btnWin.frame.width > 0 {
            fallbackWindow?.close()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Fallback floating window near top-right of main screen
        if fallbackWindow == nil {
            let win = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 590),
                styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "TokenPulse"
            win.titlebarAppearsTransparent = true
            win.appearance = NSAppearance(named: .aqua)
            win.backgroundColor = NSColor(calibratedRed: 0.965, green: 0.973, blue: 0.984, alpha: 1.0)
            win.isFloatingPanel = true
            win.level = .floating
            win.isReleasedWhenClosed = false
            win.contentViewController = WebDashboardViewController(engine: engine, onQuit: {
                NSApp.terminate(nil)
            })
            fallbackWindow = win
        }

        if let win = fallbackWindow {
            if let screen = NSScreen.main {
                let sf = screen.visibleFrame
                let x = sf.maxX - win.frame.width - 16
                let y = sf.maxY - win.frame.height - 12
                win.setFrameOrigin(NSPoint(x: x, y: y))
            }
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func providerAccentColor(_ provider: AIProvider, isDark: Bool) -> NSColor {
        switch provider {
        case .gpt:
            return isDark
                ? NSColor(calibratedRed: 0.20, green: 0.83, blue: 0.60, alpha: 1.0)
                : NSColor(calibratedRed: 0.06, green: 0.72, blue: 0.50, alpha: 1.0)
        case .gemini:
            return isDark
                ? NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0)
                : NSColor(calibratedRed: 0.00, green: 0.48, blue: 1.00, alpha: 1.0)
        case .claude:
            return isDark
                ? NSColor(calibratedRed: 0.65, green: 0.55, blue: 0.98, alpha: 1.0)
                : NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 1.0)
        }
    }

    private func interpolateColor(_ colors: [NSColor], t: CGFloat) -> NSColor {
        guard !colors.isEmpty else { return .systemBlue }
        if colors.count == 1 { return colors[0] }
        let clamped = max(0, min(1, t))
        let scaled = clamped * CGFloat(colors.count - 1)
        let idx = min(Int(scaled), colors.count - 2)
        let frac = scaled - CGFloat(idx)
        let c1 = colors[idx].usingColorSpace(.deviceRGB) ?? colors[idx]
        let c2 = colors[idx + 1].usingColorSpace(.deviceRGB) ?? colors[idx + 1]
        return NSColor(
            calibratedRed: c1.redComponent + (c2.redComponent - c1.redComponent) * frac,
            green: c1.greenComponent + (c2.greenComponent - c1.greenComponent) * frac,
            blue: c1.blueComponent + (c2.blueComponent - c1.blueComponent) * frac,
            alpha: 1.0
        )
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }

        let pendingCount = engine.activeNeedsActionSessions.count
        let runningSessions = engine.activeRunningSessions
        let runningCount = runningSessions.count
        let displayMode = engine.menuBarDisplayMode
        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Preserve order of active providers (deduplicated) for single or multi-provider blended pulse
        var activeProviders: [AIProvider] = []
        for s in runningSessions {
            if !activeProviders.contains(s.provider) {
                activeProviders.append(s.provider)
            }
        }
        let runningColors = activeProviders.map { providerAccentColor($0, isDark: isDark) }
        let runningTextAccent = interpolateColor(runningColors, t: 0.5)
        let pendingAccent = NSColor(calibratedRed: 0.96, green: 0.44, blue: 0.09, alpha: 1.0)

        button.imagePosition = .imageOnly
        button.title = ""

        let costText = String(format: "$%.2f", engine.last24hEstimatedCostUSD)

        if pendingCount > 0 {
            let badgeText: String? = {
                switch displayMode {
                case .iconOnly: return nil
                case .tps: return "\(pendingCount)"
                case .cost: return costText
                }
            }()
            let img = drawPulseIcon(
                mode: .needsAction(phase: pulsePhase),
                badgeText: badgeText,
                badgeColor: pendingAccent,
                appearance: button.effectiveAppearance
            )
            button.image = img
            statusItem.length = img.size.width
            button.toolTip = "TokenPulse：有 \(pendingCount) 个会话正在等待你操作（近 1 天 \(costText)）"
        } else if runningCount > 0 {
            let tpsLabel = engine.liveLatestTPS.map { "\(Int(round($0)))" } ?? "\(runningCount)"
            let badgeText: String? = {
                switch displayMode {
                case .iconOnly: return nil
                case .tps: return tpsLabel
                case .cost: return costText
                }
            }()
            let img = drawPulseIcon(
                mode: .running(phase: pulsePhase, colors: runningColors),
                badgeText: badgeText,
                badgeColor: runningTextAccent,
                appearance: button.effectiveAppearance
            )
            button.image = img
            statusItem.length = img.size.width
            let names = activeProviders.map(\.shortName).joined(separator: " + ")
            button.toolTip = "TokenPulse：\(names) 运行中（\(Formatters.tps(engine.liveLatestTPS)) · 近 1 天 \(costText)）"
        } else {
            let badgeText: String? = {
                switch displayMode {
                case .iconOnly: return nil
                case .tps: return "0"
                case .cost: return costText
                }
            }()
            let idleInk: NSColor = isDark ? .white : NSColor(white: 0.08, alpha: 0.92)
            let img = drawPulseIcon(
                mode: .idle(phase: pulsePhase),
                badgeText: badgeText,
                badgeColor: idleInk,
                appearance: button.effectiveAppearance
            )
            button.image = img
            statusItem.length = img.size.width
            button.toolTip = "TokenPulse（空闲 · 近 1 天 \(costText) · \(Formatters.tokens(engine.todayTotalTokens)) tokens）"
        }
    }

    private enum StatusIconMode {
        case idle(phase: Double)
        case running(phase: Double, colors: [NSColor])
        case needsAction(phase: Double)
    }

    /// Draws a unified 18pt-tall ECG heartbeat pulse icon aligned with native macOS menu bar icons,
    /// optionally placing a vertically centered number 3pt to the right with zero extra AppKit padding.
    private func drawPulseIcon(
        mode: StatusIconMode,
        badgeText: String?,
        badgeColor: NSColor,
        appearance: NSAppearance
    ) -> NSImage {
        let hasBadge = (badgeText?.isEmpty == false)
        let badgeWeight: NSFont.Weight
        if case .needsAction = mode {
            badgeWeight = .semibold
        } else {
            badgeWeight = .medium
        }
        let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: badgeWeight)
        let badgeSize: NSSize
        if let text = badgeText, !text.isEmpty {
            badgeSize = (text as NSString).size(withAttributes: [.font: badgeFont])
        } else {
            badgeSize = .zero
        }

        // Slightly larger, crisp 20pt-tall ECG icon with 6.5pt gap to digit
        let leftPad: CGFloat = 0.8
        let ecgSpan: CGFloat = 17.5
        let ecgRight: CGFloat = leftPad + ecgSpan
        let gap: CGFloat = 6.5
        let canvasH: CGFloat = 20.0
        let canvasW: CGFloat = hasBadge ? ceil(ecgRight + gap + badgeSize.width - 1.5) : 19.0
        let size = NSSize(width: canvasW, height: canvasH)

        // Strictly centered on y = 10.0 (16.4pt vertical span, matching neighboring menu bar icons)
        let pts: [NSPoint] = [
            NSPoint(x: leftPad + 0.0, y: 10.0),
            NSPoint(x: leftPad + 3.5, y: 10.0),
            NSPoint(x: leftPad + 5.0, y: 12.3),
            NSPoint(x: leftPad + 6.2, y: 7.4),
            NSPoint(x: leftPad + 8.3, y: 18.2),
            NSPoint(x: leftPad + 10.7, y: 1.8),
            NSPoint(x: leftPad + 12.8, y: 12.8),
            NSPoint(x: leftPad + 14.3, y: 10.0),
            NSPoint(x: leftPad + ecgSpan, y: 10.0)
        ]

        // Precompute cumulative arc lengths along the polyline for uniform-speed sweep
        var cumLen: [CGFloat] = [0]
        for i in 1..<pts.count {
            let dx = pts[i].x - pts[i - 1].x
            let dy = pts[i].y - pts[i - 1].y
            cumLen.append(cumLen[i - 1] + hypot(dx, dy))
        }
        let totalLen = cumLen.last ?? 1.0

        func pointAt(_ dist: CGFloat) -> NSPoint {
            let d = max(0, min(totalLen, dist))
            for i in 1..<pts.count {
                if d <= cumLen[i] {
                    let segLen = max(cumLen[i] - cumLen[i - 1], 0.0001)
                    let t = (d - cumLen[i - 1]) / segLen
                    return NSPoint(
                        x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
                        y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t
                    )
                }
            }
            return pts.last!
        }

        func makeFullPath() -> NSBezierPath {
            let p = NSBezierPath()
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.line(to: pt) }
            p.lineWidth = 1.95
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            return p
        }

        func strokeSegment(from d0: CGFloat, to d1: CGFloat, color: NSColor, width: CGFloat) {
            let a = max(0, min(totalLen, d0))
            let b = max(0, min(totalLen, d1))
            guard b > a + 0.05 else { return }
            let p = NSBezierPath()
            p.move(to: pointAt(a))
            for i in 1..<pts.count {
                if cumLen[i] > a && cumLen[i] < b {
                    p.line(to: pts[i])
                }
            }
            p.line(to: pointAt(b))
            p.lineWidth = width
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            color.setStroke()
            p.stroke()
        }

        func drawBadgeIfNeeded(color: NSColor) {
            guard let text = badgeText, !text.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: color
            ]
            let x = ecgRight + gap
            let y = (canvasH - badgeSize.height) / 2.0 - 0.25
            (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }

        switch mode {
        case .idle(let phase):
            let alpha = 0.34 + 0.64 * (0.5 + 0.5 * sin(CGFloat(phase) * .pi * 2.0))
            let img = NSImage(size: size, flipped: false) { _ in
                NSColor.black.withAlphaComponent(alpha).setStroke()
                makeFullPath().stroke()
                drawBadgeIfNeeded(color: NSColor.black.withAlphaComponent(0.85))
                return true
            }
            img.isTemplate = true
            return img

        case .running(let phase, let colors):
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let trackColor: NSColor = isDark
                ? NSColor.white.withAlphaComponent(0.24)
                : NSColor.black.withAlphaComponent(0.18)
            let palette = colors.isEmpty ? [providerAccentColor(.gemini, isDark: isDark)] : colors

            let img = NSImage(size: size, flipped: false) { _ in
                trackColor.setStroke()
                makeFullPath().stroke()

                // Sweeping highlight head with smooth fading tail (single or blended multi-provider gradient)
                let head = CGFloat(phase) * totalLen * 1.38
                let tailLen = totalLen * 0.52
                let slices = 12
                for s in 0..<slices {
                    let f0 = CGFloat(s) / CGFloat(slices)
                    let f1 = CGFloat(s + 1) / CGFloat(slices)
                    let segStart = head - tailLen * (1.0 - f0)
                    let segEnd = head - tailLen * (1.0 - f1)
                    let alpha = 0.14 + 0.86 * pow(f1, 1.45)
                    let sliceColor = self.interpolateColor(palette, t: f1)
                    strokeSegment(from: segStart, to: segEnd, color: sliceColor.withAlphaComponent(alpha), width: 2.0)
                }

                if head >= 0 && head <= totalLen {
                    let hp = pointAt(head)
                    let r: CGFloat = 1.4
                    (palette.last ?? palette[0]).setFill()
                    NSBezierPath(ovalIn: NSRect(x: hp.x - r, y: hp.y - r, width: r * 2, height: r * 2)).fill()
                }
                drawBadgeIfNeeded(color: badgeColor)
                return true
            }
            img.isTemplate = false
            return img

        case .needsAction(let phase):
            let alpha = 0.42 + 0.58 * (0.5 + 0.5 * sin(CGFloat(phase) * .pi * 2.0))
            let orange = NSColor(calibratedRed: 0.96, green: 0.44, blue: 0.09, alpha: alpha)
            let img = NSImage(size: size, flipped: false) { _ in
                orange.setStroke()
                makeFullPath().stroke()
                drawBadgeIfNeeded(color: badgeColor)
                return true
            }
            img.isTemplate = false
            return img
        }
    }
}

