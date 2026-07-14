import SwiftUI
import TokcatKit

/// Game-style bag / equipment screen: paper-doll loadout + item grid + inspector.
struct InventoryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedItemID: String?
    @State private var bagFilter: BagFilter = .all
    @State private var showRules = false

    private enum BagFilter: String, CaseIterable, Identifiable {
        case all
        case equipment
        case skin
        case prop

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .equipment: return "装备"
            case .skin: return "皮肤"
            case .prop: return "道具"
            }
        }

        var systemImage: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .equipment: return "shield.lefthalf.filled"
            case .skin: return "paintpalette.fill"
            case .prop: return "shippingbox.fill"
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 760
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                if wide {
                    HStack(alignment: .top, spacing: 14) {
                        loadoutPanel
                            .frame(width: min(320, geo.size.width * 0.38))
                        bagPanel
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            loadoutPanel
                            bagPanel
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .background(GameUITheme.windowBackground)
        .onAppear {
            reconcileSelection()
        }
        .onChange(of: bagFilter) { _ in
            reconcileSelection()
        }
        .onChange(of: model.inventory.count) { _ in
            reconcileSelection()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                GameScreenTitle(title: "背包", subtitle: "INVENTORY", icon: "bag.fill")
                Spacer()
                hudChips
                rulesButton
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    GameScreenTitle(title: "背包", subtitle: "INVENTORY", icon: "bag.fill")
                    Spacer()
                    rulesButton
                }
                hudChips
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var hudChips: some View {
        HStack(spacing: 8) {
            GameHUDChip(
                title: "今日掉落",
                value: "\(model.lootProgress.dropsToday)/\(LootConfig.default.dailyCap)",
                tint: GameUITheme.token
            )
            GameHUDChip(
                title: "未掉连击",
                value: "\(model.lootProgress.missStreak)",
                tint: GameUITheme.flash
            )
            GameHUDChip(
                title: "保底",
                value: "\(LootConfig.default.pityThreshold)",
                tint: GameUITheme.innerEar
            )
            GameHUDChip(
                title: "持有",
                value: "\(model.inventory.count)种/\(totalQuantity)件",
                tint: GameUITheme.accent
            )
        }
    }

    private var rulesButton: some View {
        Button {
            if reduceMotion {
                showRules.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showRules.toggle()
                }
            }
        } label: {
            Image(systemName: showRules ? "info.circle.fill" : "info.circle")
                .font(.title3)
                .foregroundStyle(showRules ? GameUITheme.token : .secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("掉落规则")
        .accessibilityLabel("掉落规则")
        .accessibilityValue(showRules ? "已展开" : "已收起")
        .accessibilityHint(showRules ? "收起掉落规则" : "展开掉落规则")
    }

    // MARK: - Loadout (paper doll)

    private var loadoutPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            GamePanelHeader(title: "装备栏", subtitle: "LOADOUT", icon: "person.crop.square")

            ZStack {
                // Stage backdrop
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                GameUITheme.stageTop,
                                GameUITheme.stageBottom
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(GameUITheme.frameStroke, lineWidth: 1.5)
                    )

                // Soft vignette / floor glow
                VStack {
                    Spacer()
                    Ellipse()
                        .fill(GameUITheme.token.opacity(0.12))
                        .frame(height: 36)
                        .blur(radius: 8)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 18)
                }

                // Paper-doll layout
                HStack(alignment: .center, spacing: 10) {
                    VStack(spacing: 10) {
                        equipSlotCell(.head)
                        equipSlotCell(.face)
                        equipSlotCell(.back)
                    }
                    .frame(width: 78)

                    VStack(spacing: 8) {
                        PixelPetPreviewView(
                            stage: PetStage.stage(for: model.petState.level),
                            status: model.petProgress.status,
                            skinItemID: model.activeSkinItemID,
                            loadout: model.equipment,
                            animating: !reduceMotion
                        )
                        .frame(width: 120, height: 138)

                        VStack(spacing: 2) {
                            Text(activeSkinName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(CompactCopy.levelLabel(model.petState.level))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(GameUITheme.token)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 10) {
                        equipSlotCell(.held)
                        equipSlotCell(.aura)
                        Color.clear.frame(height: 68)
                    }
                    .frame(width: 78)
                }
                .padding(12)
            }
            .frame(height: 250)

            GameTokenPacketRail(
                progress: Double(model.lootProgress.dropsToday) / Double(max(1, LootConfig.default.dailyCap)),
                title: "今日掉落进度",
                value: "\(model.lootProgress.dropsToday) / \(LootConfig.default.dailyCap)",
                tint: GameUITheme.token,
                trailingTint: GameUITheme.gold,
                segmentCount: LootConfig.default.dailyCap
            )

            bonusStrip

            if showRules {
                rulesInline
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .gamePanel()
    }

    private var bonusStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(CompactCopy.bonusSummaryTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GameUITheme.secondaryText)
                Spacer()
                if !model.activeBonuses.dormantItemIDs.isEmpty {
                    Text("\(CompactCopy.powerDormantLabel) \(model.activeBonuses.dormantItemIDs.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Text(model.activeBonuses.summaryLine)
                .font(.caption.weight(.medium))
                .foregroundStyle(GameUITheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(GameUITheme.insetFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(GameUITheme.frameStroke.opacity(0.7), lineWidth: 1)
                        )
                )

            if !model.activeBonuses.activeSets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("套装")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GameUITheme.secondaryText)
                    ForEach(model.activeBonuses.activeSets) { set in
                        HStack(spacing: 6) {
                            Image(systemName: set.setID.systemImage)
                                .font(.caption2)
                                .foregroundStyle(set.unlockedTierTitles.isEmpty ? GameUITheme.mutedText : GameUITheme.innerEar)
                            Text(set.detailLine)
                                .font(.caption2)
                                .foregroundStyle(GameUITheme.primaryText)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(GameUITheme.insetFill.opacity(0.85))
                )
            }
        }
    }

    private var rulesInline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("掉落规则")
                .font(.caption.weight(.bold))
            Text("· 喂食批次约 \(Int(LootConfig.default.feedBaseChance * 100))%，首充 +\(Int(LootConfig.default.firstFeedBonus * 100))%")
            Text("· 连续 \(LootConfig.default.pityThreshold) 次未掉 → 保底 common+")
            Text("· 升级 100% 小奖励；每日 cap \(LootConfig.default.dailyCap)")
            Text("· 装备/皮肤实时叠到桌面像素猫")
        }
        .font(.caption2)
        .foregroundStyle(GameUITheme.secondaryText)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(GameUITheme.insetFill)
        )
    }

    @ViewBuilder
    private func equipSlotCell(_ slot: EquipSlot) -> some View {
        let itemID = model.equipment.itemID(for: slot)
        let item = itemID.flatMap(ItemCatalog.item(id:))
        let active = item.map {
            $0.effectsActive(level: model.petState.level, stats: model.petState.stats)
        } ?? true
        let selected = selectedItemID == itemID && itemID != nil
        let tint = item.map { rarityColor($0.rarity) } ?? GameUITheme.slotEmpty

        if let itemID, let item {
            Button {
                selectedItemID = itemID
            } label: {
                equipSlotLabel(slot, item: item, active: active, selected: selected, tint: tint)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("卸下") { model.unequipSlot(slot) }
                Button("查看") { selectedItemID = itemID }
            }
            .help(item.name)
            .accessibilityLabel("\(slot.title)，\(item.name)")
            .accessibilityValue(active ? "已装备" : "已装备，能力休眠")
            .accessibilityHint("查看装备详情")
        } else {
            equipSlotLabel(slot, item: nil, active: true, selected: false, tint: tint)
                .help("空槽 · \(slot.title)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(slot.title)槽位")
                .accessibilityValue("空")
        }
    }

    private func equipSlotLabel(
        _ slot: EquipSlot,
        item: ItemDefinition?,
        active: Bool,
        selected: Bool,
        tint: Color
    ) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(GameUITheme.slotFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                selected ? GameUITheme.accent : tint.opacity(item == nil ? 0.35 : 0.85),
                                lineWidth: selected ? 2 : 1.5
                            )
                    )
                    .shadow(color: item == nil ? .clear : tint.opacity(0.28), radius: selected ? 8 : 4)

                Image(systemName: item?.systemImage ?? slotPlaceholderIcon(slot))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item == nil ? GameUITheme.mutedText : tint)
                    .symbolRenderingMode(.hierarchical)

                if item != nil, !active {
                    VStack {
                        Spacer()
                        Text("休眠")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.9), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(4)
                    }
                }
            }
            .frame(width: 68, height: 52)

            Text(slot.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(GameUITheme.secondaryText)
                .lineLimit(1)
        }
    }

    private func slotPlaceholderIcon(_ slot: EquipSlot) -> String {
        switch slot {
        case .head: return "crown"
        case .face: return "eyeglasses"
        case .back: return "flag"
        case .held: return "hand.raised"
        case .aura: return "sparkles"
        }
    }

    // MARK: - Bag panel

    private var bagPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                GamePanelHeader(title: "物品栏", subtitle: "BAG", icon: "square.grid.3x3.fill")
                Spacer()
                if let drop = model.latestLootDrops.first {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                        Text("刚掉：\(drop.item.name)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GameUITheme.innerEar)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(GameUITheme.innerEar.opacity(0.12), in: Capsule())
                }
            }

            filterBar

            GeometryReader { proxy in
                let columns = max(4, Int((proxy.size.width + 10) / 78))
                let grid = Array(repeating: GridItem(.flexible(minimum: 64), spacing: 8), count: columns)

                ScrollView {
                    if filteredRows.isEmpty {
                        emptyBag
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                    } else {
                        LazyVGrid(columns: grid, spacing: 8) {
                            ForEach(filteredRows) { row in
                                itemSlot(row)
                            }
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(minHeight: 180)

            inspector
        }
        .gamePanel()
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(BagFilter.allCases) { filter in
                let on = bagFilter == filter
                Button {
                    bagFilter = filter
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: filter.systemImage)
                            .font(.caption2.weight(.bold))
                        Text(filter.title)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(on ? Color.white : GameUITheme.secondaryText)
                    .background(
                        Capsule()
                            .fill(on ? GameUITheme.token : GameUITheme.insetFill)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(on ? GameUITheme.token : GameUITheme.frameStroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(filteredRows.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(GameUITheme.secondaryText)
        }
    }

    private var emptyBag: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(GameUITheme.mutedText)
            Text(emptyBagTitle)
                .font(.subheadline.weight(.semibold))
            Text("喂 token 或升级，物品会掉进这里。")
                .font(.caption)
                .foregroundStyle(GameUITheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private var emptyBagTitle: String {
        switch bagFilter {
        case .all: return "背包还是空的"
        case .equipment: return "还没有装备"
        case .skin: return "还没有皮肤"
        case .prop: return "还没有道具"
        }
    }

    private func itemSlot(_ row: InventoryItem) -> some View {
        let item = ItemCatalog.item(id: row.itemID)
        let rarity = item?.rarity ?? .common
        let tint = rarityColor(rarity)
        let selected = selectedItemID == row.itemID
        let equipped: Bool = {
            guard let item, let slot = item.slot else { return false }
            return model.equipment.itemID(for: slot) == row.itemID
        }()
        let isActiveSkin = item?.kind == .skin && model.activeSkinItemID == row.itemID
        let dormant: Bool = {
            guard let item, item.isEquippable else { return false }
            return !item.effectsActive(level: model.petState.level, stats: model.petState.stats)
        }()

        return Button {
            selectedItemID = row.itemID
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(selected ? 0.22 : 0.10),
                                        GameUITheme.slotFill
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        selected ? GameUITheme.accent : tint.opacity(0.7),
                                        lineWidth: selected ? 2.2 : 1.2
                                    )
                            )
                            .shadow(color: selected ? tint.opacity(0.35) : .clear, radius: 8)

                        Image(systemName: item?.systemImage ?? "questionmark.square")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(tint)
                            .symbolRenderingMode(.hierarchical)

                        if equipped || isActiveSkin {
                            VStack {
                                HStack {
                                    Text(isActiveSkin ? "用" : "装")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(GameUITheme.token, in: Capsule())
                                    Spacer()
                                }
                                Spacer()
                            }
                            .padding(5)
                        }

                        if dormant {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 7, height: 7)
                                        .padding(5)
                                }
                            }
                        }
                    }
                    .frame(height: 58)
                    .aspectRatio(1, contentMode: .fit)

                    Text(item?.name ?? row.itemID)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GameUITheme.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }

                if row.quantity > 1 {
                    Text("×\(row.quantity)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.95), in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item?.name ?? row.itemID)
        .accessibilityValue(itemAccessibilityValue(
            quantity: row.quantity,
            selected: selected,
            equipped: equipped,
            activeSkin: isActiveSkin,
            dormant: dormant
        ))
        .accessibilityHint("查看物品详情")
        .contextMenu {
            if let item {
                if item.kind == .skin {
                    Button(model.activeSkinItemID == item.id ? "使用中" : "启用皮肤") {
                        _ = model.selectSkin(id: item.id)
                    }
                    .disabled(model.activeSkinItemID == item.id)
                } else if item.isEquippable, let slot = item.slot {
                    let eq = model.equipment.itemID(for: slot) == item.id
                    Button(eq ? "已装备" : "装备") {
                        _ = model.equipItem(id: item.id)
                    }
                    .disabled(eq)
                    if eq {
                        Button("卸下") { model.unequipSlot(slot) }
                    }
                }
            }
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        let item = selectedItemID.flatMap(ItemCatalog.item(id:))
        let ownedQty = selectedItemID.flatMap { id in
            model.inventory.first(where: { $0.itemID == id })?.quantity
        } ?? (item?.id == PetAppearanceState.defaultSkinID ? 1 : 0)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("物品详情")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GameUITheme.secondaryText)
                Spacer()
                if let item {
                    rarityBadge(item.rarity)
                }
            }

            if let item {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(rarityColor(item.rarity).opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(rarityColor(item.rarity).opacity(0.55), lineWidth: 1.5)
                            )
                        Image(systemName: item.systemImage)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(rarityColor(item.rarity))
                    }
                    .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.headline)
                            if ownedQty > 0 {
                                Text("×\(ownedQty)")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(GameUITheme.secondaryText)
                            }
                        }
                        Text(CompactCopy.raritySlotLine(rarity: item.rarity, slot: item.slot) + " · \(item.kind.title)")
                            .font(.caption)
                            .foregroundStyle(GameUITheme.secondaryText)
                        Text(item.rarityRoleLine)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(rarityColor(item.rarity))
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(GameUITheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }

                if item.isEquippable || item.kind == .skin {
                    gearBuckets(for: item)
                }

                actionRow(for: item)
            } else {
                Text("点选物品格或已装备槽位查看详情。")
                    .font(.caption)
                    .foregroundStyle(GameUITheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GameUITheme.insetFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(GameUITheme.frameStroke, lineWidth: 1)
                )
        )
    }

    private func gearBuckets(for item: ItemDefinition) -> some View {
        let met = item.effectsActive(level: model.petState.level, stats: model.petState.stats)
        return VStack(alignment: .leading, spacing: 8) {
            bucketBlock(
                title: GearPresentation.Bucket.requirement.title,
                icon: GearPresentation.Bucket.requirement.systemImage,
                tint: met ? GameUITheme.innerEar : Color.red.opacity(0.85),
                lines: item.requirementLines,
                trailing: met ? CompactCopy.requirementMet : CompactCopy.requirementUnmet
            )
            bucketBlock(
                title: GearPresentation.Bucket.appearance.title,
                icon: GearPresentation.Bucket.appearance.systemImage,
                tint: GameUITheme.accent,
                lines: item.appearanceLines
            )
            bucketBlock(
                title: GearPresentation.Bucket.power.title,
                icon: GearPresentation.Bucket.power.systemImage,
                tint: met ? GameUITheme.token : Color.orange,
                lines: item.powerLines,
                trailing: item.resolvedEffect.plainLines.isEmpty
                    ? nil
                    : (met ? CompactCopy.powerActiveLabel : CompactCopy.powerDormantLabel)
            )
            if item.setID != nil || GearSetCatalog.setID(forItemID: item.id) != nil {
                bucketBlock(
                    title: GearPresentation.Bucket.set.title,
                    icon: GearPresentation.Bucket.set.systemImage,
                    tint: GameUITheme.innerEar,
                    lines: item.setLines
                )
            }
        }
    }

    private func bucketBlock(
        title: String,
        icon: String,
        tint: Color,
        lines: [String],
        trailing: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(GameUITheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func actionRow(for item: ItemDefinition) -> some View {

        HStack(spacing: 8) {
            if item.kind == .skin {
                let owned = isOwned(item)
                let active = model.activeSkinItemID == item.id
                if owned {
                    Button {
                        _ = model.selectSkin(id: item.id)
                    } label: {
                        Label(active ? "使用中" : "启用皮肤", systemImage: active ? "checkmark.circle.fill" : "paintbrush.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GamePrimaryButtonStyle(enabled: !active))
                    .disabled(active)
                } else {
                    Text("未解锁（剪影）")
                        .font(.caption)
                        .foregroundStyle(GameUITheme.secondaryText)
                }
            } else if item.isEquippable, let slot = item.slot {
                let owned = isOwned(item)
                let equipped = model.equipment.itemID(for: slot) == item.id
                if owned {
                    if equipped {
                        Button {
                            model.unequipSlot(slot)
                        } label: {
                            Label("卸下", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GameSecondaryButtonStyle())
                        Button {} label: {
                            Label("已装备", systemImage: "checkmark.shield.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GamePrimaryButtonStyle(enabled: false))
                        .disabled(true)
                    } else {
                        Button {
                            _ = model.equipItem(id: item.id)
                        } label: {
                            Label("装备到\(slot.title)", systemImage: "shield.lefthalf.filled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GamePrimaryButtonStyle(enabled: true))
                    }
                } else {
                    Text("未持有")
                        .font(.caption)
                        .foregroundStyle(GameUITheme.secondaryText)
                }
            } else {
                Text("收藏道具 · 不可装备")
                    .font(.caption)
                    .foregroundStyle(GameUITheme.secondaryText)
            }
        }
    }

    // MARK: - Data helpers

    private var filteredRows: [InventoryItem] {
        let base: [InventoryItem] = {
            // Ensure default skin always appears in skin/all filters even if not in inventory table.
            var rows = model.inventory
            let hasDefault = rows.contains { $0.itemID == PetAppearanceState.defaultSkinID }
            if !hasDefault {
                rows.insert(
                    InventoryItem(itemID: PetAppearanceState.defaultSkinID, quantity: 1, source: .grant),
                    at: 0
                )
            }
            return rows
        }()

        let filtered = base.filter { row in
            guard let item = ItemCatalog.item(id: row.itemID) else {
                return bagFilter == .all
            }
            switch bagFilter {
            case .all: return true
            case .equipment: return item.kind == .equipment
            case .skin: return item.kind == .skin
            case .prop: return item.kind == .prop
            }
        }

        return filtered.sorted { a, b in
            let ia = ItemCatalog.item(id: a.itemID)
            let ib = ItemCatalog.item(id: b.itemID)
            let ra = ia?.rarity.sortRank ?? -1
            let rb = ib?.rarity.sortRank ?? -1
            if ra != rb { return ra > rb }
            return (ia?.name ?? a.itemID) < (ib?.name ?? b.itemID)
        }
    }

    private func reconcileSelection() {
        let visibleIDs = filteredRows.map(\.itemID)
        guard !visibleIDs.isEmpty else {
            selectedItemID = nil
            return
        }
        if let selectedItemID, visibleIDs.contains(selectedItemID) {
            return
        }
        selectedItemID = visibleIDs.first
    }

    private func itemAccessibilityValue(
        quantity: Int,
        selected: Bool,
        equipped: Bool,
        activeSkin: Bool,
        dormant: Bool
    ) -> String {
        var states = ["持有 \(quantity) 件"]
        if selected { states.append("已选择") }
        if equipped { states.append("已装备") }
        if activeSkin { states.append("使用中") }
        if dormant { states.append("能力休眠") }
        return states.joined(separator: "，")
    }

    private var totalQuantity: Int {
        model.inventory.reduce(0) { $0 + $1.quantity }
    }

    private var activeSkinName: String {
        ItemCatalog.item(id: model.activeSkinItemID)?.name ?? "经典米杏"
    }

    private func isOwned(_ item: ItemDefinition) -> Bool {
        if item.id == PetAppearanceState.defaultSkinID { return true }
        return model.inventory.contains { $0.itemID == item.id && $0.quantity > 0 }
    }

    // MARK: - Chrome

    private func rarityBadge(_ rarity: Rarity) -> some View {
        Text("\(rarity.title) · \(rarity.letter)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(rarityColor(rarity))
            .background(rarityColor(rarity).opacity(0.14), in: Capsule())
            .overlay(
                Capsule().strokeBorder(rarityColor(rarity).opacity(0.35), lineWidth: 1)
            )
    }

    private func rarityColor(_ rarity: Rarity) -> Color {
        GameUITheme.rarityColor(rarity)
    }
}
