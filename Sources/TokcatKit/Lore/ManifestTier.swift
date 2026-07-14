import Foundation

/// Presentation growth tier (显化阶) replacing outward "幼/成/老猫" narrative.
public enum ManifestTier: String, Codable, CaseIterable, Sendable, Identifiable {
    case spark
    case initiate
    case formed
    case sanctum
    case nearDivine
    case sovereign

    public var id: String { rawValue }

    /// 明文阶段
    public var plainTitle: String {
        switch self {
        case .spark: return "新手"
        case .initiate: return "入门"
        case .formed: return "进阶"
        case .sanctum: return "高阶"
        case .nearDivine: return "巅峰"
        case .sovereign: return "满阶"
        }
    }

    /// 密契显化
    public var loreTitle: String {
        switch self {
        case .spark: return "初契·显影"
        case .initiate: return "入途·启灵"
        case .formed: return "定契·成形"
        case .sanctum: return "高座·显圣"
        case .nearDivine: return "近神·权柄"
        case .sovereign: return "座上·令主"
        }
    }

    public var detail: String {
        switch self {
        case .spark: return "Lv.1–9：初契显影，体型更轻。"
        case .initiate: return "Lv.10–19：入途启灵，开始分支。"
        case .formed: return "Lv.20–34：定契成形，装备与途径展开。"
        case .sanctum: return "Lv.35–54：高座显圣，高阶器物。"
        case .nearDivine: return "Lv.55–74：近神权柄，长线追求。"
        case .sovereign: return "Lv.75+：座上令主，满阶追求。"
        }
    }

    /// Approximate stage accent (hex without #) for UI tinting.
    public var accentHex: String {
        switch self {
        case .spark: return "9CA3AF"
        case .initiate: return "34D399"
        case .formed: return "60A5FA"
        case .sanctum: return "C084FC"
        case .nearDivine: return "FBBF24"
        case .sovereign: return "F59E0B"
        }
    }

    public static func tier(for level: Int) -> ManifestTier {
        let lv = max(1, level)
        switch lv {
        case 1...9: return .spark
        case 10...19: return .initiate
        case 20...34: return .formed
        case 35...54: return .sanctum
        case 55...74: return .nearDivine
        default: return .sovereign
        }
    }

    /// Sequence display number 9…0 (higher rank → lower sequence).
    public static func sequenceLabel(for level: Int) -> Int {
        let lv = max(1, level)
        switch lv {
        case 1...4: return 9
        case 5...9: return 8
        case 10...14: return 7
        case 15...19: return 6
        case 20...27: return 5
        case 28...34: return 4
        case 35...44: return 3
        case 45...54: return 2
        case 55...74: return 1
        default: return 0
        }
    }

    /// Map to legacy 3-tier visual stage used by pixel/3D pipelines.
    public var legacyStage: PetStage {
        switch self {
        case .spark, .initiate: return .kitten
        case .formed: return .adult
        case .sanctum, .nearDivine, .sovereign: return .elder
        }
    }
}

public extension PetStage {
    /// Prefer plain ManifestTier titles for outward copy.
    var plainManifestTitle: String {
        switch self {
        case .kitten: return ManifestTier.spark.plainTitle
        case .adult: return ManifestTier.formed.plainTitle
        case .elder: return ManifestTier.sanctum.plainTitle
        }
    }

    static func stage(forManifest tier: ManifestTier) -> PetStage {
        tier.legacyStage
    }
}
