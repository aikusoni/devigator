import AppKit
import SwiftUI

enum HUDPlacementMode: String, CaseIterable, Identifiable {
    case screenCenter
    case cursorNearby
    case followCursor

    static let defaultsKey = "hudPlacementMode"

    var id: String { rawValue }

    static var saved: HUDPlacementMode {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let mode = HUDPlacementMode(rawValue: rawValue) else {
            return .followCursor
        }
        return mode
    }

    var displayName: String {
        switch self {
        case .screenCenter: return "화면 중앙"
        case .cursorNearby: return "커서 근처에 열기"
        case .followCursor: return "커서 따라가기"
        }
    }
}

@MainActor
final class OverlayPanelController: NSObject {
    private var panels: [NSPanel] = []
    private var followTimer: Timer?
    private var currentAnchor: NSPoint?
    private(set) var placementMode = HUDPlacementMode.saved

    var isVisible: Bool { panels.contains(where: \.isVisible) }

    func show(
        application: FrontmostApplication,
        loadedProfile: LoadedProfile?
    ) {
        rebuildPanels(application: application, loadedProfile: loadedProfile)
        currentAnchor = nil
        positionPanels(smoothly: false)
        panels.forEach { $0.orderFrontRegardless() }
        configureFollowTimer()
    }

    func update(
        application: FrontmostApplication,
        loadedProfile: LoadedProfile?
    ) {
        let wasVisible = isVisible
        rebuildPanels(application: application, loadedProfile: loadedProfile)
        positionPanels(smoothly: false)
        if wasVisible { panels.forEach { $0.orderFrontRegardless() } }
        configureFollowTimer()
    }

    func hide() {
        stopFollowingMouse()
        panels.forEach { $0.orderOut(nil) }
    }

    func setPlacementMode(_ mode: HUDPlacementMode) {
        placementMode = mode
        currentAnchor = nil
        if isVisible {
            positionPanels(smoothly: false)
            configureFollowTimer()
        }
    }

    private func rebuildPanels(
        application: FrontmostApplication,
        loadedProfile: LoadedProfile?
    ) {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()

        if let loadedProfile {
            let groups = displayGroups(from: normalizedGroups(loadedProfile.profile.groups))
            panels = groups.enumerated().map { index, group in
                makePanel(rootView: ShortcutGroupOverlayView(
                    applicationName: loadedProfile.profile.name,
                    group: group,
                    groupIndex: index,
                    isPrimary: index == 0
                ))
            }
        } else {
            panels = [makePanel(rootView: UnregisteredApplicationOverlayView(
                applicationName: application.name
            ))]
        }
    }

    private func makePanel<Content: View>(rootView: Content) -> NSPanel {
        let hostingView = NSHostingView(rootView: rootView)
        let fittingSize = hostingView.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .stationary]
        panel.animationBehavior = .none
        return panel
    }

    private func displayGroups(from groups: [ShortcutProfile.Group]) -> [ShortcutProfile.Group] {
        groups.flatMap { group in
            guard group.shortcuts.count > 4 else { return [group] }
            let partCount = Int(ceil(Double(group.shortcuts.count) / 4.0))
            let partSize = Int(ceil(Double(group.shortcuts.count) / Double(partCount)))
            return stride(from: 0, to: group.shortcuts.count, by: partSize).enumerated().map { part, start in
                let end = min(start + partSize, group.shortcuts.count)
                return ShortcutProfile.Group(
                    id: "\(group.id)-\(part + 1)",
                    title: "\(group.title) \(part + 1)",
                    categoryID: group.categoryID,
                    shortcuts: Array(group.shortcuts[start..<end])
                )
            }
        }
    }

    private func normalizedGroups(
        _ sourceGroups: [ShortcutProfile.Group]
    ) -> [ShortcutProfile.Group] {
        var order: [String] = []
        var groups: [String: ShortcutProfile.Group] = [:]

        for sourceGroup in sourceGroups {
            for shortcut in sourceGroup.shortcuts {
                let categoryID = CapabilityLocalization.categoryID(
                    for: shortcut,
                    fallback: sourceGroup.categoryID
                )
                let key = categoryID ?? "profile.\(sourceGroup.id)"
                if groups[key] == nil {
                    order.append(key)
                    groups[key] = ShortcutProfile.Group(
                        id: key,
                        title: sourceGroup.title,
                        categoryID: categoryID,
                        shortcuts: []
                    )
                }
                groups[key]?.shortcuts.append(shortcut)
            }
        }

        return order.compactMap { groups[$0] }
    }

    private func configureFollowTimer() {
        stopFollowingMouse()
        guard placementMode == .followCursor, isVisible else { return }
        let timer = Timer(
            timeInterval: 1.0 / 45.0,
            target: self,
            selector: #selector(followMouseTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func stopFollowingMouse() {
        followTimer?.invalidate()
        followTimer = nil
    }

    @objc private func followMouseTick() {
        positionPanels(smoothly: true)
    }

    private func positionPanels(smoothly: Bool) {
        guard !panels.isEmpty else { return }
        let mouse = NSEvent.mouseLocation
        guard let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(mouse) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame else { return }

        let desiredAnchor: NSPoint
        switch placementMode {
        case .screenCenter:
            desiredAnchor = NSPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        case .cursorNearby, .followCursor:
            desiredAnchor = mouse
        }

        let relativeOrigins = relativePanelOrigins()
        let relativeBounds = relativeOrigins.enumerated().reduce(NSRect.null) { bounds, item in
            let (index, origin) = item
            return bounds.union(NSRect(origin: origin, size: panels[index].frame.size))
        }
        let safeAnchor = NSPoint(
            x: clamp(
                desiredAnchor.x,
                minimum: visibleFrame.minX - relativeBounds.minX,
                maximum: visibleFrame.maxX - relativeBounds.maxX
            ),
            y: clamp(
                desiredAnchor.y,
                minimum: visibleFrame.minY - relativeBounds.minY,
                maximum: visibleFrame.maxY - relativeBounds.maxY
            )
        )

        let anchor: NSPoint
        if smoothly, let currentAnchor {
            let amount: CGFloat = 0.20
            anchor = NSPoint(
                x: currentAnchor.x + (safeAnchor.x - currentAnchor.x) * amount,
                y: currentAnchor.y + (safeAnchor.y - currentAnchor.y) * amount
            )
        } else {
            anchor = safeAnchor
        }
        currentAnchor = anchor

        for (index, panel) in panels.enumerated() {
            let relative = relativeOrigins[index]
            panel.setFrameOrigin(NSPoint(x: anchor.x + relative.x, y: anchor.y + relative.y))
            if panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    /// Layout order: upper-left, lower-left, upper-right, lower-right.
    private func relativePanelOrigins() -> [NSPoint] {
        let gap: CGFloat = 42
        let stackGap: CGFloat = 12
        var offsets = Array(repeating: CGFloat(0), count: 4)

        return panels.enumerated().map { index, panel in
            let quadrant = index % 4
            let size = panel.frame.size
            let offset = offsets[quadrant]
            offsets[quadrant] += size.height + stackGap

            switch quadrant {
            case 0: return NSPoint(x: -size.width - gap, y: gap + offset)
            case 1: return NSPoint(x: -size.width - gap, y: -size.height - gap - offset)
            case 2: return NSPoint(x: gap, y: gap + offset)
            default: return NSPoint(x: gap, y: -size.height - gap - offset)
            }
        }
    }

    private func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard maximum >= minimum else { return (minimum + maximum) / 2 }
        return min(maximum, max(minimum, value))
    }

    func renderPreview(to url: URL) throws {
        let visiblePanels = panels.filter { $0.contentView != nil }
        guard !visiblePanels.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        let union = visiblePanels.map(\.frame).reduce(NSRect.null) { $0.union($1) }
        let scale: CGFloat = 2
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(union.width * scale),
            pixelsHigh: Int(union.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }
        canvas.size = union.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: union.size).fill()
        for panel in visiblePanels {
            guard let view = panel.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(bitmap)
            image.draw(
                in: NSRect(
                    x: panel.frame.minX - union.minX,
                    y: panel.frame.minY - union.minY,
                    width: panel.frame.width,
                    height: panel.frame.height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let png = canvas.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url, options: .atomic)
    }
}
