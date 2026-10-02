# Codex Meter Scriptable Widget

这个脚本只读取 Mac Codex Meter 写入 iCloud Drive 的只读额度快照，不登录 OpenAI，也不保存 Token、Cookie、账号或聊天内容。

## 从旧版升级

当前手机脚本版本：1.4（与 Mac 1.0.4 及 usage.json schemaVersion 1 兼容）。Mac 不需要重装。

本次优化没有修改 `usage.json` 和 Mac 同步设置。只需用项目中的新版 `CodexMeter.js` 替换 Scriptable 里的同名脚本；桌面和锁屏小组件无需删除或重新添加。

## 首次安装

1. 在 iPhone 安装 Scriptable。
2. 确认系统设置中已为 Scriptable 开启 iCloud。
3. 在 iPhone Scriptable 中至少创建并运行一次任意脚本，确保 Scriptable 的 iCloud Documents 已建立并同步到 Mac。
4. 在 Mac 打开 Codex Meter → 设置。
5. 开启“同步到 iPhone”。
6. 在系统文件夹选择器中选择“iCloud Drive / Scriptable”根目录。
7. 确认 Mac 成功生成 `Scriptable/CodexMeter/usage.json`。
8. 将完整的 `CodexMeter.js` 放入 Scriptable。可以在 Mac 的 Scriptable iCloud 文件夹中保存，也可以复制到 iPhone Scriptable 新脚本。
9. 在 iPhone Scriptable 中手动运行一次 `CodexMeter`，确认能够读取数据。
10. iPhone 长按桌面，或进入锁屏编辑界面。
11. 添加 Scriptable Widget。
12. 在 Widget 配置中选择 `CodexMeter` 脚本。

## 支持尺寸

- 桌面小号：5H 和 W 两个剩余额度及简短重置时间。
- 桌面中号：5H 和 WEEK 两组额度、进度条、重置倒计时和数据新鲜度。
- 锁屏矩形：两组剩余额度和 5H 重置倒计时。
- 锁屏圆形：默认显示 5H；Widget Parameter 填写 `weekly` 可显示周额度，填写 `fiveHour` 或留空显示 5 小时额度。

在 Scriptable App 中手动运行脚本会立即重新读取 iCloud 的 `usage.json`。

新版支持点击小组件打开 Scriptable 并自动运行当前脚本，立即重新读取 iCloud 数据并展示预览，无需再点击运行按钮。脚本改名后仍有效；桌面小/中号、锁屏矩形/圆形均支持，预览保留原尺寸和 `weekly` 参数。锁屏可能需要先解锁。

这不是“不跳转的桌面原地刷新”：手机只能读取已经同步到 iCloud 的快照，不能要求 Mac 立即联网获取额度，也不能强制桌面小组件马上重绘。

## 刷新说明

1.4 不再人为设置“至少 15 分钟后才允许刷新”，而是把 `refreshAfterDate` 设为 `null`，使用 Scriptable / iOS 的默认调度。默认调度不保证比旧版更快，更不保证秒级、每分钟或精确定时刷新。实际刷新时机仍由 iOS / iPadOS 决定，低电量、低使用频率等情况可能继续延迟。

iCloud 返回的文件有时比手机已有的缓存更旧。1.4 会先比较真实额度检查时间，再比较同一检查时间下的导出时间，保留更新的有效数据并标记缓存，避免旧文件覆盖新额度。较新的离线状态仍可正常更新。

排查延迟时请区分三段：Mac 获取与导出、iCloud 文件传输、iOS 桌面渲染。手动运行预览已经变新但桌面未变，说明桌面尚未刷新；手动运行也旧，需要对比 Mac 的最后成功检查和导出时间，不能仅靠缩短脚本刷新设置解决。

如果必须立刻读取最新的 `usage.json`，请在 Scriptable App 中手动运行 `CodexMeter`。真正不打开 App 的点击刷新需要原生 iOS WidgetKit 小组件和 App Intent，不属于当前 Scriptable 方案。

Mac 1.0.4 修复额度数字不变时遗漏最新成功检查时间的问题：每次真实同步成功都会更新快照时间；重复的相同快照和本地倒计时不会触发写入。Mac 休眠、离线或 iCloud 未完成传输时，点击不会伪造新数据。

额度新鲜度以 `sourceLastSuccessfulSync` 为准。30 分钟后显示具体更新时间，2 小时后显示警告，6 小时后明确显示“数据可能已过期”。如果 iCloud 暂时不可用，脚本会显示最后一次有效缓存并标记“缓存”；没有任何有效数据时不会显示虚假的 `0%`。

新版还会分别标记“更新中”“离线”“缓存”“Mac 连接异常”和“额度暂不可用”。即使 Mac 关机或断网，最后一次有效额度仍会保留，但不会伪装成实时数据。

## 1.2 状态与排查

- 中号桌面组件将倒计时和具体重置时间分行显示，保留已用比例与进度条；小号优先突出剩余额度。
- 锁屏矩形明确显示缓存、离线或过期；圆形除了警示符号还会显示简短状态，不能只凭颜色判断。
- 重置已过时显示“等待 Mac 更新”或“待更新”，仍保留上次真实比例，不自动补成 100%。
- “刚刚同步／几分钟前”始终根据真实额度更新时间计算，不根据文件导出时间计算。
- 在 Scriptable 手动运行时，若文件未生成、下载失败或格式有误，会先弹出中文处理建议，再展示有效缓存或无数据界面。桌面自动运行不会弹窗。
- 本地文件更新只能证明脚本已部署到 Mac 的 iCloud 目录。请等待 iCloud 同步，并在 iPhone Scriptable 手动运行一次，确认下载与实际显示；无需重新添加原来的小组件。
