import SwiftUI
import TokcatKit

/// Collection codex: owned items vs silhouettes for missing entries.
/// Tuned for scroll performance: no full AppModel observation, static pet preview,
/// LazyVStack sections, and O(1) ownership lookups.
struct CodexView: View {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isMainTabActive) private var isMainTabActive

    @State private var searchText = ""
    @State private var ownershipFilter: OwnershipFilter = .all
    @State private var expandedSections: Set<CodexSection> = Set(CodexSection.allCases)

    /// Local snapshot so scrolling is not rebuilt by pet ticks / metrics.
    @State private var ownedIDs: Set<String> = []
    @State private var quantityByID: [String: Int] = [:]
    @State private var equipment = EquipmentLoadout()
    @State private var activeSkinItemID = PetAppearanceState.defaultSkinID
    @State private var petLevel = 1
    @State private var petStatus: PetDerivedStatus = .content
    @State private var petStats = PetStats()

    private enum OwnershipFilter: String, CaseIterable, Identifiable {
        case all
        case owned
        case missing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .owned: return "已获得"
            case .missing: return "未获得"
            }
        }
    }

    private enum CodexSection: String, CaseIterable, Identifiable {
        case skins
        case equipment
        case props

        var id: String { rawValue }

        var title: String {
            switch self {
            case .skins: return "皮肤"
            case .equipment: return "装备"
            case .props: return "道具"
            }
        }

        var subtitle: String {
            switch self {
            case .skins: return "SKINS"
            case .equipment: return "GEAR"
            case .props: return "PROPS"
            }
        }

        var icon: String {
            switch self {
            case .skins: return "paintpalette.fill"
            case .equipment: return "shield.lefthalf.filled"
            case .props: return "shippingbox.fill"
            }
        }

        var items: [ItemDefinition] {
            switch self {
            case .skins: return ItemCatalog.skins
            case .equipment: return ItemCatalog.equipmentItems
            case .props: return ItemCatalog.props
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                topBar
                livePreview
                discoveryControls

                ForEach(CodexSection.allCases) { section in
                    codexSection(section)
                }

                if visibleItemCount == 0 {
                    emptyResults
                }
            }
            .padding(16)
        }
        .background(GameUITheme.windowBackground)
        .onAppear(perform: pullSnapshot)
        .onChange(of: isMainTabActive) { active in
            if active { pullSnapshot() }
        }
        // Inventory / equipment / skin can change while codex is open — lightweight.
        .onReceive(model.$inventory) { _ in
            guard isMainTabActive else { return }
            pullOwnership()
        }
        .onReceive(model.$equipment) { value in
            guard isMainTabActive else { return }
            equipment = value
        }
        .onReceive(model.$activeSkinItemID) { value in
            guard isMainTabActive else { return }
            activeSkinItemID = value
        }
    }

    // MARK: - Snapshot

    private func pullSnapshot() {
        pullOwnership()
        equipment = model.equipment
        activeSkinItemID = model.activeSkinItemID
        petLevel = model.petState.level
        petStatus = model.petProgress.status
        petStats = model.petState.stats
    }

    private func pullOwnership() {
        var owned: Set<String> = [PetAppearanceState.defaultSkinID]
        var qty: [String: Int] = [:]
        for row in model.inventory where row.quantity > 0 {
            owned.insert(row.itemID)
            qty[row.itemID] = row.quantity
        }
        ownedIDs = owned
        quantityByID = qty
    }

    // MARK: - Header

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                GameScreenTitle(title: "图鉴", subtitle: "CODEX", icon: "books.vertical.fill")
                Spacer()
                summaryChips
            }

            VStack(alignment: .leading, spacing: 8) {
                GameScreenTitle(title: "图鉴", subtitle: "CODEX", icon: "books.vertical.fill")
                summaryChips
            }
        }
    }

    private var summaryChips: some View {
        HStack(spacing: 8) {
            GameHUDChip(title: "已获得", value: "\(ownedCount)", tint: GameUITheme.innerEar)
            GameHUDChip(title: "未获得", value: "\(missingCount)", tint: GameUITheme.accent)
            GameHUDChip(title: "完成率", value: completionText, tint: GameUITheme.token)
        }
    }

    private var livePreview: some View {
        HStack(spacing: 16) {
            // Static pose while browsing — animated composite during scroll was a major hitch source.
            PixelPetPreviewView(
                stage: PetStage.stage(for: petLevel),
                status: petStatus,
                skinItemID: activeSkinItemID,
                loadout: equipment,
                animating: false
            )
            .frame(width: 120, height: 136)
            .background(
                RoundedRectangle(cornerRadius: GameUITheme.Radius.stage, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [GameUITheme.stageTop, GameUITheme.stageBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: GameUITheme.Radius.stage, style: .continuous)
                            .strokeBorder(GameUITheme.frameStroke, lineWidth: 1.5)
                    )
            )

            VStack(alignment: .leading, spacing: 8) {
                GamePanelHeader(title: "实时收藏", subtitle: "LIVE SET", icon: "sparkles")
                Text(activeSkinName)
                    .font(GameUITheme.heroTitleFont)
                Text("已获得的皮肤和装备可在图鉴中直接启用，变化会同步到桌面像素猫。")
                    .font(.caption)
                    .foregroundStyle(GameUITheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                GameTokenPacketRail(
                    progress: completionProgress,
                    title: "收集进度",
                    value: "\(ownedCount) / \(ItemCatalog.all.count)",
                    tint: GameUITheme.token,
                    trailingTint: GameUITheme.accent
                )
            }
            Spacer(minLength: 0)
        }
        .gamePanel()
    }

    private var discoveryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            GamePanelHeader(title: "查找藏品", subtitle: "DISCOVER", icon: "magnifyingglass")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    searchField
                    ownershipPicker
                        .frame(width: 250)
                }
                VStack(alignment: .leading, spacing: 8) {
                    searchField
                    ownershipPicker
                }
            }
        }
        .gamePanel()
    }

    private var searchField: some View {
        TextField("搜索藏品名称", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("搜索藏品")
    }

    private var ownershipPicker: some View {
        Picker("获得状态", selection: $ownershipFilter) {
            ForEach(OwnershipFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Sections

    private func codexSection(_ section: CodexSection) -> some View {
        let items = filteredItems(in: section)
        let expanded = expandedSections.contains(section)

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                toggle(section)
            } label: {
                HStack(spacing: 8) {
                    GamePanelHeader(title: section.title, subtitle: section.subtitle, icon: section.icon)
                    Spacer()
                    Text("\(items.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(GameUITheme.secondaryText)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GameUITheme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, !items.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(items) { item in
                        card(for: item)
                    }
                }
            } else if expanded {
                Text("没有符合筛选的\(section.title)")
                    .font(.caption)
                    .foregroundStyle(GameUITheme.secondaryText)
            }
        }
        .gamePanel()
    }

    private var emptyResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("没有匹配的藏品")
                .font(.headline)
            Text("试试切换「全部 / 已获得 / 未获得」，或清空搜索。")
                .font(.caption)
                .foregroundStyle(GameUITheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gamePanel()
    }


    @ViewBuilder
    private func card(for item: ItemDefinition) -> some View {
        let owned = isOwned(item)
        let isActiveSkin = item.kind == .skin && item.id == activeSkinItemID
        let isEquipped: Bool = {
            guard item.kind == .equipment, let slot = item.slot else { return false }
            return equipment.itemID(for: slot) == item.id
        }()
        let isDormant: Bool = {
            guard isEquipped else { return false }
            return !item.effectsActive(level: petLevel, stats: petStats)
        }()
        CodexCardView(
            item: item,
            owned: owned,
            quantity: quantity(item.id),
            activeSkin: isActiveSkin,
            equipped: isEquipped,
            dormant: isDormant,
            onActivate: { activate(item) }
        )
    }

    // MARK: - Data

    private func filteredItems(in section: CodexSection) -> [ItemDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return section.items.filter { item in
            let owned = isOwned(item)
            switch ownershipFilter {
            case .all: break
            case .owned: if !owned { return false }
            case .missing: if owned { return false }
            }
            if query.isEmpty { return true }
            return item.name.lowercased().contains(query)
                || item.id.lowercased().contains(query)
                || item.rarity.title.lowercased().contains(query)
        }
    }

    private func toggle(_ section: CodexSection) {
        if reduceMotion {
            if expandedSections.contains(section) {
                expandedSections.remove(section)
            } else {
                expandedSections.insert(section)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.15)) {
                if expandedSections.contains(section) {
                    expandedSections.remove(section)
                } else {
                    expandedSections.insert(section)
                }
            }
        }
    }

    private var ownedCount: Int { ownedIDs.count }
    private var missingCount: Int { max(0, ItemCatalog.all.count - ownedCount) }
    private var completionProgress: Double {
        Double(ownedCount) / Double(max(1, ItemCatalog.all.count))
    }
    private var completionText: String {
        "\(Int((completionProgress * 100).rounded()))%"
    }
    private var visibleItemCount: Int {
        CodexSection.allCases.reduce(0) { $0 + filteredItems(in: $1).count }
    }
    private var activeSkinName: String {
        ItemCatalog.item(id: activeSkinItemID)?.name ?? "经典米杏"
    }

    private func isOwned(_ item: ItemDefinition) -> Bool {
        ownedIDs.contains(item.id)
    }

    private func quantity(_ id: String) -> Int {
        quantityByID[id] ?? 0
    }

    private func activate(_ item: ItemDefinition) {
        guard isOwned(item) else { return }
        switch item.kind {
        case .skin:
            model.selectSkin(id: item.id)
            activeSkinItemID = item.id
        case .equipment:
            _ = model.equipItem(id: item.id)
            equipment = model.equipment
        case .prop:
            break
        }
        pullOwnership()
    }
}

// MARK: - Card (isolated view = cheaper invalidation)

private struct CodexCardView: View {
    let item: ItemDefinition
    let owned: Bool
    let quantity: Int
    let activeSkin: Bool
    let equipped: Bool
    let dormant: Bool
    let onActivate: () -> Void

    private var tint: Color { GameUITheme.rarityColor(item.rarity) }
    private var rarityLine: String { item.rarity.title + " · " + item.kind.title }
    private var loreLine: String { owned ? item.detail : "尚未发现这件藏品。" }
    private var subtitleColor: Color { tint.opacity(owned ? 1 : 0.55) }
    private var displayName: String { owned ? item.name : "???" }

    var body: some View {
        Button(action: onActivate) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(owned ? tint : GameUITheme.mutedText)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(owned ? tint : GameUITheme.secondaryText)
                            .lineLimit(1)
                        Text(rarityLine)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                Text(loreLine)
                    .font(.caption2)
                    .foregroundStyle(GameUITheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                cardFooter
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: GameUITheme.Radius.card, style: .continuous)
                    .fill(GameUITheme.insetFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GameUITheme.Radius.card, style: .continuous)
                    .strokeBorder(
                        owned ? tint.opacity(0.35) : GameUITheme.frameStroke,
                        lineWidth: 1.2
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!owned || item.kind == .prop)
        .opacity(owned ? 1 : 0.72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(owned ? item.name : "未获得藏品")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(owned && item.kind != .prop ? "点按启用" : "")
    }

    @ViewBuilder
    private var cardFooter: some View {
        HStack(spacing: 6) {
            if item.kind == .prop, owned {
                Text("×\(quantity)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(GameUITheme.secondaryText)
            }
            if activeSkin {
                labelChip("使用中", tint: GameUITheme.token)
            }
            if equipped {
                labelChip(dormant ? "已装备·休眠" : "已装备", tint: dormant ? GameUITheme.flash : GameUITheme.innerEar)
            }
            Spacer(minLength: 0)
            if owned, item.kind != .prop {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(GameUITheme.secondaryText)
                    .font(.caption)
            }
        }
    }

    private func labelChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var iconName: String {
        switch item.kind {
        case .skin: return owned ? "paintpalette.fill" : "paintpalette"
        case .equipment: return owned ? "shield.lefthalf.filled" : "shield"
        case .prop: return owned ? "shippingbox.fill" : "shippingbox"
        }
    }

    private var accessibilityValue: String {
        var values = [item.rarity.title, item.kind.title]
        if item.kind == .prop, owned { values.append("持有 \(quantity) 件") }
        if activeSkin { values.append("使用中") }
        if equipped { values.append(dormant ? "已装备休眠" : "已装备") }
        if !owned { values.append("未获得") }
        return values.joined(separator: "，")
    }
}
