# Codex Meter

原生 macOS 菜单栏额度监控工具，搭配 iPhone Scriptable 桌面与锁屏小组件。

Native macOS menu-bar usage monitor with an iCloud-backed Scriptable companion for iPhone.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-orange)
![License MIT](https://img.shields.io/badge/license-MIT-green)

无需打开复杂面板：Mac 顶部菜单栏显示 `C 72% · W 81%`，点击即可查看两种额度的剩余比例、已用比例和重置时间。手机显示 Mac 最近同步的真实额度快照，不在 iPhone 上登录或访问 Codex。

> 独立第三方开源项目，与 OpenAI 无隶属关系。项目不提供账号、订阅或额外额度。文档中的百分比是示例，不是预置的运行数据。

## 功能

- 原生菜单栏与紧凑弹出面板，支持系统深浅色。
- 5 小时／每周窗口按服务端时长识别，缺失窗口显示不可用。
- 剩余与已用百分比、进度条、绝对重置时间和本地倒计时。
- 启动同步、额度事件、约 60 秒兜底刷新、手动刷新与重新连接。
- 离线缓存与更新时间提示；休眠唤醒后尝试恢复连接。
- 80%／95% 阈值通知，按窗口和重置周期去重。
- 服务端提供时显示官方赠送 Full Reset 数量、发放／到期日期和到期提醒；不执行 Reset，不推测下次赠送日期。
- 客户端自动发现／手动选择、打开客户端、登录启动设置。
- 用户授权 Scriptable iCloud 文件夹后，导出最小化 `usage.json`。
- iPhone 小号、中号、锁屏矩形与圆形组件，明确标记缓存与旧数据。

## 数据路径

```text
本机 Codex App Server
    ↓ 官方 JSON-RPC / stdin / stdout
Mac Codex Meter
    ↓ 用户选择的 Scriptable iCloud 文件夹
CodexMeter/usage.json
    ↓ iCloud Drive
iPhone Scriptable Widget
```

Mac 不抓网页，不读取聊天，不保存认证凭据，不修改代理、DNS 或客户端网络配置。官方客户端负责既有登录与网络环境。当前工程没有启用 App Sandbox；不要只为手机同步开启 Sandbox，这可能影响本地子进程能力。

## 环境要求

- macOS 13 或更新版本；优先 Apple Silicon，Release 构建可覆盖 arm64 与 x86_64。
- 完整 Xcode（只运行已编译应用不需要 Xcode）。
- 已安装、已登录且能够正常获取额度的官方 Codex／ChatGPT 客户端或 Codex CLI。普通 ChatGPT 安装不一定包含 Codex App Server。
- 手机可选：Scriptable、iCloud Drive，以及与 Mac 相同的 iCloud 账号；锁屏组件需要 iOS 16+。
- Node.js 只用于脚本测试，不是 Mac 应用运行依赖。无第三方 Swift 依赖。

## Mac 安装／构建

1. 下载源码，打开 `CodexMeter.xcodeproj`。
2. 选择 `CodexMeter` Scheme 和 `My Mac`，运行。
3. 顶部菜单栏出现应用；若未找到客户端，进入设置选择包含 Codex 的官方应用。
4. 日常安装建议使用 Release 构建，将 `CodexMeter.app` 放到固定的应用程序目录后再开启登录启动。

也可在源码根目录运行：

```bash
bash scripts/build-release.sh
```

输出 `dist/CodexMeter-macOS.zip`，内含 Mac 应用、手机脚本、MIT 许可和使用文档。此脚本使用本地临时签名，不是 Apple Developer ID 公证；不要向别人声称安装包经过 Apple 公证。若系统阻止运行，只在信任来源、确认完整性后使用系统允许的打开方式，不使用全局关闭 Gatekeeper 的指令。

Apple Developer 付费账户不是阅读、修改源码或本机构建的前提；面向他人的签名／公证发行需自行准备适用的 Apple 开发者身份。iPhone 方案不是独立 iOS App，不需要本项目的 TestFlight 或 App Store 安装。

## iPhone 安装

1. 安装 Scriptable，打开其 iCloud 权限，并至少创建／运行一次脚本。
2. Mac Codex Meter → 设置 → 开启“同步到 iPhone”。
3. 用系统选择器选择 **iCloud Drive / Scriptable 根目录**。
4. 确认生成 `CodexMeter/usage.json`。
5. 将 [完整 CodexMeter.js](Scriptable/CodexMeter.js) 保存到 Scriptable 根目录或复制到 iPhone 同名脚本。
6. iPhone 手动运行一次，确认真实数据可读。
7. 添加 Scriptable 桌面／锁屏组件，选择 `CodexMeter` 脚本。

锁屏圆形默认显示 5H；参数 `weekly` 显示每周额度。完整说明见 [Scriptable 安装与使用](Scriptable/README.md)。

## 刷新与离线：先读这里

- Mac 应用需要运行并可获取真实额度；不要求官方客户端主窗口始终打开，但登录状态、可执行文件和网络必须可用。
- Mac 关机、应用退出或离线时，手机只能显示上次快照。Mac 状态没有继续导出时，手机不能直接知道 Mac 是否关机，只能通过数据年龄提醒。
- 手机新鲜度以 `sourceLastSuccessfulSync` 计算，不用文件导出时间冒充额度更新时间。
- 超过 2 小时警告，超过 6 小时明确标记可能过期；重置结束显示等待 Mac 更新，不自动填满额度。
- `refreshAfterDate` 是约 15 分钟后最早允许刷新的建议，不是精确定时器，实际由 iOS 决定。[Scriptable 官方说明](https://docs.scriptable.app/listwidget/#refreshafterdate)
- 点击手机组件会打开 Scriptable 并自动重读 iCloud、展示原尺寸预览，无需再点运行。脚本改名、锁屏圆形 `weekly` 参数均可保留。它不能强制桌面原地重绘，也不能远程要求 Mac 立即联网。
- Mac 每次真实同步成功都会导出最新检查时间，即使额度数字未变；本地倒计时和完全相同的快照不会重复写入。

## 测试

```bash
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build test CODE_SIGNING_ALLOWED=NO
node Scriptable/Tests/CodexMeter.test.cjs
```

测试覆盖分类、百分比、倒计时、周期通知去重、缓存、协议错误、恢复逻辑、JSON 导出、授权目录及四种手机布局分支。手机测试使用 Scriptable API 模拟，不替代 iPhone 实机视觉和 iCloud 端到端验证。

当前版本：Mac 1.0.4、Scriptable 1.3、JSON schema 1。31 项 XCTest 与手机脚本测试已在维护者的 Mac 上通过；该信息不是对所有客户端版本与所有 iPhone 的兼容保证。

## 代码结构

```text
CodexMeter.xcodeproj/    标准 Xcode 工程
CodexMeter/
  App/                  应用入口
  Models/               额度、连接状态、手机快照
  Services/             App Server、缓存、通知、iCloud 导出
  Views/                原生菜单栏、额度卡片、设置
  Resources/            Info.plist 与图标
CodexMeterTests/        XCTest
Scriptable/             完整脚本、说明、合成测试样例
docs/                   协议、隐私、排查说明
scripts/                本地发行构建脚本
```

## 文档与参与

- [数据协议](docs/DATA_CONTRACT.md)
- [隐私与安全边界](docs/PRIVACY.md)
- [常见问题](docs/TROUBLESHOOTING.md)
- [贡献指南](CONTRIBUTING.md)
- [版本记录](CHANGELOG.md)
- [安全问题](SECURITY.md)

提交 Issue 时不要附上 Token、Cookie、账户信息、完整日志或真实额度文件。请使用脱敏／合成样例。

## License

代码与项目原创资源采用 [MIT License](LICENSE)。可学习、修改、分发及商业使用，但需保留版权和许可声明。OpenAI、Codex、ChatGPT、Apple、Scriptable 等名称及商标属于各自权利人，MIT 不授予这些商标或第三方软件的许可。
