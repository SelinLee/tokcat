import SwiftUI
import TokcatKit

/// Top-level window: left rail navigation + content pane.
///
/// Performance notes:
/// - Observes only `tabHolder` (not the whole AppModel), so menu-bar activity /
///   token-rate ticks do not rebuild this chrome every 0.4s.
/// - Visited tabs stay mounted so subsequent switches are instant; unvisited
///   tabs are created on first open.
struct MainView: View {
    let model: AppModel
    @ObservedObject var tabHolder: MainTabHolder
    @State private var mountedTabs: Set<MainTab>
    @State private var didWarmStats = false
    @State private var brandLevel: Int

    private let sidebarWidth: CGFloat = 168

    init(model: AppModel, tabHolder: MainTabHolder) {
        self.model = model
        self.tabHolder = tabHolder
        _mountedTabs = State(initialValue: [tabHolder.tab])
        _brandLevel = State(initialValue: model.petState.level)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)

            Rectangle()
                .fill(GameUITheme.frameStroke)
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            ZStack(alignment: .topLeading) {
                ForEach(MainTab.allCases) { item in
                    if mountedTabs.contains(item) {
                        tabContent(item)
                            .environment(\.isMainTabActive, tabHolder.tab == item)
                            .opacity(tabHolder.tab == item ? 1 : 0)
                            .allowsHitTesting(tabHolder.tab == item)
                            .accessibilityHidden(tabHolder.tab != item)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, idealWidth: 920, minHeight: 540, idealHeight: 660)
        .background(GameUITheme.windowBackground)
        .onAppear {
            ensureMounted(tabHolder.tab)
            warmStatsIfNeeded(for: tabHolder.tab)
            brandLevel = model.petState.level
        }
        .onChange(of: tabHolder.tab) { newTab in
            ensureMounted(newTab)
            warmStatsIfNeeded(for: newTab)
        }
        // Low-frequency brand refresh only — not every metrics tick.
        .onReceive(model.$petState) { state in
            if brandLevel != state.level {
                brandLevel = state.level
            }
        }
    }

    private func ensureMounted(_ item: MainTab) {
        if !mountedTabs.contains(item) {
            mountedTabs.insert(item)
        }
    }

    private func warmStatsIfNeeded(for item: MainTab) {
        guard item == .stats else { return }
        guard !didWarmStats else {
            // Subsequent visits: still allow control-driven refresh inside StatsDashboardView.
            return
        }
        didWarmStats = true
        DispatchQueue.main.async {
            model.refreshUsageStats()
        }
    }

    @ViewBuilder
    private func tabContent(_ item: MainTab) -> some View {
        switch item {
        case .stats:
            StatsDashboardView(model: model)
        case .pet:
            PetProfileView(model: model)
        case .bag:
            InventoryView(model: model)
        case .codex:
            CodexView(model: model)
        case .settings:
            SettingsView(model: model, embedded: true)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(MainTab.primaryTabs) { item in
                    sidebarButton(item)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 4) {
                sidebarSectionLabel("系统")
                sidebarButton(.settings)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .background(GameUITheme.panelFill.opacity(0.72))
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GameUITheme.token.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(GameUITheme.token.opacity(0.22), lineWidth: 1)
                    )
                    .frame(width: 34, height: 34)
                Image(systemName: "cat.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GameUITheme.token)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Tokcat")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(GameUITheme.primaryText)
                Text(CompactCopy.levelLabel(brandLevel))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(GameUITheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tokcat \(CompactCopy.levelLabel(brandLevel))")
    }

    private func sidebarSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(GameUITheme.mutedText)
            .tracking(0.6)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
    }

    private func sidebarButton(_ item: MainTab) -> some View {
        let selected = tabHolder.tab == item
        return Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                tabHolder.tab = item
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(selected ? GameUITheme.token : GameUITheme.secondaryText)
                Text(item.title)
                    .font(.subheadline.weight(selected ? .semibold : .medium))
                    .foregroundStyle(selected ? GameUITheme.primaryText : GameUITheme.secondaryText)
                Spacer(minLength: 0)
                if selected {
                    Circle()
                        .fill(GameUITheme.token)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? GameUITheme.token.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? GameUITheme.token.opacity(0.22) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum MainTab: String, CaseIterable, Identifiable, Hashable {
    case stats
    case pet
    case bag
    case codex
    case settings

    var id: String { rawValue }

    static var primaryTabs: [MainTab] {
        [.stats, .pet, .bag, .codex]
    }

    var title: String {
        switch self {
        case .stats: return "统计"
        case .pet: return "宠物"
        case .bag: return "背包"
        case .codex: return "图鉴"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .stats: return "chart.xyaxis.line"
        case .pet: return "cat.fill"
        case .bag: return "bag.fill"
        case .codex: return "books.vertical.fill"
        case .settings: return "gearshape"
        }
    }
}
