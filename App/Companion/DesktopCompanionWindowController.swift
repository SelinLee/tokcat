import AppKit
import TokcatKit

/// A transparent, edge-attached window displaying live agent activity.
@MainActor
final class DesktopCompanionWindowController: NSWindowController {
    private let appModel: AppModel
    private let companionView: DesktopCompanionView
    private var pollTimer: Timer?
    private var isVisible = false
    private var lastAnchorCheck = Date.distantPast
    private var isDragging = false
    private var dragStartOrigin: NSPoint = .zero
    private var dragStartMouse: NSPoint = .zero

    init(model: AppModel) {
        appModel = model
        let size = model.settings.desktopPetDockPosition.companionWindowSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = false
        if let x = model.settings.desktopPetWindowX, let y = model.settings.desktopPetWindowY {
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        let root = CompanionInteractionView(frame: NSRect(origin: .zero, size: size))
        let companion = DesktopCompanionView(frame: root.bounds)
        companion.autoresizingMask = [.width, .height]
        root.addSubview(companion)
        window.contentView = root
        companionView = companion
        super.init(window: window)
        companion.onBubbleClick = { [weak self] in self?.openTasks() }
        root.companion = companion
        root.addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:))))
        root.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:))))
        root.menu = makeContextMenu()
        window.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { pollTimer?.invalidate() }

    func setPetVisible(_ visible: Bool) {
        if visible == isVisible {
            if visible { updateAnchor(force: true); applyCurrentState() }
            return
        }
        isVisible = visible
        companionView.setAnimating(visible)
        if visible {
            updateAnchor(force: true)
            applyCurrentState()
            window?.orderFrontRegardless()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.applyCurrentState() }
            }
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
            window?.orderOut(nil)
        }
    }

    private func applyCurrentState() {
        guard isVisible else { return }
        updateAnchor(force: false)
        companionView.characterAppearance = appModel.settings.desktopCompanionAppearance
        companionView.apply(DesktopCompanionSnapshot(
            sessions: appModel.taskMonitor.sessions, tasks: appModel.taskMonitor.tasks,
            fallbackModel: appModel.latestModel, fallbackSource: appModel.latestSource))
    }

    func applyPlacementChoice() {
        isDragging = false
        setPetVisible(true)
        updateAnchor(force: true, explicitChoice: true)
        if let window { appModel.updateDesktopPetWindowOrigin(window.frame.origin) }
    }

    private func updateAnchor(force: Bool, explicitChoice: Bool = false) {
        guard !isDragging, let window else { return }
        if !force && Date().timeIntervalSince(lastAnchorCheck) < 1 { return }
        lastAnchorCheck = Date()
        let position = appModel.settings.desktopPetDockPosition.fixedPosition
        guard let screen = window.screen ?? NSScreen.main else { return }
        let dock = position.isDockSide ? DesktopDockLocator.dockFrame(on: screen) : nil
        companionView.dockFallback = position.isDockSide && dock == nil
        companionView.dockPosition = companionView.dockFallback ? .bottomRight : position
        companionView.dockContactX = nil
        let size = companionView.dockPosition.companionWindowSize
        if window.frame.size != size {
            let origin = window.frame.origin
            window.setContentSize(size)
            window.setFrameOrigin(origin)
        }
        let area = placementFrame(on: screen, dock: dock)
        let origin = PetDockGeometry.origin(position: position, size: size, visible: area, dock: dock,
            currentOrigin: explicitChoice ? nil : window.frame.origin, margin: 0)
        if window.frame.origin != origin { window.setFrameOrigin(origin) }
        if let dock {
            companionView.dockContactX = (position == .dockLeft ? dock.minX : dock.maxX) - origin.x
        }
    }

    private func placementFrame(on screen: NSScreen, dock: NSRect?) -> NSRect {
        guard dock != nil else { return screen.visibleFrame }
        return NSRect(x: screen.frame.minX, y: screen.frame.minY,
            width: screen.frame.width, height: screen.visibleFrame.maxY - screen.frame.minY)
    }

    /// Only the axis parallel to the chosen edge can move.
    func moveAlongAnchor(to proposedOrigin: NSPoint) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let position = appModel.settings.desktopPetDockPosition.fixedPosition
        let dock = position.isDockSide ? DesktopDockLocator.dockFrame(on: screen) : nil
        window.setFrameOrigin(PetDockGeometry.origin(position: position, size: window.frame.size,
            visible: placementFrame(on: screen, dock: dock), dock: dock,
            currentOrigin: proposedOrigin, margin: 0))
    }

    @objc private func handleDrag(_ gesture: NSPanGestureRecognizer) {
        guard let window else { return }
        switch gesture.state {
        case .began:
            isDragging = true
            dragStartOrigin = window.frame.origin
            dragStartMouse = NSEvent.mouseLocation
        case .changed:
            let mouse = NSEvent.mouseLocation
            moveAlongAnchor(to: NSPoint(x: dragStartOrigin.x + mouse.x - dragStartMouse.x,
                y: dragStartOrigin.y + mouse.y - dragStartMouse.y))
        case .ended, .cancelled:
            isDragging = false
            updateAnchor(force: true)
            appModel.updateDesktopPetWindowOrigin(window.frame.origin)
        default: break
        }
    }

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard gesture.state == .ended else { return }
        companionView.interact(at: gesture.location(in: companionView))
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "桌边挂件")
        menu.addItem(withTitle: "查看实时任务", action: #selector(openTasks), keyEquivalent: "")
        let avatars = NSMenuItem(title: "选择 toki / biti", action: nil, keyEquivalent: "")
        let avatarMenu = NSMenu()
        for appearance in CompanionAppearance.allCases {
            let item = avatarMenu.addItem(withTitle: appearance.title,
                action: #selector(chooseAppearance(_:)), keyEquivalent: "")
            item.representedObject = appearance.rawValue
            item.target = self
        }
        avatars.submenu = avatarMenu
        menu.addItem(avatars)
        let anchors = NSMenuItem(title: "吸附位置", action: nil, keyEquivalent: "")
        let anchorMenu = NSMenu()
        for position in PetDockPosition.allCases {
            let item = anchorMenu.addItem(withTitle: position.title,
                action: #selector(choosePosition(_:)), keyEquivalent: "")
            item.representedObject = position.rawValue
            item.target = self
        }
        anchors.submenu = anchorMenu
        menu.addItem(anchors)
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(withTitle: "隐藏挂件", action: #selector(hideCompanion), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func chooseAppearance(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String,
              let appearance = CompanionAppearance(rawValue: raw) else { return }
        appModel.selectCompanionAppearance(appearance)
    }
    @objc private func choosePosition(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String,
              let position = PetDockPosition(rawValue: raw) else { return }
        appModel.selectDesktopPetPosition(position)
    }
    @objc private func openTasks() { MainWindowController.show(model: appModel, tab: .tasks) }
    @objc private func openSettings() { MainWindowController.show(model: appModel, tab: .settings) }
    @objc private func hideCompanion() { appModel.updateSettings { $0.showDesktopPet = false } }
}

/// Only the character and an open detail bubble receive input.
private final class CompanionInteractionView: NSView {
    weak var companion: DesktopCompanionView?
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let companion else { return nil }
        let local = companion.convert(point, from: self)
        return companion.characterRect.contains(local)
            || (companion.showsBubble && companion.bubbleRect.contains(local)) ? self : nil
    }
}
