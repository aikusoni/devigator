import AppKit
import SwiftUI

@MainActor
final class ProfileEditorWindowController: NSWindowController {
    init(store: ProfileStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Devigator 프로필"
        window.minSize = NSSize(width: 860, height: 560)
        window.center()
        window.contentView = NSHostingView(rootView: ProfileEditorView(store: store))
        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
