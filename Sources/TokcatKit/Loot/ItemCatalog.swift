import Foundation

/// Built-in item definitions for Phase 3 loot / inventory.
public enum ItemCatalog {
    public static let all: [ItemDefinition] = [
        // MARK: Skins
        ItemDefinition(
            id: "skin_classic",
            name: "经典米杏",
            detail: "默认 Tokcat：暖米白 + 杏橙点缀。",
            kind: .skin,
            rarity: .common,
            systemImage: "cat.fill"
        ),
        ItemDefinition(
            id: "skin_mint",
            name: "青瓷薄荷",
            detail: "内耳同色系拉满，冷静工程师感。",
            kind: .skin,
            rarity: .rare,
            systemImage: "leaf.circle.fill"
        ),
        ItemDefinition(
            id: "skin_midnight",
            name: "午夜编译",
            detail: "深夜机房配色，token 印记更亮。",
            kind: .skin,
            rarity: .epic,
            systemImage: "moon.stars.fill"
        ),

        // MARK: Props
        ItemDefinition(
            id: "prop_token_crumb",
            name: "Token 屑",
            detail: "吃剩的蓝色碎屑，没什么用但很可爱。",
            kind: .prop,
            rarity: .common,
            systemImage: "sparkle"
        ),
        ItemDefinition(
            id: "prop_catnip",
            name: "猫薄荷袋",
            detail: "一小撮本地猫薄荷，闻着就开心。",
            kind: .prop,
            rarity: .common,
            systemImage: "leaf.fill"
        ),
        ItemDefinition(
            id: "prop_yarn_ball",
            name: "毛线球",
            detail: "经典玩具。适合在桌角滚来滚去。",
            kind: .prop,
            rarity: .common,
            systemImage: "circle.circle"
        ),
        ItemDefinition(
            id: "prop_fish_cookie",
            name: "小鱼饼干",
            detail: "香脆一口，喂食后心情会更好一点（心理作用）。",
            kind: .prop,
            rarity: .uncommon,
            systemImage: "fish.fill"
        ),
        ItemDefinition(
            id: "prop_coffee_bean",
            name: "加班咖啡豆",
            detail: "工程师专属口粮。提神，不治本。",
            kind: .prop,
            rarity: .uncommon,
            systemImage: "cup.and.saucer.fill"
        ),
        ItemDefinition(
            id: "prop_sticky_note",
            name: "像素便利贴",
            detail: "写着 TODO: pet the cat。",
            kind: .prop,
            rarity: .uncommon,
            systemImage: "note.text"
        ),
        ItemDefinition(
            id: "prop_usb_mouse",
            name: "迷你 USB 鼠",
            detail: "不是真老鼠。是鼠标。大概。",
            kind: .prop,
            rarity: .common,
            systemImage: "computermouse.fill"
        ),
        ItemDefinition(
            id: "prop_debug_duck",
            name: "调试小黄鸭",
            detail: "对着它讲 bug，有时真的会好。",
            kind: .prop,
            rarity: .rare,
            systemImage: "bird.fill"
        ),
        ItemDefinition(
            id: "prop_error_stack",
            name: "折叠报错条",
            detail: "把 stack trace 折成千纸鹤。治愈力存疑。",
            kind: .prop,
            rarity: .uncommon,
            systemImage: "exclamationmark.triangle.fill"
        ),
        ItemDefinition(
            id: "prop_green_build",
            name: "绿勾徽章碎片",
            detail: "CI 全绿时掉下来的小碎片。",
            kind: .prop,
            rarity: .rare,
            systemImage: "checkmark.circle.fill"
        ),

        // ═══════════════════════════════════════════════
        // MARK: Equipment — rarity ladder
        // Common: look-first, low/no gate
        // Uncommon: one light power + early sequence gate
        // Rare: dual power / pathway lean
        // Epic: strong power + higher sequence
        // Legendary: multi-axis + broad requirements
        // ═══════════════════════════════════════════════

        // --- Head ---
        ItemDefinition(
            id: "eq_pixel_bow",
            name: "像素蝴蝶结",
            detail: "头上绑一朵，立刻软萌 20%。",
            kind: .equipment,
            rarity: .common,
            slot: .head,
            systemImage: "ribbon",
            requirement: StatRequirement(minLevel: 1),
            effect: ItemEffect(menuBarHatID: "hat_bow"),
            menuBarHatID: "hat_bow"
        ),
        ItemDefinition(
            id: "eq_paper_hat",
            name: "便利贴纸帽",
            detail: "紧急会议前随手折的。",
            kind: .equipment,
            rarity: .common,
            slot: .head,
            systemImage: "note.text",
            requirement: StatRequirement(minLevel: 1),
            effect: ItemEffect(menuBarHatID: "hat_paper"),
            menuBarHatID: "hat_paper"
        ),
        ItemDefinition(
            id: "eq_beanie",
            name: "程序员冷帽",
            detail: "凌晨三点的机房标配。",
            kind: .equipment,
            rarity: .uncommon,
            slot: .head,
            systemImage: "crown",
            requirement: StatRequirement(minLevel: 5, minEnergy: 1.5),
            effect: ItemEffect(dropChanceBonus: 0.01, menuBarHatID: "hat_beanie"),
            pathway: .flash,
            menuBarHatID: "hat_beanie",
            setID: .clickStream
        ),
        ItemDefinition(
            id: "eq_headphones",
            name: "降噪耳机",
            detail: "世界安静，只剩敲键盘。",
            kind: .equipment,
            rarity: .uncommon,
            slot: .head,
            systemImage: "headphones",
            requirement: StatRequirement(minLevel: 7, minEnergy: 2),
            effect: ItemEffect(xpMultiplier: 1.01, menuBarHatID: "hat_headphones"),
            pathway: .flash,
            menuBarHatID: "hat_headphones"
        ),
        ItemDefinition(
            id: "eq_night_hood",
            name: "守夜兜帽",
            detail: "炉边守夜人的连帽。",
            kind: .equipment,
            rarity: .rare,
            slot: .head,
            systemImage: "cloud.moon.fill",
            requirement: StatRequirement(minLevel: 14, minVitality: 3.5, requiredPathway: .warden),
            effect: ItemEffect(hungerDecayMultiplier: 0.94, dailyXPSoftCapBonus: 6, menuBarHatID: "hat_hood"),
            pathway: .warden,
            menuBarHatID: "hat_hood",
            setID: .cozyHearth
        ),
        ItemDefinition(
            id: "eq_debug_crown",
            name: "令牌冠",
            detail: "高阶冠徽，权能与外观同在。",
            kind: .equipment,
            rarity: .epic,
            slot: .head,
            systemImage: "crown.fill",
            requirement: StatRequirement(minLevel: 35, minIntelligence: 10),
            effect: ItemEffect(xpMultiplier: 1.05, dropChanceBonus: 0.02, menuBarHatID: "hat_crown"),
            pathway: .reader,
            menuBarHatID: "hat_crown",
            setID: .tokenSanctum
        ),

        // --- Face ---
        ItemDefinition(
            id: "eq_pixel_shades",
            name: "像素墨镜",
            detail: "装酷专用。看不出有没有在看报错。",
            kind: .equipment,
            rarity: .common,
            slot: .face,
            systemImage: "sunglasses",
            requirement: StatRequirement(minLevel: 1),
            effect: ItemEffect()
        ),
        ItemDefinition(
            id: "eq_monocle",
            name: "旁注单片镜",
            detail: "看起来很会 review PR。",
            kind: .equipment,
            rarity: .uncommon,
            slot: .face,
            systemImage: "eyeglasses",
            requirement: StatRequirement(minLevel: 10, minIntelligence: 3, requiredPathway: .reader),
            effect: ItemEffect(rarityWeightBias: 1.15),
            pathway: .reader,
            setID: .diffScholar
        ),
        ItemDefinition(
            id: "eq_code_badge",
            name: "Commit 徽章",
            detail: "今日已 push 的证明。",
            kind: .equipment,
            rarity: .rare,
            slot: .face,
            systemImage: "checkmark.seal.fill",
            requirement: StatRequirement(minLevel: 15, minIntelligence: 4),
            effect: ItemEffect(xpMultiplier: 1.02, rarityWeightBias: 1.05),
            pathway: .reader
        ),
        ItemDefinition(
            id: "eq_focus_visor",
            name: "专注面罩",
            detail: "视野收窄，只剩当前函数。",
            kind: .equipment,
            rarity: .rare,
            slot: .face,
            systemImage: "eye.trianglebadge.exclamationmark",
            requirement: StatRequirement(minLevel: 18, minEnergy: 4, requiredPathway: .flash),
            effect: ItemEffect(xpMultiplier: 1.02, dropChanceBonus: 0.008),
            pathway: .flash
        ),
        ItemDefinition(
            id: "eq_review_goggles",
            name: "审阅护目镜",
            detail: "diff 里的坑都看得更清。",
            kind: .equipment,
            rarity: .epic,
            slot: .face,
            systemImage: "eyeglasses",
            requirement: StatRequirement(minLevel: 30, minIntelligence: 8, requiredPathway: .reader),
            effect: ItemEffect(xpMultiplier: 1.03, rarityWeightBias: 1.12),
            pathway: .reader
        ),

        // --- Back ---
        ItemDefinition(
            id: "eq_tiny_backpack",
            name: "迷你双肩包",
            detail: "装得下半袋猫薄荷和一整袋 TODO。",
            kind: .equipment,
            rarity: .common,
            slot: .back,
            systemImage: "bag.fill",
            requirement: StatRequirement(minLevel: 1),
            effect: ItemEffect()
        ),
        ItemDefinition(
            id: "eq_soft_scarf",
            name: "炉边围巾",
            detail: "围上之后打字都更暖一点。",
            kind: .equipment,
            rarity: .uncommon,
            slot: .back,
            systemImage: "wind",
            requirement: StatRequirement(minLevel: 8, minVitality: 2.5),
            effect: ItemEffect(hungerDecayMultiplier: 0.9),
            pathway: .warden,
            setID: .cozyHearth
        ),
        ItemDefinition(
            id: "eq_diff_cape",
            name: "旁注披肩",
            detail: "书斋气场，适合长文 review。",
            kind: .equipment,
            rarity: .rare,
            slot: .back,
            systemImage: "book.closed.fill",
            requirement: StatRequirement(minLevel: 16, minIntelligence: 4, requiredPathway: .reader),
            effect: ItemEffect(xpMultiplier: 1.015, rarityWeightBias: 1.06),
            pathway: .reader,
            setID: .diffScholar
        ),
        ItemDefinition(
            id: "eq_cape",
            name: "调试披风",
            detail: "bug 见了都要绕道。",
            kind: .equipment,
            rarity: .rare,
            slot: .back,
            systemImage: "flag.fill",
            requirement: StatRequirement(minLevel: 20, minVitality: 5),
            effect: ItemEffect(hungerDecayMultiplier: 0.95, dailyXPSoftCapBonus: 15),
            pathway: .warden
        ),
        ItemDefinition(
            id: "eq_signal_cloak",
            name: "信号披风",
            detail: "像有条稳定的连接在身后。",
            kind: .equipment,
            rarity: .epic,
            slot: .back,
            systemImage: "wifi",
            requirement: StatRequirement(minLevel: 28, minVitality: 7, minEnergy: 5),
            effect: ItemEffect(dropChanceBonus: 0.008, hungerDecayMultiplier: 0.93, dailyXPSoftCapBonus: 18),
            pathway: .warden
        ),

        // --- Held ---
        ItemDefinition(
            id: "eq_fish_rod",
            name: "逗鱼竿",
            detail: "其实是自己逗自己。",
            kind: .equipment,
            rarity: .common,
            slot: .held,
            systemImage: "line.diagonal",
            requirement: StatRequirement(minLevel: 1),
            effect: ItemEffect()
        ),
        ItemDefinition(
            id: "eq_rubber_duck",
            name: "手持小黄鸭",
            detail: "把 bug 讲给它听。",
            kind: .equipment,
            rarity: .common,
            slot: .held,
            systemImage: "bird.fill",
            requirement: StatRequirement(minLevel: 2),
            effect: ItemEffect()
        ),
        ItemDefinition(
            id: "eq_keycap_charm",
            name: "键帽挂饰",
            detail: "咔哒一下，手感线吉祥物。",
            kind: .equipment,
            rarity: .uncommon,
            slot: .held,
            systemImage: "computermouse",
            requirement: StatRequirement(minLevel: 6, minEnergy: 1.8),
            effect: ItemEffect(xpMultiplier: 1.01, dropChanceBonus: 0.005),
            pathway: .flash,
            setID: .clickStream
        ),
        ItemDefinition(
            id: "eq_mini_keyboard",
            name: "迷你键盘",
            detail: "前爪专用 60%。咔哒咔哒。",
            kind: .equipment,
            rarity: .rare,
            slot: .held,
            systemImage: "keyboard",
            requirement: StatRequirement(minLevel: 12, minEnergy: 3.5),
            effect: ItemEffect(xpMultiplier: 1.03),
            pathway: .flash,
            setID: .clickStream
        ),
        ItemDefinition(
            id: "eq_night_lantern",
            name: "续灯小炉",
            detail: "守夜人桌角的暖光。",
            kind: .equipment,
            rarity: .rare,
            slot: .held,
            systemImage: "lantern.fill",
            requirement: StatRequirement(minLevel: 18, minVitality: 4.5, requiredPathway: .warden),
            effect: ItemEffect(hungerDecayMultiplier: 0.92, dailyXPSoftCapBonus: 8),
            pathway: .warden,
            setID: .cozyHearth
        ),
        ItemDefinition(
            id: "eq_annotation_quill",
            name: "旁注羽笔",
            detail: "写在 diff 边上的细笔。",
            kind: .equipment,
            rarity: .rare,
            slot: .held,
            systemImage: "pencil.and.outline",
            requirement: StatRequirement(minLevel: 16, minIntelligence: 4, requiredPathway: .reader),
            effect: ItemEffect(xpMultiplier: 1.02, rarityWeightBias: 1.08),
            pathway: .reader,
            setID: .diffScholar
        ),
        ItemDefinition(
            id: "eq_tablet_slate",
            name: "像素石板",
            detail: "随身记 issue 的小板。",
            kind: .equipment,
            rarity: .epic,
            slot: .held,
            systemImage: "rectangle.and.pencil.and.ellipsis",
            requirement: StatRequirement(minLevel: 26, minIntelligence: 6, minEnergy: 5),
            effect: ItemEffect(xpMultiplier: 1.025, dropChanceBonus: 0.01, dailyXPSoftCapBonus: 10)
        ),

        // --- Aura ---
        ItemDefinition(
            id: "eq_soft_glow",
            name: "柔光点",
            detail: "一点点环绕高光，克制不晃眼。",
            kind: .equipment,
            rarity: .common,
            slot: .aura,
            systemImage: "circle.dotted",
            requirement: StatRequirement(minLevel: 3),
            effect: ItemEffect()
        ),
        ItemDefinition(
            id: "eq_focus_ring",
            name: "专注环",
            detail: "坐下干活时会轻轻亮一下。",
            kind: .equipment,
            rarity: .uncommon,
            slot: .aura,
            systemImage: "circle.circle",
            requirement: StatRequirement(minLevel: 9, minEnergy: 2.5),
            effect: ItemEffect(xpMultiplier: 1.01),
            pathway: .flash
        ),
        ItemDefinition(
            id: "eq_spark_aura",
            name: "编译光环",
            detail: "成功编译时会闪一下（克制版）。",
            kind: .equipment,
            rarity: .epic,
            slot: .aura,
            systemImage: "sparkles",
            requirement: StatRequirement(minLevel: 25, minIntelligence: 5, minEnergy: 4),
            effect: ItemEffect(xpMultiplier: 1.02, dropChanceBonus: 0.01)
        ),
        ItemDefinition(
            id: "eq_compile_aura",
            name: "调律光环",
            detail: "三途均衡时才会完全点亮。",
            kind: .equipment,
            rarity: .epic,
            slot: .aura,
            systemImage: "sparkles",
            requirement: StatRequirement(minLevel: 50, minAllStats: 9),
            effect: ItemEffect(xpMultiplier: 1.02, dailyXPSoftCapBonus: 25),
            setID: .tokenSanctum
        ),
        ItemDefinition(
            id: "eq_golden_token",
            name: "金色 Token 印",
            detail: "传说中的印记，亮到有点不好意思。",
            kind: .equipment,
            rarity: .legendary,
            slot: .aura,
            systemImage: "hexagon.fill",
            requirement: StatRequirement(minLevel: 55, minAllStats: 11),
            effect: ItemEffect(
                xpMultiplier: 1.04,
                dropChanceBonus: 0.02,
                rarityWeightBias: 1.1,
                dailyXPSoftCapBonus: 20
            ),
            setID: .tokenSanctum
        ),
        ItemDefinition(
            id: "eq_origin_seal",
            name: "源响圣印",
            detail: "序列尽头才会共鸣的印记。",
            kind: .equipment,
            rarity: .legendary,
            slot: .face,
            systemImage: "seal.fill",
            requirement: StatRequirement(minLevel: 60, minAllStats: 12),
            effect: ItemEffect(
                xpMultiplier: 1.04,
                dropChanceBonus: 0.015,
                rarityWeightBias: 1.12,
                hungerDecayMultiplier: 0.95,
                dailyXPSoftCapBonus: 15
            )
        )
    ]

    private static let byID: [String: ItemDefinition] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    public static func item(id: String) -> ItemDefinition? {
        byID[id]
    }

    public static func items(kind: ItemKind) -> [ItemDefinition] {
        all.filter { $0.kind == kind }
    }

    public static func items(rarity: Rarity) -> [ItemDefinition] {
        all.filter { $0.rarity == rarity }
    }

    public static var skins: [ItemDefinition] {
        items(kind: .skin)
    }

    public static var equipmentItems: [ItemDefinition] {
        items(kind: .equipment)
    }

    public static var props: [ItemDefinition] {
        items(kind: .prop)
    }

    public static var sets: [GearSetDefinition] {
        GearSetCatalog.all
    }

    /// Pool used for feed / pity drops (props + equipment + rare skins).
    public static var droppable: [ItemDefinition] {
        all.filter { item in
            switch item.kind {
            case .prop, .equipment: return true
            case .skin: return item.id != PetAppearanceState.defaultSkinID
            }
        }
    }

    /// Smaller, friendlier pool for guaranteed level-up gifts.
    public static var levelUpPool: [ItemDefinition] {
        droppable.filter { $0.rarity <= .rare }
    }
}
