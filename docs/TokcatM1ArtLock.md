# Tokcat V3 形象锁定与全量生产

## 锁定结论（2026-07-18）

**V3**：纯黑身体 + 白耳内 + Luna 大白眼（黑瞳）+ 黑色嘴鼻；无青、无月亮。

主文件：
- `docs/assets/ai_gen_test/m1_v3_full/master/V3_master.png`
- 128：`.../V3_master_128.png`
- skill 示例：`~/.codex/skills/tokcat-ai-art/assets/examples/V3_master_360.png`

## 全量生产状态：✅ 完成（90/90）

| 路径 | 内容 |
|------|------|
| `docs/assets/ai_gen_test/m1_v3_full/raw/` | BotCF 原图 ×90 |
| `docs/assets/ai_gen_test/m1_v3_full/frames128/` | 透明 128 ×90+ |
| `docs/assets/ai_gen_test/m1_v3_full/sheets/` | 分 clip contact sheet + overview |
| `App/Resources/Sprites/TokcatPixel/` | 运行时 base frames |
| `App/Resources/Sprites/TokcatPixel/gear/` | V3 装备层 |
| `frames128/skin_*.png` | 皮肤（mint / midnight） |

### Clip 帧数（与 manifest 对齐）

```
idle4 happy3 sad3 wave4 interact3 jump5 level_up5
working4 review6 waiting4 failed4 sleepy3 rest4
hungry3 eating4 pace8 groom4 look_around6
```

### Extra

- scenes: `scene_desk` `scene_desk_0` `scene_desk_1` `scene_bowl`
- gear: `eq_beanie` `eq_soft_scarf` `eq_rubber_duck` `eq_headphones` `eq_monocle` `eq_cape` `eq_spark_aura`
- skins: `skin_mint` `skin_midnight`

报告：`docs/assets/ai_gen_test/m1_v3_full/PRODUCTION_REPORT.json`

## Skill

`~/.codex/skills/tokcat-ai-art/` — art bible / prompts / workflow 已切 **V3**。
默认参考：`assets/examples/V3_master_360.png`。

## 再生 / Resume

```bash
export BOTCF_API_KEY=...
python3 /tmp/tokcat_v3full/resume_py.py   # 跳过已有 raw
python3 /tmp/tokcat_v3full/finalize.py    # 重装 + contact sheets
```

BotCF edits only，锚点 `master/V3_master.png`。
