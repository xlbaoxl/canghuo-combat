# 本模块素材来源

本模块从作者授权使用的 `D:/novel/game` 现有工程和素材库复制已有素材。实际本地来源路径及逐文件 SHA256 在 `SOURCES.json`，人物原提示词与元数据、野怪生成清单均随源码保存。

- 人物六组：`素材库/01_人物动画/characters_frames_v1`，既有内置 image_gen 原创全身八帧条带。原元数据记录生成工具与源图路径，脚位经已有资产导出统一。没有重新生成，也没有复制商业角色。
- 赤角炎牛：`素材库/02_灵兽与Boss/bosses_attack_v1`，内置 image_gen 原创16帧四乘四图集；`characters/cinder_horn_ox/source_manifest.json` 保存原批次记录。
- 配装/结果页背景：既有 `assets/art/combat_v2/battle-courtyard.png`，原同名生成提示词保留。战斗页实际采用旧版原创程序石台，不使用平面背景代替模型。
- 石台：旧工程 `lab_box_diorama.gd` 原创几何、材质与灯光代码；移植来源与提交见模块 README。
- 本次功法、法宝、Buff图标：`tools/build_ui_assets.py`生成的34张原创SVG，书封面预留框由`skill_tile.gd`绘制。参考旧Demo交互及本地《逸剑风云决》打包蓝图元数据中的分类/技能提示绑定，未复制其贴图或开发源码。
- SVG图标和短音效：既有 `tools/generate_art.py` 原创几何/数学波形产物。
- 中文字体：未修改 Noto Sans SC，官方固定来源、哈希与 SIL OFL 1.1 在 `fonts/SOURCE.md` / `fonts/OFL.txt`。
- Godot：引擎 MIT 与第三方版权见 `licenses/Godot-LICENSE.txt` / `Godot-COPYRIGHT.txt`。

不宣称AI生成内容的排他版权或新增第三方开源许可。素材未获本次作者审美验收；既有条带有生成细节和姿势衔接限制。
