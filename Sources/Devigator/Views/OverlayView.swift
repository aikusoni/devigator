import SwiftUI

struct ShortcutGroupOverlayView: View {
    let applicationName: String
    let group: ShortcutProfile.Group
    let groupIndex: Int
    let isPrimary: Bool

    private var accent: Color {
        PointerHUDPalette.color(for: groupIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if isPrimary {
                    Text(applicationName.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.7)
                        .foregroundStyle(.white.opacity(0.62))
                        .shadow(color: .black.opacity(0.95), radius: 3)
                }

                HStack(spacing: 7) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: accent.opacity(0.8), radius: 5)
                    Text(CapabilityLocalization.groupTitle(group))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.95), radius: 4)
                    Spacer()
                    Text(String(format: "%02d", group.shortcuts.count))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                        .shadow(color: .black, radius: 3)
                }
            }

            VStack(spacing: 7) {
                ForEach(group.shortcuts) { shortcut in
                    HStack(spacing: 10) {
                        Text(CapabilityLocalization.action(shortcut))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.96))
                            .lineLimit(1)
                            .shadow(color: .black, radius: 4, x: 0, y: 1)

                        Spacer(minLength: 12)
                        FloatingInputHints(shortcut: shortcut, accent: accent)
                    }
                    .frame(minHeight: 31)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.065), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 12, x: 0, y: 4)
    }
}

struct UnregisteredApplicationOverlayView: View {
    let applicationName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(applicationName.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.cyan)
                .shadow(color: .black, radius: 3)
            Text(CapabilityLocalization.interfaceText(
                korean: "단축키 정보가 등록되지 않은 앱입니다",
                english: "No shortcut information is registered for this app"
            ))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 4)
            Text(CapabilityLocalization.interfaceText(
                korean: "프로필을 만들거나 가져오면 자동으로 표시됩니다.",
                english: "Create or import a profile to show its shortcuts."
            ))
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .shadow(color: .black, radius: 3)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.065), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 12, x: 0, y: 4)
    }
}

private struct FloatingKeyCaps: View {
    let keys: [String]
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: keyWidth(key), minHeight: 27)
                    .padding(.horizontal, key.count > 2 ? 5 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.black.opacity(0.28))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.28), accent.opacity(0.28)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.82), radius: 3, x: 0, y: 2)
            }
        }
    }

    private func keyWidth(_ key: String) -> CGFloat {
        if key.count >= 4 { return 42 }
        if key.count >= 2 { return 33 }
        return 27
    }
}

private struct FloatingInputHints: View {
    let shortcut: ShortcutProfile.Shortcut
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            FloatingKeyCaps(keys: shortcut.keys, accent: accent)
            ForEach(Array((shortcut.pointerGestures ?? []).enumerated()), id: \.offset) { _, gesture in
                Text("/")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                FloatingPointerGesture(gesture: gesture, accent: accent)
            }
        }
    }
}

private struct FloatingPointerGesture: View {
    let gesture: ShortcutProfile.Shortcut.PointerGesture
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            FloatingKeyCaps(keys: gesture.modifiers, accent: accent)
            HStack(spacing: 2) {
                if gesture.button != .primary {
                    Text(gesture.button == .secondary ? "R" : "M")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                }
                Image(systemName: "cursorarrow.click")
                    .font(.system(size: 13, weight: .bold))
                if gesture.clickCount > 1 {
                    Text("\(gesture.clickCount)×")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(minWidth: 27, minHeight: 27)
            .padding(.horizontal, gesture.clickCount > 1 ? 3 : 0)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.black.opacity(0.28))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.28), accent.opacity(0.28)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.82), radius: 3, x: 0, y: 2)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var accessibilityLabel: String {
        let button = switch gesture.button {
        case .primary: "primary"
        case .secondary: "secondary"
        case .middle: "middle"
        }
        return "\(button) click \(gesture.clickCount) time(s)"
    }
}

private enum PointerHUDPalette {
    static func color(for index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.23, green: 0.78, blue: 1.00),
            Color(red: 0.25, green: 0.94, blue: 0.74),
            Color(red: 0.75, green: 0.48, blue: 1.00),
            Color(red: 1.00, green: 0.56, blue: 0.30)
        ]
        return colors[index % colors.count]
    }
}
