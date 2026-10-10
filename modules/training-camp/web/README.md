# 藏火 · 网页训练营

本目录是现有训练营的浏览器适配层，不是第二套战斗实现。当前完成程度、真实运行证据与未完成项见[网页实施记录](WEB_STATUS.md)。**构建成功、浏览器回归成功、托管发布成功、作者试玩认可，是四件不同的事。**

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

## 托管一次性配置与发布边界

目标是 Vercel 上的固定受保护试玩入口。此前考虑的 Cloudflare Pages 单文件 25 MiB 限制小于首轮导出的两项主要资源（PCK 约 36 MB、WASM 约 39 MB），因此不直接采用该方案。具体托管配额及访问权限应在首次连接时再次核验。

**未连接账号不等于已经部署。**首次需要作者授权托管账号，然后由开发端建立/选择专用项目，确认全部部署（包括正式域名）受 Vercel Authentication 保护。仓库私有、`robots.txt` 或难猜网址都不是网站访问控制。浏览器必须能下载游戏运行资源，因此获准试玩者仍可取得发布资源，不能将客户端代码视作服务器秘密。

发布脚本 `tools/web/deploy_vercel.py` 已提供，但托管 API 的真实端到端联调必须在账号连接后完成。脚本先检查同一提交的规则与浏览器证据、每份运行文件的 SHA256、已有项目身份及 `ssoProtection.deploymentType=all`，不满足则停止且不上传。只上传白名单运行文件，不上传仓库源码、研究材料、测试证据或访问令牌，不自动创建项目或关闭保护。

GitHub 配置使用 Secret `VERCEL_TOKEN`、Variables `VERCEL_PROJECT_ID`（已有 `prj_...` 标识）、可选 `VERCEL_TEAM_ID`，以及显式开关 `WEB_DEPLOY_ENABLED=true`。**不要把 token 发到聊天、提交到仓库或写入网页。**首次配置由开发端处理账号允许的部分，不能把缺少发布授权伪装成代码错误。本轮不会自动打开开关。

开启后，只有 `main` 的通过版本可触发正式发布；PR 不读取发布凭据，也不覆盖稳定入口。脚本返回 READY 只代表托管平台报告就绪，仍需登录后的真实 HTTPS 访问，检查响应头、版本、一次完整战斗、保存和反馈。发布结果明确记录 `public_http_and_browser_verified=false`，未做此项时不能声称正式网址已验收。后续实验分支预览/线上冒烟门禁属于下一项扩展，不用假网址冒充现成入口。

官方依据：[Godot Web 导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)、[JavaScriptBridge](https://docs.godotengine.org/en/stable/classes/class_javascriptbridge.html)、[Vercel 项目读取](https://vercel.com/docs/rest-api/projects/find-a-project-by-id-or-name)、[文件上传](https://vercel.com/docs/rest-api/deployments/upload-deployment-files)、[部署创建](https://vercel.com/docs/rest-api/deployments/create-a-new-deployment)。
