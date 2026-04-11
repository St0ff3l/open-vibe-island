# Qwen 独立 Hook 与进程守护修复说明

本文档记录了将 `qwen-cli` 的 Hook 逻辑从 `claude` 逻辑中彻底解耦，并修复 UI 闪退、提示“没有打开的终端会话”的核心操作与思路。

## 故障现象与原因分析

**现象**：在终端执行 Qwen 命令时，Open Island 的 UI 会短暂出现（约 2 秒），随后变成“没有打开的终端会话”（No open terminal sessions），并在后续执行工具时不断闪烁。

**根本原因**：
Open Island 的架构分为两部分：
1. **Hook 接收器** (`OpenIslandHooksCLI`)：负责接收 CLI 传来的 JSON，并在 UI 创建一个 Session。
2. **本地进程守护** (`ProcessMonitoringCoordinator` / `ActiveAgentProcessDiscovery`)：负责每秒扫描 macOS 的进程表（`ps` / `lsof`），确认这个 Session 对应的底层进程（Node/Qwen）和终端窗口（Ghostty/iTerm）是否还活着。

由于我们把 Qwen 的 Payload 从 Claude 独立了出来，导致**进程守护系统完全不认识 Qwen**，从而引发了一系列连锁反应：UI 刚根据 Hook 创建了 Qwen 会话，进程守护系统扫描一圈发现“找不到匹配的 Qwen 进程和终端”，于是立刻判定会话已死亡/终端已关闭，导致 UI 消失。

## 详细修复步骤

为了彻底解决这个问题，我们在整个链路的 5 个关键节点进行了修改：

### 1. Hook 负载解析与 CLI 阻塞修复
* **文件**：`Sources/OpenIslandCore/QwenHooks.swift`, `Sources/OpenIslandHooks/OpenIslandHooksCLI.swift`
* **操作**：
  * 为 `QwenHookPayload` 添加了 `CodingKeys`，将 CLI 传来的 `snake_case`（如 `hook_event_name`）正确映射为 Swift 的 `camelCase`，修复了解析失败的问题。
  * 在 `OpenIslandHooksCLI.swift` 中，Qwen 分支处理完毕后，强制向标准输出写入 `{"continue":true,"suppressOutput":true}\n`。这是因为 Qwen CLI 会阻塞等待这个 JSON 返回，如果不写，终端会卡死。

### 2. 终端上下文注入 (Terminal Context Injection)
* **文件**：`Sources/OpenIslandCore/QwenHooks.swift`
* **操作**：
  * 将 `ClaudeHooks.swift` 中的 `withRuntimeContext` 逻辑完整移植到了 `QwenHooks.swift`。
  * **为什么关键**：Hook JSON 默认只包含 `cwd` 和 `session_id`。如果不注入 `terminalTTY`（如 `/dev/ttys001`）和 `terminalApp`（如 `Ghostty`），Open Island 就不知道把这个 UI 挂载到哪个终端窗口上。

### 3. Node 进程识别修复 (Process Discovery)
* **文件**：`Sources/OpenIslandApp/ActiveAgentProcessDiscovery.swift`
* **操作**：
  * 修改了 `isClaudeProcess` 方法。
  * **为什么关键**：在 macOS 的 `ps` 输出中，Qwen 经常是以 `node /Users/.../bin/qwen` 的形式运行的。原本的代码只检查第一个单词是不是 `claude` 或 `qwen`，导致所有 `node` 开头的进程被直接忽略。修改后，它能正确识别 `node` 后面的 `qwen` 参数，从而让进程扫描器抓取到 Qwen 进程。

### 4. 进程与会话保活匹配 (Process Monitoring Coordinator)
* **文件**：`Sources/OpenIslandApp/ProcessMonitoringCoordinator.swift`
* **操作**：
  * 全局将特判 `session.tool == .claudeCode` 的地方扩充为 `(session.tool == .claudeCode || session.tool == .qwenCode)`。
  * 引入了**后缀匹配** (`hasSuffix`)：Qwen CLI 传来的 `session_id` 是 `project-xxxx-xxxx...`，但本地扫描 `transcript.jsonl` 提取出的 ID 只有 `xxxx-xxxx...`。将严格相等（`==`）改为允许后缀匹配，解决了 ID 匹配不上的问题。
  * 将 Qwen 加入到了多重匹配（Multi-pass matching）逻辑中：即使 Session ID 没对上，只要 Qwen 进程的 `TTY` 和当前路径（`CWD`）与 Hook 传来的信息一致，就强行判定进程存活，确保 UI 永不消失。

### 5. 终端窗口挂载状态 (Terminal Session Attachment Probe)
* **文件**：`Sources/OpenIslandApp/TerminalSessionAttachmentProbe.swift`
* **操作**：
  * 同样将大量硬编码的 `.claudeCode` 检查扩充以包含 `.qwenCode`。
  * **为什么关键**：这个文件专门决定 UI 是否要显示“没有打开的终端会话”。之前因为忽略了 `.qwenCode`，系统默认认定 Qwen 没有依附任何有效终端。修复后，UI 能够准确识别 Qwen 所在的终端窗口并正常吸附。

## 总结

现在的 Qwen Hook 链路已经成为一条**一等公民 (First-class citizen)** 链路。它不仅在 Hook 解析层独立（避免被 Claude 复杂的 Tool/Thinking 状态机干扰），在底层的进程守护、终端发现、UI 挂载层面也享受了与 Claude 完全同等级的存活保障（Liveness Guarantee）。