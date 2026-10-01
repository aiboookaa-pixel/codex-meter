# 数据与本地协议

## 官方本地 App Server

`CodexAppServerClient` 启动现有客户端的 `codex app-server --stdio` 子进程，使用逐行 JSON-RPC、stdin/stdout 通信。当前实现完成 `initialize` 后请求 `account/rateLimits/read`，监听 `account/rateLimits/updated`。协议可能随客户端更新，故错误、空字段和断线都必须兼容；请以实际安装版本的官方协议为准。

额度优先取 `rateLimitsByLimitId["codex"]`，否则取 `rateLimits`。窗口字段为 `usedPercent`、`windowDurationMins`、`resetsAt`（Unix 秒）。primary/secondary 不是永久的 5H/WEEK 语义；以窗口时长分类，无法识别则为 unknown。

可选 `rateLimitResetCredits` 包含 `availableCount`、`credits[]`（`grantedAt`、`expiresAt`、`status`、`resetType`、可选 `id`）。本应用仅展示、提醒，不调用 Reset。当前不推测下次赠送／恢复日期。

不附带官方可执行文件，不采集认证数据，不改变官方客户端安装与配置。

## 手机 JSON schema 1

路径：用户授权的 Scriptable 根目录下 `CodexMeter/usage.json`；手机通过 `FileManager.iCloud().documentsDirectory()` 定位同一路径，不访问 Mac 的本机地址。

```json
{
  "schemaVersion": 1,
  "fiveHour": {
    "usedPercent": 28,
    "remainingPercent": 72,
    "resetAt": "2026-09-13T22:16:00+08:00"
  },
  "weekly": null,
  "sourceLastSuccessfulSync": "2026-09-13T20:38:12+08:00",
  "exportedAt": "2026-09-13T20:38:13+08:00",
  "sourceStatus": "connected"
}
```

示例是合成数据，只用于说明结构。窗口允许 null；resetAt 允许 null。百分比为 0–100、已用与剩余合计 100。日期为 ISO 8601，UTC 的 Z 与时区偏移都合法。

`sourceLastSuccessfulSync` 表示 Codex 数据最后成功获取时间；`exportedAt` 只是本机文件生成时间。状态可能为 connected、refreshing、offline、cached、codexNotFound、appServerUnavailable、dataUnavailable、error。未知状态被手机当作异常，而非实时正常。

Mac 对有意义的快照／状态更新导出；倒计时不触发每秒写入。先写临时文件并验证能解码，再原子替换有效文件。手机校验 schema、字段、日期和百分比；下载或解析失败时使用有效本地缓存并显式标注。

手机 schema 1 不导出 Full Reset、账号、邮箱、Cookie、密码、Token、聊天内容、代理配置或设备识别信息。未来协议升级需明确迁移，不静默改变 schema 1 含义。
