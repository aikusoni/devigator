import AppKit
import Carbon.HIToolbox

@MainActor
final class ShortcutRecorderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private(set) var recordedBinding: HotKeyBinding

    override var acceptsFirstResponder: Bool { true }

    init(initialBinding: HotKeyBinding) {
        recordedBinding = initialBinding
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 86))

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        label.stringValue = initialBinding.displayName
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 22, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            label.stringValue = "조합키를 하나 이상 함께 누르세요"
            NSSound.beep()
            return
        }

        let binding = HotKeyBinding(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyLabel: keyLabel(for: event)
        )
        recordedBinding = binding
        label.stringValue = binding.displayName
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    private func keyLabel(for event: NSEvent) -> String {
        let specialKeys: [UInt16: String] = [
            UInt16(kVK_Space): "SPACE", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "ESC",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_Home): "HOME", UInt16(kVK_End): "END",
            UInt16(kVK_PageUp): "PGUP", UInt16(kVK_PageDown): "PGDN",
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
        ]
        if let label = specialKeys[event.keyCode] { return label }
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            return characters.uppercased()
        }
        return "KEY\(event.keyCode)"
    }
}
