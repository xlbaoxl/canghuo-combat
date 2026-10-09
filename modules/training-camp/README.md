# 藏火 · 双窗口战斗训练营 3.0.1

2026-10-05｜规则 `dual-window-1.1`｜内容 `training-dual-1.1`｜保存结构4

基于训练营2.2.2的完整工程，保留选人→配装→镜像/预设→战斗→重试、4人物/16成品/6法宝、3D舞台、原角色素材与书卡/悬停交互。普通回合一次主动作，战机多门合法施放；自动功效不可点击重放；独立《催》保留主动按钮。成长快照采用真实公式，不包含刷取过程。

## 入口

- 当前规则入口：[核心策划](../../docs/新版战斗.md)与[升级策划](../../docs/战斗升级策划.md)。
- [操作说明](PLAY_GUIDE.md)、[实际验证与限制](TEST_REPORT.md)。
- Godot项目：`project/project.godot`。使用4.7.2官方编辑器与同版本模板。

## 实现职责

`combat_protocol.gd`维护时钟/阶段/类型；`effect_math.gd`纯计算；`catalog.gd`编译、校验、成长解析与冻结快照；`battle.gd`是真实操作/AI/预演共用的执行器；`ai.gd`使用同一合法行动边界。`main.gd`和`ui/`控制原有界面/展示/后台提交，不在动画回调改规则。

法宝实例拥有独立事件来源，不调用主角费用和锋锐。周期伤害/恢复请求、净变化及实际通道分开记录。所有模式共用H/E对账。每窗仅一次准备换法，并同时检查格子与同源等待。

## 构建和验证

安装Godot4.7.2与官方导出模板；使用 `tools/build.ps1 -Engine <Godot_console.exe> -Platform Windows` 或 `tools/build.sh <godot> Linux <输出目录>`。构建脚本不下载来源不明工具，不写原世界存档。它们执行导入、规则、动态说明、线程一致性，再导出；完整互搏和原生输入另行运行。

```sh
export UPGRADE_VERIFY_DIR=/absolute/verification
Godot --headless --path project --script res://tests/test_upgrade.gd
Godot --headless --path project --script res://tests/test_presentation_upgrade.gd
Godot --headless --path project --script res://tests/threaded_upgrade.gd
Godot --headless --path project --script res://tests/test_upgrade_battles.gd
Godot --path project -- --native-check=/absolute/verification/ui
# 上项完成后独立启动，不与原窗口共享内存
Godot --path project -- --reload-check=/absolute/verification/ui
```

导出程序支持 `-- --native-check=...`、`-- --reload-check=...`、`-- --export-check=...`。export-check仅验证实际可执行文件的资源/场景/规则启动，不代表图形验收。

原 `tests/test_rules.gd` 等入口转向当前套件。旧own-window测试原文保存在 `tests/legacy_own_window/` 并明确排除，不能用旧断言冒充新规则通过。原角色/舞台/字体/音效文件未更换，授权来源见原 `assets/ART_SOURCES.md`。

## 数据与保存

新设置仅写 `user://training_camp_v3`。旧训练配置可在明确校验后只迁移合法配装并备份，旧运行态不续接；不访问世界存档。镜像复制选定成长输入，NPC数据独立。原条件重试恢复冻结初态，战中换法结果只能显式另存。

本模块不是全游戏替换包。Win导出与Win实际图形运行分开说明；完整证据见TEST_REPORT，不用文件存在/测试数量代表平衡或作者验收。

## 3.0.1作者纠正

原设计就是自动功效＋主动《催》。3.0.0删除《催》是助手误改；本次恢复独立成品与按钮，不让自动效果被点击重放。自动记录triggered/last_normal/enabled，与主动active_used/active_ready_window互不修改。普通《催》占本回合唯一主动作；战机每入口一次。主动支付及锋锐按主动规则，自动不借用主人状态。自动给量和F未改。

首两件主动数值沿用作者原例；其余训练《催》按2.2.2直接量与费用缩十作为试验值，详见核心策划第6.3节。本轮只修复这项误改，没有重设普通／战机、成长或自动来源规则。恢复入口改变战斗内容，测试结果以本次新报告为准。
