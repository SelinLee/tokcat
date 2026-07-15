import AppKit
import SwiftUI
import TokcatKit

private struct IsMainTabActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// `false` while a main-window tab is mounted but not selected.
    var isMainTabActive: Bool {
        get { self[IsMainTabActiveKey.self] }
        set { self[IsMainTabActiveKey.self] = newValue }
    }
}

/// Compact SwiftUI wrapper around the pixel pet for bag / codex / profile previews.
struct PixelPetPreviewView: NSViewRepresentable {
    @Environment(\.isMainTabActive) private var isMainTabActive

    var stage: PetStage
    var status: PetDerivedStatus
    var skinItemID: String
    var loadout: EquipmentLoadout
    var animating: Bool = true
    /// When non-nil, showcase this clip instead of the live status pose.
    var forcedClip: PixelPetClip? = nil
    /// Bump to re-trigger the current forced one-shot clip.
    var replayToken: Int = 0
    var activity: MenuBarAgentActivity = .idle

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PixelPetView {
        let view = PixelPetView(frame: .zero)
        view.setAnimating(animating && isMainTabActive)
        context.coordinator.didApplyInitial = false
        apply(to: view, context: context, isInitial: true)
        return view
    }

    func updateNSView(_ nsView: PixelPetView, context: Context) {
        nsView.setAnimating(animating && isMainTabActive)
        apply(to: nsView, context: context, isInitial: false)
    }

    private func apply(to view: PixelPetView, context: Context, isInitial: Bool) {
        view.apply(
            state: PetState(),
            status: status,
            stage: stage,
            skinItemID: skinItemID,
            loadout: loadout,
            activity: activity
        )

        let clipChanged = context.coordinator.forcedClip != forcedClip
        let replayChanged = context.coordinator.replayToken != replayToken
        context.coordinator.forcedClip = forcedClip
        context.coordinator.replayToken = replayToken

        if isInitial || clipChanged {
            view.forceClip(forcedClip, liveStatus: status)
        } else if forcedClip != nil, replayChanged {
            view.replayForcedClip()
        }
    }

    final class Coordinator {
        var forcedClip: PixelPetClip? = nil
        var replayToken: Int = 0
        var didApplyInitial = false
    }
}
