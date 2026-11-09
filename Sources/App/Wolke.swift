// SPDX-License-Identifier: Apache-2.0
import AppKit
import OSLog
import SafariServices
import SwiftUI
import WidgetKit

@main
struct Wolke {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = Controller()
    private let widgetLog = Logger(subsystem: "studio.local.wolke", category: "WidgetControls")
    private var window: NSWindow?
    private var status: NSStatusItem?
    private var terminationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Wolke für SoundCloud")
        item.button?.toolTip = "Wolke für SoundCloud"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        status = item

        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier == "com.apple.Safari" else { return }
            Task { @MainActor in self?.controller.safariQuit() }
        }
        controller.start()
        controller.checkSafariExtension()
        WidgetCenter.shared.reloadTimelines(ofKind: "WolkePlayer")
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Wolke")
        appMenu.addItem(withTitle: "Über Wolke", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Wolke ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Wolke beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Fenster")
        add(windowMenu, "Wolke anzeigen", #selector(showPlayer))
        windowMenu.addItem(withTitle: "Fenster schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller.checkSafariExtension()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPlayer()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme == "wolke" }) else { return }
        switch url.host {
        case "control":
            guard let request = controller.widgetCommand(for: url) else { return }
            window?.orderOut(nil)
            if NSApp.isActive { NSApp.hide(nil) }
            widgetLog.info("Received widget action: \(request.action.rawValue, privacy: .public)")
            Task { await controller.perform(request.action, expectedURL: request.url) }
        case "playlist":
            let requested = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "track" })?.value
            if let requested, let track = URL(string: requested) {
                openPlaylist(track)
            }
        case "player":
            openSafariTrack()
        default:
            showPlayer()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let track = controller.state.track {
            let item = menu.addItem(withTitle: track.artist.isEmpty ? track.title : "\(track.title) · \(track.artist)",
                                    action: nil, keyEquivalent: "")
            item.isEnabled = false
            if PlayerAction.toggle.enabled(in: controller.state) {
                add(menu, track.playing ? "Pause" : "Play", #selector(toggle))
            }
            menu.addItem(.separator())
        }
        let connection = menu.addItem(
            withTitle: controller.bridgeFailed ? "Lokale Verbindung belegt" : controller.safariConnection.label,
            action: nil, keyEquivalent: ""
        )
        connection.isEnabled = false
        add(menu, "Player anzeigen", #selector(showPlayer))
        add(menu, "Safari-Erweiterung öffnen", #selector(openSafariExtension))
        add(menu, "SoundCloud in Safari öffnen", #selector(openSafariTrack))
        menu.addItem(.separator())
        add(menu, "Wolke beenden", #selector(quit))
    }

    private func add(_ menu: NSMenu, _ title: String, _ selector: Selector) {
        menu.addItem(withTitle: title, action: selector, keyEquivalent: "").target = self
    }

    @objc private func toggle() {
        Task { await controller.perform(.toggle, expectedURL: controller.state.track?.url) }
    }

    @objc private func showPlayer() {
        if window == nil {
            let content = DesktopPlayerView(
                controller: controller,
                openPlaylist: { [weak self] track in self?.openPlaylist(track) }
            )
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 136),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Wolke für SoundCloud"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func openPlaylist(_ track: URL) {
        guard let url = controller.playlistURL(for: track) else { return }
        openInSafari(url)
    }

    @objc private func openSafariTrack() {
        openInSafari(controller.state.track?.url ?? URL(string: "https://soundcloud.com/discover")!)
    }

    @objc private func openSafariExtension() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: Controller.safariExtensionID) { error in
            guard error != nil else { return }
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "Safari-Erweiterung einrichten"
                alert.informativeText = "Öffne in Safari die Einstellungen. Im Reiter „Entwickler“ aktiviere „Nicht signierte Erweiterungen erlauben“. Wechsle danach zu „Erweiterungen“ und aktiviere Wolke. Falls „Entwickler“ fehlt, blende die Funktionen für Webentwickler unter „Erweitert“ ein."
                alert.addButton(withTitle: "Safari öffnen")
                alert.addButton(withTitle: "Schließen")
                if alert.runModal() == .alertFirstButtonReturn,
                   let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
                    NSWorkspace.shared.openApplication(at: safari, configuration: .init(), completionHandler: nil)
                }
            }
        }
    }

    private func openInSafari(_ url: URL) {
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: configuration) { _, error in
            guard error != nil else { return }
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "Safari konnte nicht geöffnet werden"
                alert.informativeText = "Öffne soundcloud.com direkt in Safari."
                alert.runModal()
            }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

private struct DesktopPlayerView: View {
    @ObservedObject var controller: Controller
    let openPlaylist: (URL) -> Void

    var body: some View {
        PlayerCard(state: controller.state) {
            if let track = controller.state.track {
                HStack(spacing: 1) {
                    ForEach(PlayerAction.controls, id: \.self) { action in
                        Button {
                            Task { await controller.perform(action, expectedURL: track.url) }
                        } label: {
                            PlayerGlyph(action: action, track: track)
                        }
                        .buttonStyle(.plain)
                        .disabled(!action.enabled(in: controller.state))
                        .opacity(action.enabled(in: controller.state) ? 1 : 0.38)
                        .accessibilityLabel(action.label)
                    }
                    Button {
                        openPlaylist(track.url)
                    } label: {
                        PlayerGlyph(track: track)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Zu Playlist hinzufügen")
                }
            }
        }
        .frame(width: 320, height: 136)
        .background { PlayerBackground() }
    }
}
