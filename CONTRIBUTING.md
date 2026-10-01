# 贡献指南

欢迎提交 Issue 和 Pull Request。请先描述问题及复现步骤，再做小范围修改。

## 开发

打开 CodexMeter.xcodeproj，选择 CodexMeter Scheme。运行 README 中的 XCTest 与 Node 测试；修改手机逻辑需要覆盖四种尺寸、空窗口、旧数据、重置过期和 iCloud 失败。

纯逻辑使用合成测试数据，不要求维护者账号，不把真实额度写入 fixture。不直接把协议通信写进 SwiftUI View。没有必要不要加第三方依赖，不为测试或同步改动用户网络、官方客户端配置和 App Sandbox 策略。

## 提交前

- 测试通过，说明实机验证与模拟验证的边界。
- 不提交 usage.json、Token、Cookie、bookmark、个人路径、证书、缓存、.DS_Store、build 或 dist。
- 保持兼容 macOS 13+ 和 schemaVersion 1；协议变化先补兼容测试。
- UI 保持原生、清晰；旧数据必须显式标识。
- 请不要提交网页抓取、认证提取、自动 Reset、网络工具或不相关扩展。

贡献的代码将按本项目 MIT 许可证分发。请只提交你有权贡献的代码／资源，保留必要的第三方许可说明。
