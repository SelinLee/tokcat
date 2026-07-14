import Foundation

public enum ItemKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case skin
    case prop
    case equipment

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .skin: return "皮肤"
        case .prop: return "道具"
        case .equipment: return "装备"
        }
    }
}

public enum Rarity: String, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .common: return "普通"
        case .uncommon: return "优秀"
        case .rare: return "稀有"
        case .epic: return "史诗"
        case .legendary: return "传说"
        }
    }

    public var loreTitle: String {
        CompactCopy.rarityLore(self)
    }

    public var letter: String {
        CompactCopy.rarityLetter(self)
    }

    public var sortRank: Int {
        switch self {
        case .common: return 0
        case .uncommon: return 1
        case .rare: return 2
        case .epic: return 3
        case .legendary: return 4
        }
    }

    public static func < (lhs: Rarity, rhs: Rarity) -> Bool {
        lhs.sortRank < rhs.sortRank
    }
}

public enum EquipSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case head
    case face
    case back
    case held
    case aura

    public var id: String { rawValue }

    public var title: String {
        CompactCopy.slotPlain(self)
    }

    public var loreTitle: String {
        CompactCopy.slotLore(self)
    }
}

public enum LootSource: String, Codable, CaseIterable, Sendable {
    case feed
    case levelUp
    case pity
    case grant

    public var title: String {
        switch self {
        case .feed: return "喂食掉落"
        case .levelUp: return "升级奖励"
        case .pity: return "保底"
        case .grant: return "系统发放"
        }
    }
}

public struct ItemDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var detail: String
    public var kind: ItemKind
    public var rarity: Rarity
    public var slot: EquipSlot?
    public var systemImage: String
    /// Minimum level / stats / pathway before powers activate.
    public var requirement: StatRequirement?
    /// Numeric powers. Appearance still shows when dormant.
    public var effect: ItemEffect?
    /// Optional pathway tag for loot gating (C4).
    public var pathway: PathwayID?
    /// Explicit menu-bar hat id; also readable from effect.menuBarHatID.
    public var menuBarHatID: String?
    /// Minimum player level for the item to enter drop pools (defaults to requirement.minLevel).
    public var dropMinLevel: Int?
    /// Optional equipment set membership.
    public var setID: GearSetID?

    public init(
        id: String,
        name: String,
        detail: String,
        kind: ItemKind,
        rarity: Rarity,
        slot: EquipSlot? = nil,
        systemImage: String,
        requirement: StatRequirement? = nil,
        effect: ItemEffect? = nil,
        pathway: PathwayID? = nil,
        menuBarHatID: String? = nil,
        dropMinLevel: Int? = nil,
        setID: GearSetID? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.kind = kind
        self.rarity = rarity
        self.slot = slot
        self.systemImage = systemImage
        self.requirement = requirement
        self.effect = effect
        self.pathway = pathway
        self.menuBarHatID = menuBarHatID ?? effect?.menuBarHatID
        self.dropMinLevel = dropMinLevel
        self.setID = setID ?? GearSetCatalog.setID(forItemID: id)
    }

    public var isEquippable: Bool {
        kind == .equipment && slot != nil
    }

    public var resolvedRequirement: StatRequirement {
        requirement ?? .none
    }

    public var resolvedEffect: ItemEffect {
        effect ?? .none
    }

    public var resolvedDropMinLevel: Int {
        dropMinLevel ?? requirement?.minLevel ?? 1
    }

    public func effectsActive(level: Int, stats: PetStats) -> Bool {
        resolvedRequirement.isSatisfied(level: level, stats: stats)
    }

    public var requirementLine: String {
        resolvedRequirement.plainLine
    }

    public var effectLine: String {
        resolvedEffect.effectSummaryLine
    }

    public var appearanceLines: [String] {
        GearPresentation.appearanceLines(for: self)
    }

    public var powerLines: [String] {
        GearPresentation.powerLines(for: self)
    }

    public var requirementLines: [String] {
        GearPresentation.requirementLines(for: self)
    }

    public var setLines: [String] {
        GearPresentation.setLines(for: self)
    }

    public var rarityRoleLine: String {
        GearPresentation.rarityRoleLine(rarity)
    }
}

public struct InventoryItem: Codable, Equatable, Sendable, Identifiable {
    public var itemID: String
    public var quantity: Int
    public var obtainedAt: Date
    public var source: LootSource

    public var id: String { itemID }

    public init(
        itemID: String,
        quantity: Int = 1,
        obtainedAt: Date = Date(),
        source: LootSource = .feed
    ) {
        self.itemID = itemID
        self.quantity = quantity
        self.obtainedAt = obtainedAt
        self.source = source
    }
}

public struct EquipmentLoadout: Codable, Equatable, Sendable {
    /// Slot raw value → item id.
    public var slots: [String: String]

    public init(slots: [String: String] = [:]) {
        self.slots = slots
    }

    public func itemID(for slot: EquipSlot) -> String? {
        slots[slot.rawValue]
    }

    public mutating func equip(itemID: String, slot: EquipSlot) {
        slots[slot.rawValue] = itemID
    }

    public mutating func unequip(slot: EquipSlot) {
        slots.removeValue(forKey: slot.rawValue)
    }
}

/// Soft pity / daily cap bookkeeping for the loot loop.
public struct LootProgressState: Codable, Equatable, Sendable {
    public var dayKey: String?
    public var dropsToday: Int
    /// Consecutive eligible feed batches without a drop.
    public var missStreak: Int
    public var firstFeedBonusUsedDayKey: String?

    public init(
        dayKey: String? = nil,
        dropsToday: Int = 0,
        missStreak: Int = 0,
        firstFeedBonusUsedDayKey: String? = nil
    ) {
        self.dayKey = dayKey
        self.dropsToday = dropsToday
        self.missStreak = missStreak
        self.firstFeedBonusUsedDayKey = firstFeedBonusUsedDayKey
    }
}

public struct LootDrop: Equatable, Sendable, Identifiable {
    public var id: String
    public var item: ItemDefinition
    public var quantity: Int
    public var source: LootSource
    public var wasPity: Bool
    public var timestamp: Date

    public init(
        id: String = UUID().uuidString,
        item: ItemDefinition,
        quantity: Int = 1,
        source: LootSource,
        wasPity: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.item = item
        self.quantity = quantity
        self.source = source
        self.wasPity = wasPity
        self.timestamp = timestamp
    }
}

public struct LootRollResult: Equatable, Sendable {
    public var drops: [LootDrop]
    public var progress: LootProgressState
    /// True when a feed roll was attempted (hit or miss).
    public var didRollFeed: Bool
    public var feedHit: Bool

    public init(
        drops: [LootDrop] = [],
        progress: LootProgressState = LootProgressState(),
        didRollFeed: Bool = false,
        feedHit: Bool = false
    ) {
        self.drops = drops
        self.progress = progress
        self.didRollFeed = didRollFeed
        self.feedHit = feedHit
    }

    public var didDrop: Bool { !drops.isEmpty }
}


/// Selected pixel cosmetics (skin + equipment loadout).
public struct PetAppearanceState: Codable, Equatable, Sendable {
    /// Active full-body skin item id. Defaults to classic Tokcat.
    public var skinItemID: String
    public var equipment: EquipmentLoadout

    public static let defaultSkinID = "skin_classic"

    public init(skinItemID: String = PetAppearanceState.defaultSkinID, equipment: EquipmentLoadout = EquipmentLoadout()) {
        self.skinItemID = skinItemID
        self.equipment = equipment
    }
}
