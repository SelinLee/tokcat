import SwiftUI
import TokcatKit

/// Renders the cat sprite, blending its look from `mood` and `hunger`.
/// A single emoji-based placeholder stands in for real sprite frames until
/// `Resources/Sprites` art lands — the state-selection logic is what matters
/// here, not the art asset itself.
struct PetView: View {
    let petState: PetState

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

    private var faceEmoji: String {
        if petState.hunger < 0.2 {
            return "🙀"
        }
        if petState.mood > 0.7 {
            return "😻"
        }
        if petState.mood < 0.3 {
            return "😿"
        }
        return "😼"
    }
}

#Preview {
    PetView(petState: PetState())
}
