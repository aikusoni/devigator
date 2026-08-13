import AppKit
import Carbon.HIToolbox

@MainActor
final class CommandHoldMonitor: NSObject {
    private let delay: TimeInterval
    private let onBegin: () -> Void
    private let onEnd: () -> Void
    private var timer: Timer?
    private var pressedAt: Date?
    private var isShowing = false
    private var cancelledUntilRelease = false

    init(
        delay: TimeInterval = 1.0,
        onBegin: @escaping () -> Void,
        onEnd: @escaping () -> Void
    ) {
        self.delay = delay
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(
            timeInterval: 1.0 / 45.0,
            target: self,
            selector: #selector(pollModifiers),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        finishIfNeeded()
        reset()
    }

    @objc private func pollModifiers() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let commandDown = flags.contains(.maskCommand)

        guard commandDown else {
            finishIfNeeded()
            reset()
            return
        }

        let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate]
        if !flags.intersection(otherModifiers).isEmpty || anyNonModifierKeyIsPressed() {
            cancelledUntilRelease = true
            pressedAt = nil
            finishIfNeeded()
            return
        }

        guard !cancelledUntilRelease else { return }
        if pressedAt == nil { pressedAt = Date() }

        if !isShowing, let pressedAt, Date().timeIntervalSince(pressedAt) >= delay {
            isShowing = true
            onBegin()
        }
    }

    private func finishIfNeeded() {
        guard isShowing else { return }
        isShowing = false
        onEnd()
    }

    private func reset() {
        pressedAt = nil
        cancelledUntilRelease = false
    }

    private func anyNonModifierKeyIsPressed() -> Bool {
        let modifierKeyCodes: Set<CGKeyCode> = [
            CGKeyCode(kVK_Command), CGKeyCode(kVK_RightCommand),
            CGKeyCode(kVK_Shift), CGKeyCode(kVK_RightShift),
            CGKeyCode(kVK_Control), CGKeyCode(kVK_RightControl),
            CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption),
            CGKeyCode(kVK_CapsLock), CGKeyCode(kVK_Function)
        ]
        for keyCode in CGKeyCode(0)..<CGKeyCode(128)
        where !modifierKeyCodes.contains(keyCode) {
            if CGEventSource.keyState(.combinedSessionState, key: keyCode) {
                return true
            }
        }
        return false
    }
}
