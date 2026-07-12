import SwiftUI
import TokcatKit

/// Content of the `MenuBarExtra` dropdown: pet summary, cost, and recently
/// detected tool activity from Tier 1 process monitoring.
struct MenuBarContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tokcat").font(.headline)
                Spacer()
                Text("Lv.\(model.petState.level)")
                    .foregroundStyle(.secondary)
            }

            Divider()

            statRow("Mood", model.petState.mood)
            statRow("Hunger", model.petState.hunger)

            Divider()

            HStack {
                Text("Total cost")
                Spacer()
                Text(model.totalCostUSD, format: .currency(code: "USD"))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if !model.toolActivities.isEmpty {
                Divider()
                Text("Active tools").font(.caption).foregroundStyle(.secondary)
                ForEach(model.toolActivities, id: \.pid) { activity in
                    HStack {
                        Text(activity.tool.displayName)
                        Spacer()
                        Text(String(format: "%.0f%%", activity.cpuPercent))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    private func statRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            ProgressView(value: value)
                .frame(width: 100)
        }
        .font(.caption)
    }
}
