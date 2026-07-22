# ToolbarMonitor

原生 SwiftUI macOS 菜单栏系统监视器。菜单栏实时显示 CPU、内存利用率、上下叠放的下载/上传速度，以及今日 AI Agent Token 用量；点击后可查看 Token、系统和网络明细。

## Token 统计

- 账户额度由应用内置的 TokenTracker 额度模块直接读取各供应商认证和额度接口，不依赖 TokenTrackerBar 应用或其本地服务。
- 内置额度模块采用 `mm7894215/TokenTracker` 0.83.6 的 MIT 授权源码，保留许可证并通过本机 Node.js 按需执行，不常驻额外端口。
- 优先调用本机 `tokscale`，统一统计 Codex、Claude Code、Gemini、OpenCode、Cursor、Antigravity 等 Agent。
- Antigravity 会定期通过 `tokscale antigravity sync` 从正在运行的语言服务器 RPC 同步权威用量，再读取其标准化缓存；不会把工具 span 或累计指标重复计数。
- 没有安装 `tokscale` 时，自动回退读取 Codex、Claude、Gemini 本地会话，以及已存在的 tokscale Antigravity 缓存。
- 弹窗提供今日、7 天、30 天汇总，并按 Agent、模型和输入/输出/缓存/推理 Token 展示明细。统计结果只保留数量、模型和时间，不保存或展示对话正文。

## 运行

1. 用 Xcode 打开 `ToolbarMonitor.xcodeproj`。
2. 选择 `My Mac`，点击 Run。
3. 应用不会显示在 Dock；请从菜单栏的波形图标打开详情。

要求 macOS 14 或更高版本。CPU、内存和网络接口数据均通过 macOS 本机 API 读取，不需要额外权限。建议安装 `tokscale` 以获得完整 Agent 覆盖和 Antigravity 实时同步。
