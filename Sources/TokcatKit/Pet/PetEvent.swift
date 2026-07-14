import Foundation

/// Discrete pet lifecycle / presentation events produced by the growth loop.
/// Distinct from `TokenEvent` (raw usage). Used for timeline, float text, and SFX.
public enum PetEventKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case fed
    case levelUp
    case achievement
    case interacted
    case statusChanged
    case lootDropped
    case equipped

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fed: return "喂食"
        case .levelUp: return "升级"
        case .achievement: return "成就"
        case .interacted: return "互动"
        case .statusChanged: return "状态"
        case .lootDropped: return "掉落"
        case .equipped: return "装备"
        }
    }

    public var systemImage: String {
        switch self {
        case .fed: return "fork.knife"
        case .levelUp: return "arrow.up.circle.fill"
        case .achievement: return "medal.fill"
        case .interacted: return "hand.tap.fill"
        case .statusChanged: return "heart.text.square"
        case .lootDropped: return "gift.fill"
        case .equipped: return "shield.lefthalf.filled"
        }
    }
}

/// One row in the pet "recent events" timeline.
public struct PetTimelineEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: PetEventKind
    public var timestamp: Date
    /// Short primary line, e.g. "+12.4k tokens".
    public var title: String
    /// Secondary detail, e.g. "premium · Claude Code".
    public var detail: String
    /// Optional structured payload for UI (tokens, levels, achievement id…).
    public var payload: [String: String]

    public init(
        id: String = UUID().uuidString,
        kind: PetEventKind,
        timestamp: Date = Date(),
        title: String,
        detail: String = "",
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
        self.payload = payload
    }

    public var floatText: String {
        switch kind {
        case .fed:
            if let raw = payload["tokens"], let tokens = Int(raw) {
                return "+\(Self.compactTokens(tokens))"
            }
            return title
        case .levelUp:
            if let to = payload["toLevel"] {
                return "Lv.\(to)!"
            }
            return "升级!"
        case .achievement:
            return "成就!"
        case .interacted:
            return "摸摸~"
        case .statusChanged:
            return title
        case .lootDropped:
            if let name = payload["itemName"], !name.isEmpty {
                return name
            }
            return "掉落!"
        case .equipped:
            if let name = payload["itemName"], !name.isEmpty {
                return name
            }
            return "装备!"
        }
    }

    public var prefersSound: Bool {
        switch kind {
        case .fed, .levelUp, .achievement, .interacted, .lootDropped, .equipped: return true
        case .statusChanged: return false
        }
    }

    private static func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

/// Helper that builds timeline events from engine apply results / UI actions.
public enum PetEventFactory {
    public static func fed(
        tokens: Int,
        xpGained: Double,
        dominantTier: NutritionTier?,
        source: AgentSource?,
        model: String?,
        at timestamp: Date = Date()
    ) -> PetTimelineEvent {
        let tierText = dominantTier?.rawValue ?? "mixed"
        let sourceText = source?.displayName ?? "Agent"
        let modelText = model ?? "—"
        return PetTimelineEvent(
            kind: .fed,
            timestamp: timestamp,
            title: "吃到 \(compactTokens(tokens)) tokens",
            detail: "+\(String(format: "%.1f", xpGained)) XP · \(tierText) · \(sourceText) · \(modelText)",
            payload: [
                "tokens": "\(tokens)",
                "xp": String(format: "%.2f", xpGained),
                "tier": tierText,
                "source": source?.rawValue ?? "",
                "model": modelText
            ]
        )
    }

    public static func levelUp(
        from: Int,
        to: Int,
        stats: PetStats = PetStats(),
        at timestamp: Date = Date()
    ) -> PetTimelineEvent {
        let title = CompactCopy.levelUpToastTitle(from: from, to: to)
        let detail = PathwayLore.sequenceTitleLine(level: to, stats: stats)
        return PetTimelineEvent(
            kind: .levelUp,
            timestamp: timestamp,
            title: title,
            detail: detail,
            payload: [
                "fromLevel": "\(from)",
                "toLevel": "\(to)",
                "delta": "\(to - from)",
                "sequence": "\(ManifestTier.sequenceLabel(for: to))"
            ]
        )
    }

    public static func achievement(_ item: PetAchievement, at timestamp: Date = Date()) -> PetTimelineEvent {
        PetTimelineEvent(
            kind: .achievement,
            timestamp: timestamp,
            title: item.title,
            detail: item.detail,
            payload: ["achievementId": item.id]
        )
    }

    public static func interacted(at timestamp: Date = Date()) -> PetTimelineEvent {
        PetTimelineEvent(
            kind: .interacted,
            timestamp: timestamp,
            title: "摸摸头",
            detail: "桌宠收到互动，心情微微上扬。",
            payload: [:]
        )
    }


    public static func equipped(_ item: ItemDefinition, at timestamp: Date = Date()) -> PetTimelineEvent {
        let slotText = item.slot?.title ?? "外观"
        return PetTimelineEvent(
            kind: .equipped,
            timestamp: timestamp,
            title: "装备 \(item.name)",
            detail: "\(item.rarity.title) · \(slotText)",
            payload: [
                "itemID": item.id,
                "itemName": item.name,
                "slot": item.slot?.rawValue ?? "",
                "rarity": item.rarity.rawValue
            ]
        )
    }

    public static func lootDropped(_ drop: LootDrop, at timestamp: Date? = nil) -> PetTimelineEvent {
        let stamp = timestamp ?? drop.timestamp
        let pity = drop.wasPity ? " · 保底" : ""
        let slotBit: String
        if let slot = drop.item.slot {
            slotBit = CompactCopy.slotPlain(slot)
        } else {
            slotBit = drop.item.kind.title
        }
        return PetTimelineEvent(
            kind: .lootDropped,
            timestamp: stamp,
            title: CompactCopy.lootToastTitle(itemName: drop.item.name, quantity: drop.quantity),
            detail: "\(drop.item.rarity.title) · \(slotBit)\(pity)",
            payload: [
                "itemID": drop.item.id,
                "itemName": drop.item.name,
                "rarity": drop.item.rarity.rawValue,
                "source": drop.source.rawValue,
                "quantity": "\(drop.quantity)",
                "wasPity": drop.wasPity ? "1" : "0"
            ]
        )
    }

    private static func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}
