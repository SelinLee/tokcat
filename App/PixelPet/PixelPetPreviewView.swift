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

    func makeNSView(context: Context) -> PixelPetView {
        let view = PixelPetView(frame: .zero)
        view.setAnimating(animating && isMainTabActive)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: PixelPetView, context: Context) {
        nsView.setAnimating(animating && isMainTabActive)
        apply(to: nsView)
    }

    private func apply(to view: PixelPetView) {
        view.apply(
            state: PetState(),
            status: status,
            stage: stage,
            skinItemID: skinItemID,
            loadout: loadout
        )
    }
}
