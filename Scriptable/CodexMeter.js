// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: yellow; icon-glyph: magic;
// Codex Meter for Scriptable
// Reads only CodexMeter/usage.json from Scriptable's iCloud Documents folder.
// Widget version 1.4.1 — compatible with usage schema version 1.

const SCHEMA_VERSION = 1
const DATA_FOLDER = "CodexMeter"
const DATA_FILE = "usage.json"
const CACHE_FILE = "last-valid-usage.json"

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function validISODate(value) {
  return typeof value === "string" && Number.isFinite(new Date(value).getTime())
}

function validateWindow(value, fieldName) {
  if (value === null) return null
  if (!isObject(value)) throw new Error(`${fieldName} must be an object or null`)
  const used = value.usedPercent
  const remaining = value.remainingPercent
  if (!Number.isFinite(used) || !Number.isFinite(remaining) || used < 0 || used > 100 || remaining < 0 || remaining > 100) {
    throw new Error(`${fieldName} percentages are invalid`)
  }
  if (Math.round(used) + Math.round(remaining) !== 100) {
    throw new Error(`${fieldName} percentages are inconsistent`)
  }
  if (value.resetAt !== null && value.resetAt !== undefined && !validISODate(value.resetAt)) {
    throw new Error(`${fieldName}.resetAt is invalid`)
  }
  return {
    usedPercent: Math.round(used),
    remainingPercent: Math.round(remaining),
    resetAt: value.resetAt ?? null,
  }
}

function validateUsage(value) {
  if (!isObject(value)) throw new Error("usage payload must be an object")
  if (value.schemaVersion !== SCHEMA_VERSION) throw new Error("unsupported schemaVersion")
  if (!("fiveHour" in value) || !("weekly" in value)) throw new Error("quota window fields are missing")
  if (!validISODate(value.sourceLastSuccessfulSync)) throw new Error("sourceLastSuccessfulSync is invalid")
  if (!validISODate(value.exportedAt)) throw new Error("exportedAt is invalid")
  if (typeof value.sourceStatus !== "string") throw new Error("sourceStatus is invalid")
  return {
    schemaVersion: SCHEMA_VERSION,
    fiveHour: validateWindow(value.fiveHour, "fiveHour"),
    weekly: validateWindow(value.weekly, "weekly"),
    sourceLastSuccessfulSync: value.sourceLastSuccessfulSync,
    exportedAt: value.exportedAt,
    sourceStatus: value.sourceStatus,
  }
}

function cachePath(localManager) {
  const folder = localManager.joinPath(localManager.documentsDirectory(), DATA_FOLDER)
  return { folder, file: localManager.joinPath(folder, CACHE_FILE) }
}

function readCachedUsage(localManager) {
  try {
    const paths = cachePath(localManager)
    if (!localManager.fileExists(paths.file)) return null
    return validateUsage(JSON.parse(localManager.readString(paths.file)))
  } catch (_) {
    return null
  }
}

function saveCachedUsage(localManager, usage) {
  try {
    const paths = cachePath(localManager)
    if (!localManager.fileExists(paths.folder)) localManager.createDirectory(paths.folder, true)
    localManager.writeString(paths.file, JSON.stringify(usage))
  } catch (_) {
    // A cache failure must never hide a valid iCloud snapshot.
  }
}

function snapshotIsNewer(candidate, reference) {
  const sourceDifference = new Date(candidate.sourceLastSuccessfulSync).getTime()
    - new Date(reference.sourceLastSuccessfulSync).getTime()
  if (sourceDifference !== 0) return sourceDifference > 0
  // A later export can carry a new offline/connected state for the same data.
  return new Date(candidate.exportedAt).getTime() > new Date(reference.exportedAt).getTime()
}

async function loadUsage(icloudManager, localManager) {
  const cached = readCachedUsage(localManager)
  let stage = "icloud"
  try {
    const dataFolder = icloudManager.joinPath(icloudManager.documentsDirectory(), DATA_FOLDER)
    const dataFile = icloudManager.joinPath(dataFolder, DATA_FILE)
    stage = "missing"
    if (!icloudManager.fileExists(dataFile)) throw new Error("missing")
    stage = "download"
    await icloudManager.downloadFileFromiCloud(dataFile)
    stage = "read"
    const content = icloudManager.readString(dataFile)
    stage = "invalid"
    const usage = validateUsage(JSON.parse(content))
    if (cached && snapshotIsNewer(cached, usage)) {
      // iCloud may still expose an earlier version. Never roll valid data back.
      return { usage: cached, isCache: true, error: "lagging" }
    }
    saveCachedUsage(localManager, usage)
    return { usage, isCache: false, error: null }
  } catch (error) {
    const code = error?.message === "unsupported schemaVersion" ? "schema" : stage
    return { usage: cached, isCache: cached !== null, error: code }
  }
}

function diagnosticMessage(loaded) {
  const reasons = {
    missing: "尚未找到 usage.json。请确认 Mac 已开启 iPhone 同步、选择 Scriptable 文件夹并点击立即同步。",
    download: "iCloud 文件下载失败。请检查 iPhone 网络和 Scriptable 的 iCloud 权限，稍后重试。",
    read: "iCloud 文件暂时无法读取，可能尚未同步完成。请稍后再运行。",
    invalid: "额度文件格式不完整或字段无效。请在 Mac 点击立即同步，重新生成有效数据。",
    schema: "额度文件版本不受支持。请更新 CodexMeter 脚本。",
    icloud: "无法访问 Scriptable iCloud 目录。请确认 iCloud Drive 和 Scriptable 的 iCloud 开关已开启。",
    lagging: "iCloud 返回了较旧的快照，正在保留手机上更新的有效缓存。请等待云端同步完成后再点击刷新；刷新不会强制 Mac 或 iCloud 立即更新。",
  }
  return `${reasons[loaded.error] || "同步暂时不可用，请稍后重试。"}\n\n${loaded.isCache ? "正在保留上次有效缓存，不代表实时额度。" : "尚无有效缓存，不会显示虚假额度。"}`
}

function formatAge(minutes) {
  if (minutes < 2) return "刚刚同步"
  if (minutes < 60) return `${Math.floor(minutes)}分钟前同步`
  if (minutes < 120) return `${Math.floor(minutes / 60)}小时前同步`
  if (minutes >= 1440) return `${Math.floor(minutes / 1440)}天前同步`
  return `${Math.floor(minutes / 60)}小时前同步`
}

function freshnessInfo(usage, isCache, now = new Date()) {
  const ageMinutes = Math.max(0, (now.getTime() - new Date(usage.sourceLastSuccessfulSync).getTime()) / 60000)
  let level = "fresh"
  let text = formatAge(ageMinutes)
  if (ageMinutes >= 360) {
    level = "expired"
    text = "数据可能已过期"
  } else if (ageMinutes >= 120) {
    level = "stale"
    text = formatAge(ageMinutes)
  } else if (ageMinutes >= 30) {
    level = "aging"
  }

  if (usage.sourceStatus === "refreshing") {
    level = level === "expired" ? level : "updating"
    text = `更新中 · ${text}`
  } else if (usage.sourceStatus === "offline") {
    level = level === "expired" ? level : "stale"
    text = `离线 · ${text}`
  } else if (usage.sourceStatus === "cached") {
    level = level === "expired" ? level : "stale"
    text = `缓存 · ${text}`
  } else if (usage.sourceStatus === "appServerUnavailable") {
    level = level === "expired" ? level : "stale"
    text = `Mac 连接异常 · ${text}`
  } else if (usage.sourceStatus === "codexNotFound") {
    level = level === "expired" ? level : "stale"
    text = `Mac 未找到 ChatGPT · ${text}`
  } else if (usage.sourceStatus === "dataUnavailable") {
    level = level === "expired" ? level : "stale"
    text = `额度暂不可用 · ${text}`
  } else if (usage.sourceStatus !== "connected") {
    level = level === "expired" ? level : "stale"
    text = `状态异常 · ${text}`
  }
  if (isCache && !text.includes("缓存")) {
    level = level === "expired" ? level : "stale"
    text = `缓存 · ${text}`
  }
  if ((level === "stale" || level === "expired") && !text.startsWith("⚠")) {
    text = `⚠ ${text}`
  }
  const statusLabels = {
    connected: "", refreshing: "Mac 更新中", offline: "Mac 离线", cached: "Mac 缓存",
    appServerUnavailable: "Mac 连接异常", codexNotFound: "客户端未找到", dataUnavailable: "额度不可用",
  }
  const sourceLabel = statusLabels[usage.sourceStatus] ?? "状态异常"
  const age = formatAge(ageMinutes).replace("同步", "")
  let badge = level === "fresh" ? "正常" : level === "aging" ? "较旧" : "旧数据"
  if (sourceLabel) badge = sourceLabel.replace("Mac ", "")
  if (isCache) badge = "缓存"
  if (level === "expired") badge = "已过期"
  const compactText = level === "expired"
    ? `⚠ 数据可能已过期${sourceLabel ? ` · ${sourceLabel}` : ""}${isCache ? " · 缓存" : ""}`
    : `${level === "stale" ? "⚠ " : ""}${isCache ? "缓存 · " : ""}${sourceLabel ? `${sourceLabel} · ` : ""}${age === "刚刚" ? "刚刚同步" : `${age}同步`}`
  return { ageMinutes, level, text, compactText, badge }
}

function absoluteResetLabel(resetAt, now = new Date()) {
  if (!resetAt) return null
  const target = new Date(resetAt)
  if (target.getTime() <= now.getTime()) return null
  const sameDay = target.getFullYear() === now.getFullYear()
    && target.getMonth() === now.getMonth()
    && target.getDate() === now.getDate()
  const formatter = new DateFormatter()
  formatter.locale = "zh_CN"
  formatter.dateFormat = sameDay ? "HH:mm" : "M/d HH:mm"
  return formatter.string(target)
}

function resetDetailLabel(resetAt, now = new Date()) {
  const relative = resetLabel(resetAt, now)
  const absolute = absoluteResetLabel(resetAt, now)
  return absolute ? `${relative} · ${absolute}` : relative
}

function nearestResetLabel(usage, now = new Date()) {
  const candidates = [["5H", usage.fiveHour], ["W", usage.weekly]]
    .filter(([, window]) => window && validISODate(window.resetAt))
    .map(([title, window]) => ({ title, resetAt: window.resetAt, time: new Date(window.resetAt).getTime() }))
  const next = candidates.filter(value => value.time > now.getTime()).sort((a, b) => a.time - b.time)[0]
  if (!next) return candidates.length ? "等待 Mac 更新" : "重置时间不可用"
  return `下次重置 ${next.title} · ${absoluteResetLabel(next.resetAt, now)}`
}

function resetRemaining(resetAt, now = new Date()) {
  if (!resetAt) return { expired: false, seconds: null }
  const seconds = Math.floor((new Date(resetAt).getTime() - now.getTime()) / 1000)
  return { expired: seconds <= 0, seconds: Math.max(0, seconds) }
}

function resetLabel(resetAt, now = new Date()) {
  const value = resetRemaining(resetAt, now)
  if (value.seconds === null) return "重置时间不可用"
  if (value.expired) return "等待 Mac 更新"
  const days = Math.floor(value.seconds / 86400)
  const hours = Math.floor((value.seconds % 86400) / 3600)
  const minutes = Math.floor((value.seconds % 3600) / 60)
  if (days > 0) return `${days}天${hours}小时后`
  if (hours > 0) return `${hours}小时${minutes}分后`
  return `${Math.max(1, minutes)}分钟后`
}

function compactResetLabel(resetAt, now = new Date()) {
  const value = resetRemaining(resetAt, now)
  if (value.seconds === null) return "--"
  if (value.expired) return "待更新"
  if (value.seconds < 86400) {
    const hours = Math.floor(value.seconds / 3600)
    const minutes = Math.floor((value.seconds % 3600) / 60)
    return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}` : `${Math.max(1, minutes)}分`
  }
  const formatter = new DateFormatter()
  formatter.locale = "zh_CN"
  formatter.dateFormat = "EEE HH:mm"
  return formatter.string(new Date(resetAt))
}

function palette() {
  return {
    background: Color.dynamic(new Color("F4F5F8"), new Color("17191D")),
    card: Color.dynamic(new Color("FFFFFF", 0.82), new Color("FFFFFF", 0.08)),
    primary: Color.dynamic(new Color("101218"), new Color("F6F7FA")),
    secondary: Color.dynamic(new Color("596273"), new Color("A9B0BD")),
    green: new Color("34C759"),
    blue: new Color("0A84FF"),
    warning: new Color("FF9F0A"),
    updating: new Color("64A8FF"),
    track: Color.dynamic(new Color("DDE1E8"), new Color("3B3E45")),
  }
}

function addText(parent, value, font, color, lineLimit = 1) {
  const text = parent.addText(value)
  text.font = font
  text.textColor = color
  text.lineLimit = lineLimit
  text.minimumScaleFactor = 0.72
  return text
}

function freshnessGlyph(freshness) {
  if (freshness.level === "fresh") return "●"
  if (freshness.level === "updating") return "↻"
  return "⚠"
}

function freshnessColor(freshness, colors, freshColor = colors.secondary) {
  if (freshness.level === "fresh") return freshColor
  if (freshness.level === "updating") return colors.updating
  return colors.warning
}

function addProgress(parent, remainingPercent, width, color, colors) {
  const bar = parent.addStack()
  bar.layoutHorizontally()
  bar.size = new Size(width, 6)
  bar.backgroundColor = colors.track
  bar.cornerRadius = 3
  if (remainingPercent > 0) {
    const fill = bar.addStack()
    fill.size = new Size(Math.max(2, width * remainingPercent / 100), 6)
    fill.backgroundColor = color
    fill.cornerRadius = 3
  }
  bar.addSpacer()
}

function addQuotaColumn(parent, title, window, color, width, colors, now) {
  const column = parent.addStack()
  column.layoutVertically()
  const heading = column.addStack()
  addText(heading, title, Font.semiboldSystemFont(11), colors.secondary)
  heading.addSpacer()
  if (window) addText(heading, `已用 ${window.usedPercent}%`, Font.systemFont(9), colors.secondary)
  column.addSpacer(4)
  if (!window) {
    addText(column, "--", Font.boldSystemFont(30), colors.secondary)
    column.addSpacer(5)
    addText(column, "当前不可用", Font.systemFont(11), colors.secondary)
    return column
  }
  addText(column, `${window.remainingPercent}%`, Font.boldSystemFont(30), color)
  column.addSpacer(5)
  addProgress(column, window.remainingPercent, width, color, colors)
  column.addSpacer(5)
  addText(column, resetLabel(window.resetAt, now), Font.systemFont(10), colors.secondary)
  const absolute = absoluteResetLabel(window.resetAt, now)
  if (absolute) addText(column, `重置 ${absolute}`, Font.systemFont(9), colors.secondary)
  return column
}

function makeBaseWidget() {
  const widget = new ListWidget()
  widget.backgroundColor = palette().background
  return widget
}

function noDataWidget(family) {
  const colors = palette()
  const widget = makeBaseWidget()
  if (family === "accessoryCircular") {
    widget.addAccessoryWidgetBackground = true
    widget.setPadding(2, 2, 2, 2)
    const stack = widget.addStack()
    stack.layoutVertically()
    stack.centerAlignContent()
    stack.addSpacer()
    addText(stack, "C", Font.boldSystemFont(10), colors.secondary)
    addText(stack, "--", Font.boldSystemFont(18), colors.primary)
    stack.addSpacer()
    return widget
  }
  if (family === "accessoryRectangular") {
    widget.addAccessoryWidgetBackground = true
    widget.setPadding(2, 4, 2, 4)
    addText(widget, "Codex Meter", Font.boldSystemFont(10), colors.primary)
    addText(widget, "尚无同步数据", Font.semiboldSystemFont(14), colors.primary)
    addText(widget, "请在 Mac 开启同步", Font.systemFont(9), colors.secondary)
    return widget
  }
  widget.setPadding(14, 14, 14, 14)
  addText(widget, "Codex Meter", Font.boldSystemFont(13), colors.primary)
  widget.addSpacer(5)
  addText(widget, "尚无同步数据", Font.semiboldSystemFont(family === "medium" ? 18 : 14), colors.primary, 2)
  widget.addSpacer(3)
  addText(widget, "请先在 Mac 端开启 iPhone 同步", Font.systemFont(10), colors.secondary, 2)
  return widget
}

function buildMedium(usage, freshness, now) {
  const colors = palette()
  const widget = makeBaseWidget()
  widget.setPadding(14, 16, 12, 16)
  const header = widget.addStack()
  addText(header, "Codex Meter", Font.boldSystemFont(13), colors.primary)
  header.addSpacer()
  addText(header, freshnessGlyph(freshness), Font.boldSystemFont(12), freshnessColor(freshness, colors, colors.green))
  widget.addSpacer(10)
  const quotas = widget.addStack()
  addQuotaColumn(quotas, "5 小时", usage.fiveHour, colors.green, 112, colors, now)
  quotas.addSpacer(18)
  addQuotaColumn(quotas, "每周", usage.weekly, colors.blue, 112, colors, now)
  widget.addSpacer()
  addText(widget, nearestResetLabel(usage, now), Font.systemFont(9), colors.secondary)
  widget.addSpacer(2)
  addText(widget, freshness.compactText, Font.systemFont(10), freshnessColor(freshness, colors))
  return widget
}

function buildSmall(usage, freshness, now) {
  const colors = palette()
  const widget = makeBaseWidget()
  widget.setPadding(13, 13, 12, 13)
  const header = widget.addStack()
  addText(header, "Codex Meter", Font.boldSystemFont(13), colors.primary)
  header.addSpacer()
  addText(header, freshnessGlyph(freshness), Font.boldSystemFont(10), freshnessColor(freshness, colors, colors.green))
  widget.addSpacer(8)
  const row = widget.addStack()
  const five = row.addStack()
  five.layoutVertically()
  addText(five, "5H", Font.semiboldSystemFont(10), colors.secondary)
  addText(five, usage.fiveHour ? `${usage.fiveHour.remainingPercent}%` : "--", Font.boldSystemFont(24), usage.fiveHour ? colors.green : colors.secondary)
  addText(five, usage.fiveHour ? compactResetLabel(usage.fiveHour.resetAt, now) : "不可用", Font.systemFont(9), colors.secondary)
  row.addSpacer()
  const week = row.addStack()
  week.layoutVertically()
  addText(week, "W", Font.semiboldSystemFont(10), colors.secondary)
  addText(week, usage.weekly ? `${usage.weekly.remainingPercent}%` : "--", Font.boldSystemFont(24), usage.weekly ? colors.blue : colors.secondary)
  addText(week, usage.weekly ? compactResetLabel(usage.weekly.resetAt, now) : "不可用", Font.systemFont(9), colors.secondary)
  widget.addSpacer()
  addText(widget, nearestResetLabel(usage, now), Font.systemFont(9), colors.secondary)
  widget.addSpacer(2)
  addText(widget, freshness.compactText, Font.systemFont(9), freshnessColor(freshness, colors), 2)
  return widget
}

function buildAccessoryRectangular(usage, freshness, now) {
  const colors = palette()
  const widget = makeBaseWidget()
  widget.addAccessoryWidgetBackground = true
  widget.setPadding(2, 4, 2, 4)
  widget.backgroundColor = new Color("000000", 0)
  addText(widget, `CODEX · ${freshness.level === "fresh" ? "剩余额度" : `⚠ ${freshness.badge}`}`, Font.boldSystemFont(10), colors.primary)
  const five = usage.fiveHour ? `5H ${usage.fiveHour.remainingPercent}%` : "5H --"
  const week = usage.weekly ? `W ${usage.weekly.remainingPercent}%` : "W --"
  addText(widget, `${five} · ${week}`, Font.boldSystemFont(14), colors.primary)
  const reset = freshness.level !== "fresh" ? freshness.compactText : nearestResetLabel(usage, now)
  addText(widget, reset, Font.systemFont(9), freshnessColor(freshness, colors))
  return widget
}

function buildAccessoryCircular(usage, freshness, parameter, now) {
  const colors = palette()
  const widget = makeBaseWidget()
  widget.addAccessoryWidgetBackground = true
  widget.backgroundColor = new Color("000000", 0)
  widget.setPadding(2, 2, 2, 2)
  const wantsWeekly = String(parameter || "").toLowerCase() === "weekly"
  const title = wantsWeekly ? "W" : "5H"
  const window = wantsWeekly ? usage.weekly : usage.fiveHour
  const stack = widget.addStack()
  stack.layoutVertically()
  stack.centerAlignContent()
  stack.addSpacer()
  const expiredCycle = window && resetRemaining(window.resetAt, now).expired
  const warning = freshness.level !== "fresh" || expiredCycle
  addText(stack, `${warning ? "⚠ " : ""}${title}`, Font.boldSystemFont(9), colors.secondary)
  addText(stack, window ? `${window.remainingPercent}%` : "--", Font.boldSystemFont(17), freshnessColor(freshness, colors, colors.primary))
  if (warning) addText(stack, expiredCycle ? "待更新" : freshness.badge, Font.systemFont(8), colors.secondary)
  stack.addSpacer()
  return widget
}

function rendererName(family) {
  if (family === "medium") return "medium"
  if (family === "accessoryRectangular") return "accessoryRectangular"
  if (family === "accessoryCircular") return "accessoryCircular"
  return "small"
}

function previewMethodName(family) {
  switch (rendererName(family)) {
  case "accessoryRectangular": return "presentAccessoryRectangular"
  case "accessoryCircular": return "presentAccessoryCircular"
  case "small": return "presentSmall"
  default: return "presentMedium"
  }
}

function buildWidget(family, loaded, parameter, now = new Date()) {
  let widget
  if (!loaded.usage) {
    widget = noDataWidget(family)
  } else {
    const fresh = freshnessInfo(loaded.usage, loaded.isCache, now)
    switch (rendererName(family)) {
    case "medium": widget = buildMedium(loaded.usage, fresh, now); break
    case "accessoryRectangular": widget = buildAccessoryRectangular(loaded.usage, fresh, now); break
    case "accessoryCircular": widget = buildAccessoryCircular(loaded.usage, fresh, parameter, now); break
    default: widget = buildSmall(loaded.usage, fresh, now)
    }
  }
  // Official Scriptable run URL follows the actual script name, even if renamed.
  // Tapping opens Scriptable and rereads iCloud; it cannot force iOS to redraw.
  const runURL = URLScheme.forRunningScript()
  widget.url = `${runURL}${runURL.includes("?") ? "&" : "?"}family=${encodeURIComponent(rendererName(family))}&window=${encodeURIComponent(String(parameter || ""))}`
  return widget
}

function invocationOptions(configuration, parameters) {
  const query = parameters.queryParameters || {}
  return {
    family: !configuration.runsInWidget && query.family
      ? rendererName(query.family) : configuration.widgetFamily || "medium",
    parameter: !configuration.runsInWidget && typeof query.window === "string"
      ? query.window : parameters.widgetParameter,
  }
}

async function main() {
  let icloudManager = null
  let localManager = null
  try { localManager = FileManager.local() } catch (_) {}
  try { icloudManager = FileManager.iCloud() } catch (_) {}
  const loaded = await loadUsage(icloudManager, localManager)
  const { family, parameter } = invocationOptions(config, args)
  const widget = buildWidget(family, loaded, parameter)
  // Use the official default policy: no extra 15-minute floor, no polling hack.
  // iOS still determines the actual execution time; this is not realtime push.
  widget.refreshAfterDate = null
  if (config.runsInWidget) {
    Script.setWidget(widget)
  } else {
    if (loaded.error) {
      const alert = new Alert()
      alert.title = "Codex Meter 同步提示"
      alert.message = diagnosticMessage(loaded)
      alert.addAction("查看小组件")
      await alert.presentAlert()
    }
    await widget[previewMethodName(family)]()
  }
  Script.complete()
}

if (typeof FileManager === "undefined" && typeof module !== "undefined" && module.exports) {
  module.exports = {
    validateUsage,
    diagnosticMessage,
    loadUsage,
    freshnessInfo,
    resetLabel,
    resetDetailLabel,
    nearestResetLabel,
    rendererName,
    previewMethodName,
    buildWidget,
    invocationOptions,
  }
} else {
  await main()
}
