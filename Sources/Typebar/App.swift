import AppKit
import ApplicationServices
import TypingCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@main
enum TypebarMain {
    static func main() {
        let application = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--capture-previews"),
           CommandLine.arguments.indices.contains(index + 1) {
            do { try PreviewCapture.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)) }
            catch { FileHandle.standardError.write(Data("Could not capture Typebar previews: \(error)\n".utf8)); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--desktop-preview") {
            application.setActivationPolicy(.accessory)
            do { try PreviewCapture.desktop() }
            catch { FileHandle.standardError.write(Data("Could not show desktop preview: \(error)\n".utf8)); exit(1) }
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: OverlayPanel?
    private var typingView: TypingView?
    private var statusItem: NSStatusItem?
    private var vocabulary: [String] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var updateTimer: Timer?
    private var permissionTimer: Timer?
    private var gesture = ShortcutGesture()
    private var previousApplication: NSRunningApplication?
    private var permissionItem: NSMenuItem?
    private var hiding = false
    private var settings: OverlaySettings?
    private var settingsWindow: SettingsWindow?
    private var backdropView: ShadowBackdropView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            vocabulary = try EnglishWords.load()
            settings = OverlaySettings(presets: try ThemePalette.presets())
            settings?.onChange = { [weak self] in self?.applySettings() }
        }
        catch {
            let alert = NSAlert()
            alert.messageText = "Typebar could not load its resources"
            alert.informativeText = "Reinstall Typebar to restore the bundled words and themes."
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }
        createMenu()
        installLocalMonitor()
        refreshGlobalMonitor()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshGlobalMonitor()
                if AXIsProcessTrusted() { self.permissionTimer?.invalidate(); self.permissionTimer = nil }
            }
        }
        showOverlay()
        if !AXIsProcessTrusted() { requestPermission() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showOverlay()
        return true
    }

    private func createMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = TypebarMark.menuBarImage()
        item.button?.toolTip = "Typebar"
        let menu = NSMenu()
        for (title, selector, key) in [
            ("Show / Hide Typebar", #selector(toggleOverlay), ""),
            ("Restart Typing", #selector(restartSession), "r")
        ] {
            let command = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            command.target = self
            menu.addItem(command)
        }
        menu.addItem(.separator())
        let preferences = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        let shortcut = NSMenuItem(title: "Toggle: ⌃⌥⌘ (press and release)", action: nil, keyEquivalent: "")
        menu.addItem(shortcut)
        let permission = NSMenuItem(title: "Enable Global Shortcut…", action: #selector(requestPermission), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        permissionItem = permission
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Typebar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    private func createPanel() {
        let padding = ShadowBackdropView.contentPadding
        let frame = NSRect(x: 0, y: 0, width: 980 + padding * 2,
                           height: ShadowBackdropView.contentHeight + padding * 2)
        let window = OverlayPanel(contentRect: frame,
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Typebar"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.alphaValue = 0.94
        window.isReleasedWhenClosed = false
        window.delegate = self
        let backdrop = ShadowBackdropView(frame: frame)
        backdrop.appearance = NSAppearance(named: .darkAqua)
        let input = TypingView(frame: backdrop.bounds.insetBy(dx: padding, dy: padding), vocabulary: vocabulary)
        input.onHide = { [weak self] in self?.hideOverlay(restoreFocus: true) }
        input.onRestart = { [weak self] in self?.restartSession() }
        input.onSettings = { [weak self] in self?.showSettings() }
        backdrop.addSubview(input)
        window.contentView = backdrop
        typingView = input
        backdropView = backdrop
        panel = window
    }

    @objc private func toggleOverlay() {
        if panel?.isVisible == true { hideOverlay(restoreFocus: true) }
        else { showOverlay() }
    }

    private func showOverlay() {
        if panel == nil { createPanel() }
        guard let panel, let typingView else { return }
        if !panel.isVisible {
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = frontmost }
        }
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        applySettings(on: screen)
        typingView.session.resume(at: ProcessInfo.processInfo.systemUptime)
        typingView.settleCaret()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(typingView)
        typingView.refreshAccessibility()
        if updateTimer == nil {
            updateTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.typingView?.refreshAccessibility() }
            }
        }
    }

    private func applySettings(on screen: NSScreen? = nil) {
        guard let panel, let settings, let typingView, let backdropView,
              let visible = (screen ?? panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let layout = OverlayLayout.resolve(in: visible, preferences: settings.value)
        panel.setFrame(layout.frame, display: true)
        panel.alphaValue = settings.value.validated().contentOpacity
        backdropView.configuration = layout.configuration
        backdropView.palette = settings.palette
        typingView.frame = layout.contentFrame
        typingView.bounds = layout.contentBounds
        typingView.palette = settings.palette
        typingView.settleCaret()
    }

    @objc private func showSettings() {
        guard let settings else { return }
        hideOverlay(restoreFocus: false)
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(settings: settings, showOverlay: { [weak self] in self?.showOverlay() })
        }
        settingsWindow?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func hideOverlay(restoreFocus: Bool) {
        guard !hiding, let panel, panel.isVisible else { return }
        hiding = true
        typingView?.session.pause(at: ProcessInfo.processInfo.systemUptime)
        typingView?.settleCaret()
        updateTimer?.invalidate()
        updateTimer = nil
        panel.orderOut(nil)
        if restoreFocus, let previousApplication, !previousApplication.isTerminated {
            previousApplication.activate(options: [])
        }
        hiding = false
    }

    func windowDidResignKey(_ notification: Notification) { hideOverlay(restoreFocus: false) }

    @objc private func restartSession() {
        typingView?.session = TypingSession(vocabulary: vocabulary)
        typingView?.settleCaret()
        typingView?.refreshAccessibility()
        panel?.makeFirstResponder(typingView)
    }

    private func installLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event) }
            return event
        }
    }

    private func refreshGlobalMonitor() {
        let trusted = AXIsProcessTrusted()
        permissionItem?.isHidden = trusted
        if trusted, globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.observe(event) }
            }
        } else if !trusted, let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
            gesture.reset()
        }
    }

    private func observe(_ event: NSEvent) {
        if event.type == .keyDown { gesture.keyPressed(); return }
        var flags: ShortcutModifiers = []
        for (native, value) in [(NSEvent.ModifierFlags.control, ShortcutModifiers.control),
                                 (.option, .option), (.command, .command), (.shift, .shift), (.function, .function)] {
            if event.modifierFlags.contains(native) { flags.insert(value) }
        }
        if gesture.flagsChanged(flags) { toggleOverlay() }
    }

    @objc private func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
        permissionTimer?.invalidate()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
