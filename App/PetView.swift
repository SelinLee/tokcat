import SwiftUI
import TokcatKit

/// Lightweight emoji fallback / preview for pet state.
/// Production desktop pet uses the SceneKit window; this remains useful for
/// previews and any non-3D surface.
struct PetView: View {
    let petState: PetState
    var status: PetDerivedStatus?

    var body: some View {
        VStack(spacing: 4) {
            Text(faceEmoji)
                .font(.system(size: 64))
            Text("Lv.\(petState.level)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120, height: 120)
        .background(.clear)
    }

    private var resolvedStatus: PetDerivedStatus {
        status ?? PetPresentation.status(for: petState)
    }

    private var faceEmoji: String {
        switch resolvedStatus {
        case .celebrating: return "🥳"
        case .hungry: return "🙀"
        case .sleepy: return "😴"
        case .excited: return "⚡"
        case .focused: return "🧠"
        case .reviewing: return "🔍"
        case .waiting: return "🙋"
        case .failed: return "💥"
        case .lowEnergy: return "😪"
        case .happy: return "😻"
        case .content: return "😼"
        case .sad: return "😿"
        }
    }
}

#Preview {
    PetView(petState: PetState())
}
