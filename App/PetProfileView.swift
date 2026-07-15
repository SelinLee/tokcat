import SwiftUI
import TokcatKit

/// Game-style pet character sheet: hero preview, vitals, stats, pathways, seals.
struct PetProfileView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showMaintenance = false
    /// `nil` = follow live pet status pose; otherwise showcase a clip.
    @State private var showcaseClip: PixelPetClip? = nil
    @State private var showcaseReplayToken = 0

    private var snapshot: PetProgressSnapshot { model.petProgress }
    private var state: PetState { snapshot.state }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 780
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                if wide {
                    HStack(alignment: .top, spacing: 14) {
                        leftColumn
                            .frame(width: min(340, geo.size.width * 0.40))
                        rightColumn
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            heroPanel
                            vitalsPanel
                            statsPanel
                            pathwayPanel
                            questPanel
                            feedPanel
                            timelinePanel
                            sealsPanel
                            guidePanel
                            if showMaintenance {
                                maintenancePanel
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .background(GameUITheme.windowBackground)
    }

    // MARK: - Layout columns (wide)

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heroPanel
                vitalsPanel
                feedPanel
                guidePanel
            }
        }
    }

    private var rightColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statsPanel
                pathwayPanel
                questPanel
                timelinePanel
                sealsPanel
                if showMaintenance {
                    maintenancePanel
                }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                GameScreenTitle(title: "宠物", subtitle: "CHARACTER", icon: "cat.fill")
                Spacer()
                hudChips
                maintenanceButton
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    GameScreenTitle(title: "宠物", subtitle: "CHARACTER", icon: "cat.fill")
                    Spacer()
                    maintenanceButton
                }
                hudChips
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var hudChips: some View {
        HStack(spacing: 8) {
            GameHUDChip(
                title: "等级",
                value: CompactCopy.levelLabel(state.level),
                tint: GameUITheme.token
            )
            GameHUDChip(
                title: "序列",
                value: "S\(ManifestTier.sequenceLabel(for: state.level))",
                tint: GameUITheme.innerEar
            )
            GameHUDChip(
                title: "阶段",
                value: snapshot.manifestTier.plainTitle,
                tint: GameUITheme.accent
            )
            GameHUDChip(
                title: "连续",
                value: "\(state.streakDays) 天",
                tint: state.streakDays > 0 ? GameUITheme.flash : .secondary
            )
        }
    }

    private var maintenanceButton: some View {
        Button {
            if reduceMotion {
                showMaintenance.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showMaintenance.toggle()
                }
            }
        } label: {
            Image(systemName: showMaintenance ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
                .font(.title3)
                .foregroundStyle(showMaintenance ? GameUITheme.token : .secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("维护")
        .accessibilityLabel("宠物维护")
        .accessibilityValue(showMaintenance ? "已展开" : "已收起")
        .accessibilityHint(showMaintenance ? "收起维护操作" : "展开维护操作")
    }

    // MARK: - Hero panel

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            GamePanelHeader(title: "角色", subtitle: "HERO", icon: "person.crop.square.fill")

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [GameUITheme.stageTop, GameUITheme.stageBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(GameUITheme.frameStroke, lineWidth: 1.5)
                    )

                VStack {
                    Spacer()
                    Ellipse()
                        .fill(showcaseTint.opacity(0.16))
                        .frame(height: 40)
                        .blur(radius: 10)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 14)
                }

                HStack(alignment: .center, spacing: 14) {
                    VStack(spacing: 8) {
                        PixelPetPreviewView(
                            stage: PetStage.stage(for: state.level),
                            status: snapshot.status,
                            skinItemID: model.activeSkinItemID,
                            loadout: model.equipment,
                            animating: !reduceMotion,
                            forcedClip: showcaseClip,
                            replayToken: showcaseReplayToken,
                            activity: model.menuBarActivity
                        )
                        .frame(width: 128, height: 148)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Quick replay / interact when tapping the figure.
                            if showcaseClip == nil {
                                selectShowcase(.interact)
                            } else if showcaseClip?.isOneShot == true {
                                showcaseReplayToken &+= 1
                            } else {
                                // Toggle back to live for ambient locks on second pet tap.
                                selectShowcase(nil)
                            }
                        }
                        .help(showcaseClip == nil ? "点击预览互动动作" : "点击重播 / 返回实时状态")

                        Text(showcaseCaption)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(GameUITheme.secondaryText)
                            .lineLimit(1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Tokcat")
                                .font(.title3.weight(.bold))
                            statusBadge
                        }

                        Text(snapshot.sequenceTitleLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GameUITheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(showcaseDetail)
                            .font(.caption)
                            .foregroundStyle(GameUITheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(3)

                        HStack(spacing: 6) {
                            miniTag(
                                title: ItemCatalog.item(id: model.activeSkinItemID)?.name ?? "经典米杏",
                                icon: "paintpalette.fill",
                                tint: GameUITheme.accent
                            )
                            if let hat = model.activeBonuses.menuBarHatID {
                                miniTag(
                                    title: GearPresentation.menuBarHatLabel(hat),
                                    icon: "crown.fill",
                                    tint: GameUITheme.token
                                )
                            }
                        }

                        GameTokenPacketRail(
                            progress: snapshot.xpProgress,
                            title: CompactCopy.xpTitlePlain,
                            value: CompactCopy.xpProgressLine(current: state.xp, needed: snapshot.xpToNextLevel),
                            tint: GameUITheme.token,
                            trailingTint: GameUITheme.accent
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
            .frame(minHeight: 190)

            actionShowcaseBar
        }
        .gamePanel()
    }

    private var showcaseCaption: String {
        if let showcaseClip {
            return "展示 · \(showcaseClip.displayTitle)"
        }
        return "实时 · \(snapshot.status.title)"
    }

    private var showcaseDetail: String {
        if let showcaseClip {
            return "正在预览「\(showcaseClip.displayTitle)」动作。点选下方芯片切换；点「实时」回到当前状态。"
        }
        return snapshot.status.detail
    }

    private var showcaseTint: Color {
        guard showcaseClip != nil else { return statusTint }
        return GameUITheme.token
    }

    private var actionShowcaseBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("动作展示", systemImage: "figure.cooldown")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GameUITheme.secondaryText)
                Spacer(minLength: 0)
                if showcaseClip != nil {
                    Button {
                        selectShowcase(nil)
                    } label: {
                        Label("实时", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(GameUITheme.accent)
                    .background(GameUITheme.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(GameUITheme.accent.opacity(0.28), lineWidth: 1))
                    .help("返回实时状态动作")

                    if showcaseClip?.isOneShot == true {
                        Button {
                            showcaseReplayToken &+= 1
                        } label: {
                            Label("重播", systemImage: "arrow.clockwise")
                                .font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(GameUITheme.token)
                        .background(GameUITheme.token.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(GameUITheme.token.opacity(0.28), lineWidth: 1))
                        .help("重新播放当前一次性动作")
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PixelPetClip.showcaseOrder, id: \.self) { clip in
                        actionChip(clip)
                    }
                }
            }
            .accessibilityLabel("宠物动作列表")
        }
    }

    private func actionChip(_ clip: PixelPetClip) -> some View {
        let selected = showcaseClip == clip
        return Button {
            if selected {
                if clip.isOneShot {
                    showcaseReplayToken &+= 1
                } else {
                    // Second tap on a looping pose returns to live.
                    selectShowcase(nil)
                }
            } else {
                selectShowcase(clip)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: clip.systemImage)
                    .font(.caption2.weight(.bold))
                Text(clip.displayTitle)
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : GameUITheme.primaryText)
            .background(
                Capsule().fill(selected ? GameUITheme.token : GameUITheme.stageTop.opacity(0.9))
            )
            .overlay(
                Capsule().strokeBorder(
                    selected ? GameUITheme.token : GameUITheme.frameStroke,
                    lineWidth: selected ? 0 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .help("预览 \(clip.displayTitle)")
        .accessibilityLabel(clip.displayTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? "再次点击可重播或返回实时" : "预览该动作")
    }

    private func selectShowcase(_ clip: PixelPetClip?) {
        showcaseClip = clip
        if clip != nil {
            showcaseReplayToken &+= 1
        }
    }

    private var statusBadge: some View {
        Label(snapshot.status.title, systemImage: snapshot.status.systemImage)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(statusTint)
            .background(statusTint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(statusTint.opacity(0.28), lineWidth: 1))
    }

    private var statusTint: Color {
        switch snapshot.status {
        case .celebrating: return GameUITheme.gold
        case .hungry: return .orange
        case .sleepy: return .secondary
        case .excited: return GameUITheme.flash
        case .focused: return GameUITheme.token
        case .reviewing: return GameUITheme.token.opacity(0.85)
        case .waiting: return .yellow
        case .failed: return .red.opacity(0.75)
        case .lowEnergy: return .gray
        case .happy: return GameUITheme.innerEar
        case .content: return GameUITheme.accent
        case .sad: return .blue.opacity(0.7)
        }
    }

    // MARK: - Vitals

    private var vitalsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            GamePanelHeader(title: "状态", subtitle: "VITALS", icon: "heart.fill")

            HStack(spacing: 10) {
                vitalRing(
                    title: "心情",
                    value: state.mood,
                    detail: moodLabel,
                    tint: moodTint,
                    icon: "face.smiling"
                )
                vitalRing(
                    title: "饱食",
                    value: state.hunger,
                    detail: hungerLabel,
                    tint: hungerTint,
                    icon: "fork.knife"
                )
                vitalRing(
                    title: "连续",
                    value: min(1, Double(state.streakDays) / 30.0),
                    detail: streakLabel,
                    tint: GameUITheme.flash,
                    icon: "flame.fill",
                    centerText: "\(state.streakDays)"
                )
            }
        }
        .gamePanel()
    }

    private func vitalRing(
        title: String,
        value: Double,
        detail: String,
        tint: Color,
        icon: String,
        centerText: String? = nil
    ) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(GameUITheme.insetFill, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, max(0, value)))
                    .stroke(
                        AngularGradient(colors: [tint.opacity(0.7), tint], center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Image(systemName: icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                    Text(centerText ?? "\(Int((value * 100).rounded()))%")
                        .font(.caption.weight(.bold).monospacedDigit())
                }
            }
            .frame(width: 72, height: 72)

            Text(title)
                .font(.caption.weight(.bold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(GameUITheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GameUITheme.insetFill)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(centerText ?? "\(Int((value * 100).rounded()))%")，\(detail)")
    }

    // MARK: - Stats

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GamePanelHeader(title: "三围", subtitle: "STATS", icon: "chart.bar.fill")
                Spacer()
                Text(snapshot.pathwayFocus.summaryLine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(GameUITheme.secondaryText)
                    .lineLimit(1)
            }

            attributeRow(
                stat: .intelligence,
                value: state.stats.intelligence,
                tint: GameUITheme.reader,
                hint: "高价模型喂聪明更快"
            )
            attributeRow(
                stat: .vitality,
                value: state.stats.vitality,
                tint: GameUITheme.warden,
                hint: "连续写码 / 勤回来 → 稳定"
            )
            attributeRow(
                stat: .energy,
                value: state.stats.energy,
                tint: GameUITheme.flash,
                hint: "低延迟响应抬高手感"
            )

            if model.activeBonuses.hasAnyPower || !model.activeBonuses.activeSets.isEmpty {
                Divider().opacity(0.35)
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

                    if !model.activeBonuses.activeSets.isEmpty {
                        ForEach(model.activeBonuses.activeSets.prefix(3)) { set in
                            HStack(spacing: 6) {
                                Image(systemName: set.setID.systemImage)
                                    .font(.caption2)
                                    .foregroundStyle(
                                        set.unlockedTierTitles.isEmpty
                                        ? Color.secondary
                                        : GameUITheme.innerEar
                                    )
                                Text(set.detailLine)
                                    .font(.caption2)
                                    .foregroundStyle(GameUITheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(GameUITheme.insetFill)
                )
            }
        }
        .gamePanel()
    }

    private func attributeRow(
        stat: CompactCopy.Stat,
        value: Double,
        tint: Color,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(stat.plainWithLore, systemImage: statIcon(stat))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Spacer()
                Text(String(format: "%.1f", value))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(GameUITheme.primaryText)
            }
            GameXPBar(progress: attributeProgress(value), tint: tint, height: 8)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(GameUITheme.secondaryText)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func statIcon(_ stat: CompactCopy.Stat) -> String {
        switch stat {
        case .intelligence: return "brain.head.profile"
        case .vitality: return "leaf.fill"
        case .energy: return "bolt.fill"
        }
    }

    // MARK: - Pathways

    private var pathwayPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            GamePanelHeader(title: "成长线", subtitle: "PATHS", icon: "point.3.connected.trianglepath.dotted")

            HStack(spacing: 8) {
                ForEach(PathwayID.allCases) { path in
                    pathwayCard(path)
                }
            }
        }
        .gamePanel()
    }

    private func pathwayCard(_ path: PathwayID) -> some View {
        let gate = model.pathwayProgress.gate(for: path)
        let tint = GameUITheme.pathwayColor(path)
        let title = PathwayLore.highestTitle(
            pathway: path,
            level: state.level,
            stat: path.stat.value(in: state.stats)
        )
        let unlocked = gate != .locked

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: pathwayIcon(path))
                    .foregroundStyle(unlocked ? tint : GameUITheme.mutedText)
                Spacer()
                Text(gate.plainTitle)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(unlocked ? tint : GameUITheme.secondaryText)
                    .background((unlocked ? tint : GameUITheme.mutedText).opacity(0.14), in: Capsule())
            }

            Text(path.plainLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(unlocked ? GameUITheme.primaryText : .secondary)

            Text(title.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(unlocked ? tint : .secondary)
                .lineLimit(1)

            Text(String(format: "%@ %.1f", path.stat.plain, path.stat.value(in: state.stats)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(GameUITheme.secondaryText)

            GameXPBar(
                progress: pathwayProgressValue(path),
                tint: unlocked ? tint : .secondary.opacity(0.4),
                height: 6
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GameUITheme.insetFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(unlocked ? tint.opacity(0.35) : GameUITheme.frameStroke, lineWidth: unlocked ? 1.5 : 1)
                )
        )
        .opacity(unlocked ? 1 : 0.78)
    }

    private func pathwayIcon(_ path: PathwayID) -> String {
        switch path {
        case .reader: return "book.fill"
        case .warden: return "flame.fill"
        case .flash: return "bolt.horizontal.fill"
        }
    }

    private func pathwayProgressValue(_ path: PathwayID) -> Double {
        // Soft progress toward high-seat-ish values (Lv75/stat20 is far; use log scale).
        let levelPart = min(1, Double(state.level) / 50.0)
        let statPart = min(1, path.stat.value(in: state.stats) / 13.0)
        return min(1, levelPart * 0.45 + statPart * 0.55)
    }

    // MARK: - Next unlock / quests

    private var questPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            GamePanelHeader(title: "下一目标", subtitle: "QUESTS", icon: "flag.fill")

            if model.pathwayProgress.nextUnlockHints.isEmpty {
                emptyHint("暂时没有新的解锁目标。继续喂 token 推进序列。")
            } else {
                ForEach(Array(model.pathwayProgress.nextUnlockHints.prefix(4).enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text(String(format: "%02d", index + 1))
                            .font(.caption2.weight(.black).monospacedDigit())
                            .foregroundStyle(GameUITheme.token)
                            .frame(width: 20, height: 20)
                            .background(GameUITheme.token.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(line)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(GameUITheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(GameUITheme.insetFill)
                    )
                }
            }
        }
        .gamePanel()
    }

    // MARK: - Feed

    private var feedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            GamePanelHeader(title: "今日喂食", subtitle: "FEED", icon: "fork.knife.circle.fill")

            HStack(spacing: 8) {
                feedStat(title: "Tokens", value: formatTokens(snapshot.todayTokensFed), tint: GameUITheme.token)
                feedStat(title: "费用", value: String(format: "$%.4f", snapshot.todayCostUSD), tint: GameUITheme.accent)
                feedStat(title: "累计", value: formatTokens(state.totalTokensFed), tint: GameUITheme.innerEar)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近一口")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GameUITheme.secondaryText)
                    Text(latestFeedText)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
                Spacer()
                if let last = state.lastFedAt {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("上次喂食")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(GameUITheme.secondaryText)
                        Text(last, style: .relative)
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GameUITheme.insetFill)
            )
        }
        .gamePanel()
    }

    private func feedStat(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(GameUITheme.secondaryText)
            Text(value)
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(tint.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Timeline

    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GamePanelHeader(title: "最近事件", subtitle: "LOG", icon: "list.bullet.rectangle")
                Spacer()
                Text("\(model.recentPetEvents.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(GameUITheme.secondaryText)
            }

            if model.recentPetEvents.isEmpty {
                emptyHint("还没有演出事件。喂食、升级、互动会出现在这里。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.recentPetEvents.prefix(8).enumerated()), id: \.element.id) { index, event in
                        timelineRow(event)
                        if index < min(7, model.recentPetEvents.prefix(8).count - 1) {
                            Divider().opacity(0.25).padding(.leading, 28)
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(GameUITheme.insetFill)
                )
            }
        }
        .gamePanel()
    }

    private func timelineRow(_ event: PetTimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(timelineTint(event.kind).opacity(0.16))
                    .frame(width: 24, height: 24)
                Image(systemName: event.kind.systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(timelineTint(event.kind))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.kind.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(timelineTint(event.kind))
                    Spacer()
                    Text(event.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(GameUITheme.secondaryText)
                }
                Text(event.title)
                    .font(.caption.weight(.semibold))
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(.caption2)
                        .foregroundStyle(GameUITheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private func timelineTint(_ kind: PetEventKind) -> Color {
        switch kind {
        case .fed: return GameUITheme.warden
        case .levelUp: return GameUITheme.gold
        case .achievement: return GameUITheme.reader
        case .interacted: return .pink
        case .statusChanged: return .secondary
        case .lootDropped: return GameUITheme.flash
        case .equipped: return GameUITheme.token
        }
    }

    // MARK: - Seals / achievements

    private var sealsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GamePanelHeader(
                    title: CompactCopy.achievementSectionTitle,
                    subtitle: "SEALS",
                    icon: "seal.fill"
                )
                Spacer()
                Text("\(state.unlockedAchievements.count)/\(PetAchievementCatalog.all.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(GameUITheme.token)
            }

            let unlockedIDs = Set(state.unlockedAchievements)
            let unlocked = PetAchievementCatalog.all.filter { unlockedIDs.contains($0.id) }
            let locked = PetAchievementCatalog.all.filter { !unlockedIDs.contains($0.id) }

            if unlocked.isEmpty {
                emptyHint("还没有证印。先喂第一口 token 吧。")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(unlocked.prefix(8)) { item in
                        sealTile(item, unlocked: true)
                    }
                }
            }

            if !locked.isEmpty {
                Text("下一目标")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GameUITheme.secondaryText)
                    .padding(.top, 2)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(locked.prefix(4)) { item in
                        sealTile(item, unlocked: false)
                    }
                }
            }
        }
        .gamePanel()
    }

    private func sealTile(_ item: PetAchievement, unlocked: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(unlocked ? GameUITheme.token.opacity(0.14) : GameUITheme.insetFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                unlocked ? GameUITheme.token.opacity(0.35) : GameUITheme.frameStroke,
                                lineWidth: 1
                            )
                    )
                Image(systemName: item.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(unlocked ? GameUITheme.token : GameUITheme.mutedText)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(unlocked ? GameUITheme.primaryText : .secondary)
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(GameUITheme.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GameUITheme.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(GameUITheme.frameStroke, lineWidth: 1)
                )
        )
        .opacity(unlocked ? 1 : 0.72)
    }

    // MARK: - Guide

    private var guidePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            GamePanelHeader(title: "喂养建议", subtitle: "TIPS", icon: "lightbulb.fill")

            Text(snapshot.feedingHint)
                .font(.caption.weight(.medium))
                .foregroundStyle(GameUITheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(GameUITheme.accent.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(GameUITheme.accent.opacity(0.22), lineWidth: 1)
                        )
                )

            if let modelName = snapshot.latestModel {
                modelPlayLines(for: modelName)
            }
        }
        .gamePanel()
    }

    @ViewBuilder
    private func modelPlayLines(for modelName: String) -> some View {
        modelPlayLinesContent(TokenEconomy().modelProfile(forModel: modelName))
    }

    @ViewBuilder
    private func modelPlayLinesContent(_ profile: ModelProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CompactCopy.modelPlayHint(for: profile))
                .font(.caption.weight(.semibold))
            Text(profile.plainSummary + "（" + profile.loreSummary + "）")
                .font(.caption2)
                .foregroundStyle(GameUITheme.secondaryText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(GameUITheme.insetFill)
        )
    }

    // MARK: - Maintenance

    private var maintenancePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            GamePanelHeader(title: "维护", subtitle: "SYSTEM", icon: "wrench.and.screwdriver")

            Text("只重置宠物等级/三围/成就/连续天数/背包掉落，不影响用量统计与费用历史。")
                .font(.caption)
                .foregroundStyle(GameUITheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    model.resetPetProgress()
                } label: {
                    Label("重置宠物进度", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GameSecondaryButtonStyle())

                if model.canRecomputeGrowthBalance {
                    Button {
                        model.recomputeGrowthToBalanceV2(force: true)
                    } label: {
                        Label("按 v2 重算", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GamePrimaryButtonStyle(enabled: true))
                }
            }

            if model.canRecomputeGrowthBalance {
                Text("按累计 token 以新平衡重算等级与三围；背包与装备保留。")
                    .font(.caption2)
                    .foregroundStyle(GameUITheme.secondaryText)
            } else {
                Text("成长规则已是 v2，无需重算。")
                    .font(.caption2)
                    .foregroundStyle(GameUITheme.secondaryText)
            }
        }
        .gamePanel()
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Bits

    private func miniTag(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(GameUITheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GameUITheme.insetFill)
            )
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func attributeProgress(_ value: Double) -> Double {
        min(1, log1p(max(0, value)) / log1p(120))
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private var moodLabel: String {
        if state.mood > 0.7 { return "很开心" }
        if state.mood < 0.35 { return "有点低落" }
        return "还不错"
    }

    private var hungerLabel: String {
        if state.hunger < 0.25 { return "急需喂食" }
        if state.hunger < 0.55 { return "有点饿" }
        return "吃得饱"
    }

    private var streakLabel: String {
        state.streakDays > 0 ? "保持中" : "今天开张"
    }

    private var moodTint: Color {
        if state.mood > 0.7 { return GameUITheme.innerEar }
        if state.mood < 0.35 { return .blue.opacity(0.75) }
        return GameUITheme.token
    }

    private var hungerTint: Color {
        if state.hunger < 0.25 { return .orange }
        if state.hunger < 0.55 { return GameUITheme.flash }
        return GameUITheme.warden
    }

    private var latestFeedText: String {
        let modelName = snapshot.latestModel.map(ModelNameFormatting.shortDisplayName) ?? "—"
        let source = snapshot.latestSource?.displayName ?? "—"
        return "\(source) · \(modelName)"
    }
}
