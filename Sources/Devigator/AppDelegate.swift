import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let profileStore = ProfileStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let overlayController = OverlayPanelController()
    private lazy var editorController = ProfileEditorWindowController(store: profileStore)
    private lazy var globalHotKey = GlobalHotKey { [weak self] in
        self?.toggleOverlay()
    }
    private lazy var commandHoldMonitor = CommandHoldMonitor(
        delay: 1.0,
        onBegin: { [weak self] in self?.commandHoldDidBegin() },
        onEnd: { [weak self] in self?.commandHoldDidEnd() }
    )
    private var currentShortcut = HotKeyBinding.saved
    private var currentPlacement = HUDPlacementMode.saved
    private var commandHoldEnabled: Bool = {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "commandHoldEnabled") == nil
            ? true
            : defaults.bool(forKey: "commandHoldEnabled")
    }()
    private var hudShownByCommandHold = false
    private weak var showOverlayMenuItem: NSMenuItem?
    private weak var shortcutMenu: NSMenu?
    private weak var placementMenu: NSMenu?
    private weak var commandHoldMenuItem: NSMenuItem?
    private var activationObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        overlayController.setPlacementMode(currentPlacement)
        observeFrontmostApplication()

        do {
            try globalHotKey.register(currentShortcut)
        } catch {
            showError(error.localizedDescription)
        }
        if commandHoldEnabled { commandHoldMonitor.start() }

        if CommandLine.arguments.contains("--preview") {
            showPreviewOverlay()
        }
        if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-preview"),
           CommandLine.arguments.indices.contains(renderIndex + 1) {
            let url = URL(fileURLWithPath: CommandLine.arguments[renderIndex + 1])
            showPreviewOverlay()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                do {
                    try self?.overlayController.renderPreview(to: url)
                } catch {
                    fputs("Devigator preview error: \(error.localizedDescription)\n", stderr)
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        commandHoldMonitor.stop()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    @objc private func toggleOverlay() {
        if overlayController.isVisible {
            hudShownByCommandHold = false
            overlayController.hide()
            return
        }

        _ = showOverlay()
    }

    @discardableResult
    private func showOverlay() -> Bool {
        profileStore.reload()
        guard let runningApplication = currentExternalApplication() else { return false }
        let application = FrontmostApplication(
            name: runningApplication.localizedName ?? "Unknown Application",
            bundleIdentifier: runningApplication.bundleIdentifier,
            icon: runningApplication.icon
        )
        overlayController.show(
            application: application,
            loadedProfile: profileStore.profile(for: application),
            shortcutKeys: currentShortcut.displayKeys
        )
        return true
    }

    @objc private func showProfilesEditor() {
        overlayController.hide()
        editorController.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        editorController.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openProfilesFolder() {
        do {
            try FileManager.default.createDirectory(
                at: profileStore.profilesDirectory,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(profileStore.profilesDirectory)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func reloadProfiles() {
        profileStore.reload()
        if let error = profileStore.lastError {
            showError(error)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "point.topleft.down.to.point.bottomright.curvepath",
                accessibilityDescription: "Devigator"
            )
            button.toolTip = "Devigator"
        }

        let menu = NSMenu()
        let show = NSMenuItem(
            title: "오버레이 보기 (\(currentShortcut.displayName))",
            action: #selector(toggleOverlay),
            keyEquivalent: ""
        )
        show.target = self
        showOverlayMenuItem = show
        menu.addItem(show)
        menu.addItem(.separator())

        let shortcutRoot = NSMenuItem(title: "호출 단축키", action: nil, keyEquivalent: "")
        let shortcutSubmenu = NSMenu(title: "호출 단축키")
        shortcutMenu = shortcutSubmenu
        shortcutRoot.submenu = shortcutSubmenu
        menu.addItem(shortcutRoot)
        rebuildShortcutMenu()

        let commandHold = NSMenuItem(
            title: "⌘ 길게 눌러 표시",
            action: #selector(toggleCommandHold),
            keyEquivalent: ""
        )
        commandHold.target = self
        commandHold.state = commandHoldEnabled ? .on : .off
        commandHoldMenuItem = commandHold
        menu.addItem(commandHold)

        let placementRoot = NSMenuItem(title: "HUD 위치", action: nil, keyEquivalent: "")
        let placementSubmenu = NSMenu(title: "HUD 위치")
        placementMenu = placementSubmenu
        placementRoot.submenu = placementSubmenu
        menu.addItem(placementRoot)
        rebuildPlacementMenu()

        let edit = NSMenuItem(title: "프로필 편집…", action: #selector(showProfilesEditor), keyEquivalent: ",")
        edit.target = self
        menu.addItem(edit)

        let open = NSMenuItem(title: "프로필 폴더 열기", action: #selector(openProfilesFolder), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let reload = NSMenuItem(title: "프로필 다시 불러오기", action: #selector(reloadProfiles), keyEquivalent: "r")
        reload.target = self
        reload.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(reload)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Devigator 종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func rebuildShortcutMenu() {
        shortcutMenu?.removeAllItems()
        for preset in GlobalShortcutPreset.allCases {
            let item = NSMenuItem(
                title: preset.binding.displayName,
                action: #selector(selectShortcut(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            item.state = preset.binding == currentShortcut ? .on : .off
            shortcutMenu?.addItem(item)
        }
        shortcutMenu?.addItem(.separator())
        let custom = NSMenuItem(
            title: "직접 입력…",
            action: #selector(recordCustomShortcut),
            keyEquivalent: ""
        )
        custom.target = self
        custom.state = GlobalShortcutPreset.allCases.contains(where: { $0.binding == currentShortcut })
            ? .off
            : .on
        shortcutMenu?.addItem(custom)
    }

    @objc private func selectShortcut(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selected = GlobalShortcutPreset(rawValue: rawValue),
              selected.binding != currentShortcut else { return }

        applyShortcut(selected.binding)
    }

    @objc private func recordCustomShortcut() {
        overlayController.hide()
        hudShownByCommandHold = false
        NSApplication.shared.activate(ignoringOtherApps: true)

        let recorder = ShortcutRecorderView(initialBinding: currentShortcut)
        let alert = NSAlert()
        alert.messageText = "호출 단축키 직접 입력"
        alert.informativeText = "원하는 조합을 누르세요. 일반 입력을 방해하지 않도록 조합키가 하나 이상 필요합니다."
        alert.accessoryView = recorder
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = recorder
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        applyShortcut(recorder.recordedBinding)
    }

    private func applyShortcut(_ selected: HotKeyBinding) {
        let previous = currentShortcut
        do {
            try globalHotKey.register(selected)
            currentShortcut = selected
            selected.save()
            showOverlayMenuItem?.title = "오버레이 보기 (\(selected.displayName))"
            rebuildShortcutMenu()

            if overlayController.isVisible,
               let runningApplication = currentExternalApplication() {
                frontmostApplicationDidChange(to: runningApplication)
            }
        } catch {
            try? globalHotKey.register(previous)
            showError("\(selected.displayName)은 다른 앱에서 사용 중일 수 있습니다.\n\n\(error.localizedDescription)")
        }
    }

    @objc private func toggleCommandHold() {
        commandHoldEnabled.toggle()
        UserDefaults.standard.set(commandHoldEnabled, forKey: "commandHoldEnabled")
        commandHoldMenuItem?.state = commandHoldEnabled ? .on : .off
        if commandHoldEnabled {
            commandHoldMonitor.start()
        } else {
            commandHoldMonitor.stop()
        }
    }

    private func commandHoldDidBegin() {
        guard commandHoldEnabled,
              !overlayController.isVisible,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        hudShownByCommandHold = showOverlay()
    }

    private func commandHoldDidEnd() {
        guard hudShownByCommandHold else { return }
        hudShownByCommandHold = false
        overlayController.hide()
    }

    private func rebuildPlacementMenu() {
        placementMenu?.removeAllItems()
        for mode in HUDPlacementMode.allCases {
            let item = NSMenuItem(
                title: mode.displayName,
                action: #selector(selectPlacement(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == currentPlacement ? .on : .off
            placementMenu?.addItem(item)
        }
    }

    @objc private func selectPlacement(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selected = HUDPlacementMode(rawValue: rawValue) else { return }
        currentPlacement = selected
        UserDefaults.standard.set(selected.rawValue, forKey: HUDPlacementMode.defaultsKey)
        overlayController.setPlacementMode(selected)
        rebuildPlacementMenu()
    }

    private func observeFrontmostApplication() {
        let ownBundleID = Bundle.main.bundleIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  application.bundleIdentifier != ownBundleID else { return }
            Task { @MainActor [weak self] in
                self?.frontmostApplicationDidChange(to: application)
            }
        }
        lastExternalApplication = currentExternalApplication()
    }

    private func currentExternalApplication() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            return frontmost
        }
        return lastExternalApplication
    }

    private func frontmostApplicationDidChange(to runningApplication: NSRunningApplication) {
        lastExternalApplication = runningApplication
        guard overlayController.isVisible else { return }

        profileStore.reload()
        let application = FrontmostApplication(
            name: runningApplication.localizedName ?? "Unknown Application",
            bundleIdentifier: runningApplication.bundleIdentifier,
            icon: runningApplication.icon
        )
        overlayController.update(
            application: application,
            loadedProfile: profileStore.profile(for: application),
            shortcutKeys: currentShortcut.displayKeys
        )
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Devigator"
        alert.informativeText = message
        alert.runModal()
    }

    private func showPreviewOverlay() {
        profileStore.reload()
        let bundleIdentifier = "com.jetbrains.intellij"
        let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        )
        let application = FrontmostApplication(
            name: "IntelliJ IDEA",
            bundleIdentifier: bundleIdentifier,
            icon: applicationURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        )
        overlayController.show(
            application: application,
            loadedProfile: profileStore.profile(for: application),
            shortcutKeys: currentShortcut.displayKeys
        )
    }
}
