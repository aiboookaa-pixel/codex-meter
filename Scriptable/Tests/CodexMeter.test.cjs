const assert = require("assert")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

class Element {
  constructor() { this.children = [] }
  addStack() { const value = new Element(); this.children.push(value); return value }
  addText(value) { const text = { value }; this.children.push(text); return text }
  addSpacer() { this.children.push({ spacer: true }) }
  layoutHorizontally() {}
  layoutVertically() {}
  centerAlignContent() {}
  setPadding() {}
}

global.ListWidget = class extends Element {
  async presentSmall() {}
  async presentMedium() {}
}
global.Color = class {
  constructor(hex, alpha) { this.hex = hex; this.alpha = alpha }
  static dynamic(light, dark) { return { light, dark } }
}
global.Font = {
  systemFont: size => ({ size, weight: "regular" }),
  semiboldSystemFont: size => ({ size, weight: "semibold" }),
  boldSystemFont: size => ({ size, weight: "bold" }),
}
global.Size = class { constructor(width, height) { this.width = width; this.height = height } }
global.DateFormatter = class {
  string(date) { return date.toISOString().slice(0, 16) }
}
const scriptPath = process.env.CODEXMETER_SCRIPT || path.join(__dirname, "../CodexMeter.js")
const scriptSource = fs.readFileSync(scriptPath, "utf8")
const context = {
  module: { exports: {} },
  console,
  ListWidget: global.ListWidget,
  Color: global.Color,
  Font: global.Font,
  Size: global.Size,
  DateFormatter: global.DateFormatter,
  URLScheme: { forRunningScript: () => "scriptable:///run?scriptName=My%20Meter" },
}
vm.runInNewContext(`(async () => {\n${scriptSource}\n})()`, context, { filename: scriptPath })
const widget = context.module.exports
const samplePath = path.join(__dirname, "../fixtures/usage.sample.json")
const sample = JSON.parse(fs.readFileSync(samplePath, "utf8"))

class MemoryFileManager {
  constructor(files = {}, downloadError = null) {
    this.files = { ...files }
    this.downloadError = downloadError
  }
  documentsDirectory() { return "/documents" }
  joinPath(left, right) { return `${left}/${right}` }
  fileExists(file) { return Object.prototype.hasOwnProperty.call(this.files, file) }
  async downloadFileFromiCloud() { if (this.downloadError) throw this.downloadError }
  readString(file) { return this.files[file] }
  writeString(file, value) { this.files[file] = value }
  createDirectory(folder) { this.files[folder] = "directory" }
}

function textValues(element) {
  const values = []
  for (const child of element.children || []) {
    if (Object.prototype.hasOwnProperty.call(child, "value")) values.push(child.value)
    else values.push(...textValues(child))
  }
  return values
}

async function run() {
  const valid = widget.validateUsage(sample)
  assert.strictEqual(valid.schemaVersion, 1)
  assert.strictEqual(valid.fiveHour.remainingPercent, 72)
  assert.strictEqual(valid.weekly.remainingPercent, 81)

  assert.throws(() => widget.validateUsage({ ...sample, schemaVersion: 2 }))
  assert.throws(() => widget.validateUsage({ ...sample, sourceLastSuccessfulSync: "bad" }))
  assert.doesNotThrow(() => widget.validateUsage({ ...sample, fiveHour: null, weekly: null }))

  const dataFile = "/documents/CodexMeter/usage.json"
  const cacheFile = "/documents/CodexMeter/last-valid-usage.json"
  const live = await widget.loadUsage(new MemoryFileManager({ [dataFile]: JSON.stringify(sample) }), new MemoryFileManager())
  assert.strictEqual(live.isCache, false)

  const newer = { ...sample, sourceLastSuccessfulSync: "2026-10-02T08:01:00Z", exportedAt: "2026-10-02T08:01:01Z" }
  const olderCloud = { ...sample, sourceLastSuccessfulSync: "2026-10-02T08:00:00Z", exportedAt: "2026-10-02T08:00:01Z" }
  const newestCache = new MemoryFileManager({ [cacheFile]: JSON.stringify(newer) })
  const lagging = await widget.loadUsage(new MemoryFileManager({ [dataFile]: JSON.stringify(olderCloud) }), newestCache)
  assert.strictEqual(lagging.usage.sourceLastSuccessfulSync, newer.sourceLastSuccessfulSync)
  assert.strictEqual(lagging.isCache, true)
  assert.strictEqual(lagging.error, "lagging")
  assert.strictEqual(JSON.parse(newestCache.files[cacheFile]).sourceLastSuccessfulSync, newer.sourceLastSuccessfulSync)
  assert.match(widget.diagnosticMessage(lagging), /iCloud.*较旧/)
  const newerState = { ...newer, exportedAt: "2026-10-02T08:02:00Z", sourceStatus: "offline" }
  const stateUpdate = await widget.loadUsage(new MemoryFileManager({ [dataFile]: JSON.stringify(newerState) }), newestCache)
  assert.strictEqual(stateUpdate.usage.sourceStatus, "offline")
  assert.strictEqual(stateUpdate.isCache, false)
  const freshSource = { ...newer, sourceLastSuccessfulSync: "2026-10-02T08:03:00Z", exportedAt: "2026-10-02T08:03:01Z" }
  const lateExport = { ...olderCloud, exportedAt: "2026-10-02T08:04:00Z" }
  const sourceWins = await widget.loadUsage(new MemoryFileManager({ [dataFile]: JSON.stringify(freshSource) }), new MemoryFileManager({ [cacheFile]: JSON.stringify(lateExport) }))
  assert.strictEqual(sourceWins.usage.sourceLastSuccessfulSync, freshSource.sourceLastSuccessfulSync)

  const missing = await widget.loadUsage(new MemoryFileManager(), new MemoryFileManager())
  assert.strictEqual(missing.usage, null)

  const cachedManager = new MemoryFileManager({ [cacheFile]: JSON.stringify(sample) })
  const malformed = await widget.loadUsage(new MemoryFileManager({ [dataFile]: "{" }), cachedManager)
  assert.strictEqual(malformed.isCache, true)

  const downloadFailed = await widget.loadUsage(
    new MemoryFileManager({ [dataFile]: JSON.stringify(sample) }, new Error("iCloud unavailable")),
    new MemoryFileManager({ [cacheFile]: JSON.stringify(sample) })
  )
  assert.strictEqual(downloadFailed.isCache, true)
  const badPathManager = new MemoryFileManager()
  badPathManager.documentsDirectory = () => { throw new Error("iCloud directory unavailable") }
  const badPath = await widget.loadUsage(badPathManager, cachedManager)
  assert.strictEqual(badPath.isCache, true)
  assert.match(widget.diagnosticMessage(missing), /Mac/)
  assert.match(widget.diagnosticMessage(malformed), /格式/)
  assert.match(widget.diagnosticMessage(downloadFailed), /iCloud/)

  const staleNow = new Date(new Date(sample.sourceLastSuccessfulSync).getTime() + 7 * 3600 * 1000)
  assert.strictEqual(widget.freshnessInfo(sample, false, staleNow).level, "expired")
  assert.match(widget.freshnessInfo({ ...sample, sourceStatus: "offline" }, false, new Date(sample.sourceLastSuccessfulSync)).text, /离线/)
  assert.match(widget.freshnessInfo({ ...sample, sourceStatus: "refreshing" }, false, new Date(sample.sourceLastSuccessfulSync)).text, /更新中/)
  const staleOffline = widget.freshnessInfo({ ...sample, sourceStatus: "offline" }, false, new Date(new Date(sample.sourceLastSuccessfulSync).getTime() + 3 * 3600 * 1000))
  assert.strictEqual((staleOffline.text.match(/⚠/g) || []).length, 1)
  assert.strictEqual(widget.resetLabel("2026-01-01T00:00:00Z", new Date("2026-01-01T00:01:00Z")), "等待 Mac 更新")
  assert.strictEqual(widget.resetLabel("2026-01-01T01:00:00Z", new Date("2026-01-01T00:00:00Z")), "1小时0分后")
  assert.strictEqual(widget.freshnessInfo({ ...sample, exportedAt: staleNow.toISOString() }, false, staleNow).level, "expired")
  assert.match(widget.resetDetailLabel(sample.fiveHour.resetAt, new Date(sample.sourceLastSuccessfulSync)), / · /)
  assert.strictEqual(widget.resetDetailLabel("2026-01-01T00:00:00Z", new Date("2026-01-01T00:01:00Z")), "等待 Mac 更新")

  const families = ["small", "medium", "accessoryRectangular", "accessoryCircular"]
  assert.deepStrictEqual(families.map(widget.rendererName), families)
  assert.deepStrictEqual(families.map(widget.previewMethodName), ["presentSmall", "presentMedium", "presentAccessoryRectangular", "presentAccessoryCircular"])
  for (const family of families) {
    const rendered = widget.buildWidget(family, { usage: valid, isCache: false }, "weekly", new Date(sample.sourceLastSuccessfulSync))
    assert.ok(rendered instanceof ListWidget)
    const tap = new URL(rendered.url)
    assert.strictEqual(tap.protocol, "scriptable:")
    assert.strictEqual(tap.searchParams.get("scriptName"), "My Meter")
    assert.strictEqual(tap.searchParams.get("family"), family)
    assert.strictEqual(tap.searchParams.get("window"), "weekly")
  }
  for (const family of families) {
    for (const state of ["offline", "cached", "refreshing", "codexNotFound", "appServerUnavailable", "dataUnavailable", "error"]) {
      const rendered = widget.buildWidget(family, { usage: { ...valid, sourceStatus: state }, isCache: false }, "weekly", new Date(sample.sourceLastSuccessfulSync))
      assert.ok(textValues(rendered).length > 0)
      assert.match(textValues(rendered).join(" "), /⚠|更新中/)
    }
    for (const windows of [{ fiveHour: null }, { weekly: null }, { fiveHour: null, weekly: null }]) {
      const rendered = widget.buildWidget(family, { usage: { ...valid, ...windows }, isCache: false }, "weekly", new Date(sample.sourceLastSuccessfulSync))
      assert.ok(textValues(rendered).length > 0)
    }
  }
  for (const family of families) {
    const cached = widget.buildWidget(family, { usage: valid, isCache: true }, "weekly", new Date(sample.sourceLastSuccessfulSync))
    assert.match(textValues(cached).join(" "), /缓存|⚠/)
    const expired = widget.buildWidget(family, { usage: valid, isCache: false }, "weekly", staleNow)
    assert.match(textValues(expired).join(" "), /过期|⚠/)
  }
  const overdue = { ...valid, fiveHour: { ...valid.fiveHour, resetAt: "2026-01-01T00:00:00Z" } }
  const overdueCircle = widget.buildWidget("accessoryCircular", { usage: overdue, isCache: false }, "fiveHour", new Date(sample.sourceLastSuccessfulSync))
  assert.match(textValues(overdueCircle).join(" "), /待更新/)
  assert.ok(widget.freshnessInfo({ ...sample, sourceStatus: "offline" }, false, new Date(sample.sourceLastSuccessfulSync)).compactText.includes("Mac 离线"))
  const partial = widget.buildWidget("medium", { usage: { ...valid, weekly: null }, isCache: false }, null, new Date(sample.sourceLastSuccessfulSync))
  assert.ok(textValues(partial).includes("--"))

  const circularEmpty = widget.buildWidget("accessoryCircular", { usage: null, isCache: false }, null)
  assert.deepStrictEqual(textValues(circularEmpty), ["C", "--"])
  assert.strictEqual(new URL(circularEmpty.url).searchParams.get("family"), "accessoryCircular")

  assert.deepStrictEqual(JSON.parse(JSON.stringify(widget.invocationOptions(
    { runsInWidget: false, widgetFamily: null },
    { queryParameters: { family: "accessoryCircular", window: "weekly" } }
  ))), { family: "accessoryCircular", parameter: "weekly" })
  assert.deepStrictEqual(JSON.parse(JSON.stringify(widget.invocationOptions(
    { runsInWidget: true, widgetFamily: "small" },
    { widgetParameter: "fiveHour", queryParameters: { family: "medium", window: "weekly" } }
  ))), { family: "small", parameter: "fiveHour" })

  for (const runsInWidget of [true, false]) {
    let alerts = 0
    let completed = 0
    let widgets = 0
    const execution = {
      ...context,
      FileManager: { iCloud() { throw new Error("unavailable") }, local() { return new MemoryFileManager() } },
      config: { runsInWidget, widgetFamily: "medium" }, args: {},
      Alert: class { addAction() {} async presentAlert() { alerts += 1 } },
      Script: { setWidget(value) { widgets += 1; assert.strictEqual(value.refreshAfterDate, null) }, complete() { completed += 1 } },
    }
    await vm.runInNewContext(`(async () => {\n${scriptSource}\n})()`, execution)
    assert.strictEqual(alerts, runsInWidget ? 0 : 1)
    assert.strictEqual(widgets, runsInWidget ? 1 : 0)
    assert.strictEqual(completed, 1)
  }

  if (process.env.CODEXMETER_REAL_SNAPSHOT) {
    const real = widget.validateUsage(JSON.parse(fs.readFileSync(process.env.CODEXMETER_REAL_SNAPSHOT, "utf8")))
    for (const family of families) {
      assert.ok(textValues(widget.buildWidget(family, { usage: real, isCache: false }, "weekly")).length > 0)
    }
    console.log(`Real snapshot parsed: schema ${real.schemaVersion}, status ${real.sourceStatus}, 5H ${real.fiveHour?.remainingPercent ?? "unavailable"}%, W ${real.weekly?.remainingPercent ?? "unavailable"}%`)
  }

  console.log("CodexMeter.js: all contract, error, freshness, reset, and layout checks passed")
}

run().catch(error => {
  console.error(error)
  process.exitCode = 1
})
