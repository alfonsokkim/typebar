import AppKit
import ApplicationServices
import TypingCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
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
    private var isEditingAppearance = false
    private var settingsPreviewScreen: NSScreen?
    private let hotKey = GlobalHotKey()
    private var appliedShortcut: OverlayShortcut?
    private var shortcutMonitoringEnabled = false
    private var shortcutItem: NSMenuItem?

    init(vocabulary: [String] = [], settings: OverlaySettings? = nil) {
        self.vocabulary = vocabulary
        self.settings = settings
        super.init()
        observeSettings()
    }

    private func observeSettings() {
        settings?.onChange = { [weak self] in
            guard let self else { return }
            self.applySettings(on: self.settingsPreviewScreen)
            self.synchronizeShortcut()
        }
        settings?.onRecordingChange = { [weak self] in self?.synchronizeShortcut(force: true) }
        settings?.shortcutValidator = { [weak self] candidate in self?.validateShortcut(candidate) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            vocabulary = try EnglishWords.load()
            settings = OverlaySettings(presets: try ThemePalette.presets())
            observeSettings()
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
        shortcutMonitoringEnabled = true
        synchronizeShortcut(force: true)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshGlobalMonitor()
                if AXIsProcessTrusted() { self.permissionTimer?.invalidate(); self.permissionTimer = nil }
            }
        }
        showOverlay()
        if settings?.value.shortcut.keyCode == nil, !AXIsProcessTrusted() { requestPermission() }
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
        shortcutItem = shortcut
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
        window.alphaValue = 1
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
        if isEditingAppearance { settingsWindow?.window?.performClose(nil); return }
        if panel?.isVisible == true { hideOverlay(restoreFocus: true) }
        else { showOverlay() }
    }

    private func showOverlay(on requestedScreen: NSScreen? = nil) {
        if isEditingAppearance { settingsWindow?.window?.performClose(nil); return }
        if panel == nil { createPanel() }
        guard let panel, let typingView else { return }
        if !panel.isVisible {
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = frontmost }
        }
        let point = NSEvent.mouseLocation
        let screen = requestedScreen ?? NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
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
        panel.alphaValue = 1
        typingView.alphaValue = settings.value.validated().textOpacity
        backdropView.configuration = layout.configuration
        backdropView.palette = settings.palette
        typingView.frame = layout.contentFrame
        typingView.bounds = layout.contentBounds
        typingView.palette = settings.palette
        typingView.settleCaret()
    }

    @objc private func showSettings() {
        guard let settings else { return }
        if isEditingAppearance {
            settingsWindow?.showWindow(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        if panel == nil { createPanel() }
        guard let panel else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = frontmost }
        let point = NSEvent.mouseLocation
        let screen = (panel.isVisible ? panel.screen : nil)
            ?? NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        isEditingAppearance = true
        settingsPreviewScreen = screen
        typingView?.session.pause(at: ProcessInfo.processInfo.systemUptime)
        typingView?.settleCaret()
        updateTimer?.invalidate()
        updateTimer = nil
        panel.ignoresMouseEvents = true
        panel.level = .normal
        applySettings(on: screen)
        panel.orderFront(nil)
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(settings: settings)
            settingsWindow?.window?.delegate = self
        }
        if let screen { settingsWindow?.positionBelowPreview(on: screen, previewFrame: panel.frame) }
        settingsWindow?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        if let window = settingsWindow?.window { panel.order(.below, relativeTo: window.windowNumber) }
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

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel, !isEditingAppearance else { return }
        hideOverlay(restoreFocus: false)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow?.window, isEditingAppearance else { return }
        settings?.isRecordingShortcut = false
        let screen = settingsPreviewScreen
        isEditingAppearance = false
        settingsPreviewScreen = nil
        panel?.ignoresMouseEvents = false
        panel?.level = .floating
        showOverlay(on: screen)
    }

    @objc private func restartSession() {
        typingView?.session = TypingSession(vocabulary: vocabulary)
        typingView?.settleCaret()
        typingView?.refreshAccessibility()
        if !isEditingAppearance { panel?.makeFirstResponder(typingView) }
    }

    private func installLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event) }
            return event
        }
    }

    private func refreshGlobalMonitor() {
        let needsModifierMonitor = settings?.value.shortcut.keyCode == nil
        let trusted = AXIsProcessTrusted()
        permissionItem?.isHidden = trusted || !needsModifierMonitor
        if trusted, needsModifierMonitor, globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated { self?.observe(event) }
            }
        } else if (!trusted || !needsModifierMonitor), let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
            gesture.reset()
        }
    }

    private func observe(_ event: NSEvent) {
        guard settings?.isRecordingShortcut != true, settings?.value.shortcut.keyCode == nil else { return }
        if event.type == .keyDown { gesture.keyPressed(); return }
        let flags = ShortcutModifiers(eventFlags: event.modifierFlags)
        if gesture.flagsChanged(flags) { toggleOverlay() }
    }

    private func synchronizeShortcut(force: Bool = false) {
        guard shortcutMonitoringEnabled, let settings else { return }
        let shortcut = settings.value.shortcut.validated()
        guard force || shortcut != appliedShortcut else { return }
        appliedShortcut = shortcut
        hotKey.unregister()
        gesture = ShortcutGesture(required: shortcut.modifiers)
        shortcutItem?.title = "Toggle: \(shortcut.displayName)" + (shortcut.keyCode == nil ? " (press and release)" : "")
        if !settings.isRecordingShortcut, shortcut.keyCode != nil {
            let result = hotKey.register(shortcut, onPress: { [weak self] in self?.toggleOverlay() })
            settings.shortcutError = result == 0 ? nil : "This shortcut is unavailable. Choose another combination."
        }
        refreshGlobalMonitor()
    }

    private func validateShortcut(_ candidate: OverlayShortcut) -> String? {
        guard shortcutMonitoringEnabled else { return nil }
        hotKey.unregister()
        if candidate.keyCode != nil {
            let result = hotKey.register(candidate, onPress: { [weak self] in self?.toggleOverlay() })
            if result != 0 {
                synchronizeShortcut(force: true)
                return "This shortcut is unavailable. Choose another combination."
            }
        }
        appliedShortcut = nil
        return nil
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
        settings?.isRecordingShortcut = false
        hotKey.invalidate()
        updateTimer?.invalidate()
        permissionTimer?.invalidate()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
