# 藏火 · 网页训练营

本目录是现有训练营的浏览器适配层，不是第二套战斗实现。当前完成程度、真实运行证据与未完成项见[网页实施记录](WEB_STATUS.md)。**构建成功、浏览器回归成功、托管发布成功、作者试玩认可，是四件不同的事。**

**网页版作者无需寻找 ChatGPT 授权弹窗。**现在优先使用 Vercel 自己的 GitHub 集成，具体一次性操作见[网页托管连接](../../../docs/网页托管连接.md)。不需要本地安装、下载工程或在聊天中提供令牌。

## 架构与不变边界

`tools/web/build.py` 将 `modules/training-camp/project` 复制到临时构建目录；只替换该副本的主场景、渲染配置与导出预设。仓库中的桌面工程不变。浏览器 `main.gd` 继承原控制器；人物、技能、法宝、数值、执行器和 AI 全部使用原文件。构建前后核对文件指纹，只允许 staging 中的 `project.godot` 和 `export_presets.cfg` 两项原文件不同。

Godot 编辑器和 Web 模板固定为官方 4.7.2，安装器检查官方发布资产 SHA256，并核对已有桌面验证使用的引擎摘要。Web 使用 Compatibility/WebGL 2 与多线程，保留真实后台 AI；没有为了上线而删掉《催》、改变普通/战机、缩减素材或将规则重写成 JavaScript。Web 专用表现调整仅关闭 3D 子视口额外的 2× MSAA，暂停时停止重复绘制同一个舞台；原桌面设置不变。

迁入的历史源码仍是可核验基线。本轮通过外部适配层保持其原字节，不删除原迁移校验。以后真正修改核心代码时，应另建明确的演进记录与原始来源快照，不用改写历史指纹掩盖来源变化。

## 试玩入口和反馈

页面要求用户点击“进入训练营”，显示资源加载进度、游戏版本与提交标识。电脑浏览器是第一阶段目标。已通过的核心流程环境为 Chromium 153 / Ubuntu / Xvfb / Mesa；SwiftShader 路径仍有超时记录，Firefox、Safari、手机及作者实际设备尚不在已验证范围。浏览器需支持 WebGL 2、SharedArrayBuffer、HTTPS 和跨源隔离；缺少必要响应头会显示明确错误，而不是静默让 AI 失败。

训练设置保存到当前浏览器的持久存储；保存后请求同步。刷新结束当前对局，只恢复合法配装与冻结的重试初态，不伪装成云存档或运行态续接。清理网站数据、隐私模式以及更换域名可能导致设置不可用。

“反馈本场问题”提供可复制摘要，以及包含初态、事件、AI 判断、已接受人类指令、对账和版本的完整诊断下载。数据只在浏览器生成，不自动上传，不含仓库令牌。**完整 AI 指令重放尚未实现和验证，诊断记录不能宣称可保证重现任何问题。**

`build.json` 每分钟及页面重新可见时重新检查。发现更新只提示，由玩家确认刷新；不在打到一半自动更换规则。首版不用 Service Worker，避免旧引擎脚本和新资源缓存混用。

## 自动构建与验收

`.github/workflows/web-playtest.yml` 在相关代码变更后执行：Python 防误发布测试、归档完整性、官方引擎导入、四套原规则/表现/线程/固定对局回归、真实 Web release 导出、Chromium 鼠标输入试玩、源码未变化检查。浏览器测试通过才产生名为 `web-playable-release` 的产物；失败版本使用明确的 `web-unverified-candidate` 名称，仅用于定位问题。证据保存在 `web-verification`，不是作者体验验收。

开发与测试命令（由开发端/CI 执行，不要求作者本地安装）：

```sh
python tools/web/install_godot.py --dir /tmp/canghuo-godot
python tools/web/build.py --engine /tmp/canghuo-godot/godot --output /tmp/canghuo-web --verify
python -m pip install 'playwright==1.63.0'
python -m playwright install --with-deps chromium
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s '-screen 0 1600x1000x24' python tools/web/smoke.py --headed --graphics mesa --root /tmp/canghuo-web --output /tmp/canghuo-web-browser
```

构建输出目录必须不存在；不会覆盖其他源码或已有构建。`tools/web/serve.py` 仅供回环地址自动测试，不是生产服务器。

## 首选托管方式：Vercel 原生 Git 集成

作者在 ChatGPT 网页版没有看到授权卡片，因此不再把 ChatGPT 的 Vercel 插件当作发布前置。使用已有 GitHub 连接维护代码和经过测试的发布分支；作者在 Vercel 普通网页完成一次 GitHub 仓库连接和访问保护设置即可。详细步骤见[网页托管连接](../../../docs/网页托管连接.md)。

`web-site-sync.yml` 只取本仓 main 当前提交的成功 Web 工作流产物，重新核对构建身份、验收记录和文件指纹，将运行包更新到同仓私有 `web-playtest-site` 分支。只对这个带专用标记的生成分支作普通提交与推送；未识别文件、符号链接、失败/过时/PR/fork产物都会阻止覆盖。不强推或重置历史，不将该分支合入 main。它不是新的战斗源码维护仓库。

Vercel 连接前，主分支 `vercel.json` 仅允许输出一张不含游戏资源的设置页；先设置 **Vercel Authentication → All Deployments**，再把生产分支设为 `web-playtest-site`。该分支的静态输出为 `public`，带有 Web AI 线程需要的 COOP/COEP 响应头。Git 模式不需要 Vercel API token；网页是否实际受保护、是否可玩仍要在真实 URL 上验收，不能用私有仓库或同步绿灯代替。

## 可选方式：基于 Vercel API 的受保护发布器

原 `tools/web/deploy_vercel.py` 保留，默认不开启。它先检查同一提交的规则与浏览器证据、每份运行文件 SHA256、已有项目身份及 `ssoProtection.deploymentType=all`，不满足则停止且不上传。不自动创建项目或关闭保护。

此可选模式使用 Secret `VERCEL_TOKEN`、Variables `VERCEL_PROJECT_ID`、可选 `VERCEL_TEAM_ID` 和开关 `WEB_DEPLOY_ENABLED=true`。**首选 Git 模式不需要这些配置；不要同时开启两个发布通道，不要把 token 发到聊天或写入网页。**

无论哪条路径，构建/分支同步/托管 READY 都不等于线上试玩已验收。需要实际 HTTPS 网址、访问保护、响应头、版本、完整战斗、保存和反馈检查。获准试玩者仍能下载游戏运行资源，不能把客户端资源视作服务器秘密。Cloudflare Pages 首轮 25 MiB 单文件限制小于本工程主要资源，因此没有直接改用它。

官方依据：[Godot Web 导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)、[JavaScriptBridge](https://docs.godotengine.org/en/stable/classes/class_javascriptbridge.html)、[Vercel Git 集成](https://vercel.com/docs/git)、[Vercel 访问保护](https://vercel.com/docs/deployment-protection)。
