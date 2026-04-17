# 诊断：Claude 线程标题回退到 "Claude Code 任务"

**日期：** 2026-04-17
**现象：** Claude Code 线程在灵动岛中统一显示为 "Claude Code 任务"，未按 plan 预期展示有意义的标题摘要。

## 根因

**Claude 的 title 数据提取层太薄，fallback 链在第二步断裂。**

当前 `resolveClaudeTitle` 的 title 来源优先级：

1. `taskSummary` — 只有 transcript 里存在 `task-summary` 类型条目时才有值
2. `workspaceLabel` — 从 `cwd` 路径解析项目名
3. `"Claude Code 任务"` — 兜底

问题出在：

- **`taskSummary` 在绝大多数真实 session 里根本不存在。** 实际验证当前 session transcript，entry 类型只有 `assistant, user, last-prompt, permission-mode, system, attachment, file-history-snapshot`，没有 `task-summary`。
- `cwd` 为 `/Users/chenyuanjie`，`resolveWorkspaceLabel` 正确地拒绝了 username-only 路径，返回 nil。
- 于是直接掉到 `"Claude Code 任务"` 兜底。

**但 transcript 里明明有 `last-prompt` 条目，内容就是用户的核心意图：**

```json
{
  "type": "last-prompt",
  "lastPrompt": "我现在桌面上运行着一个虚拟的ai-灵动岛程序，先把这个程序关掉..."
}
```

而 `ClaudeCodeSnapshotParser` 把 `last-prompt` 归类为 noise 直接丢弃了（`isNoiseEntry` 里明确排除）。

**对比 Codex 的做法：** Codex 解析器专门提取了 `promptCandidates` 数组，传给 `ThreadTitleResolver.resolveCodexTitle()` 做 prompt 摘要。Claude 这边完全没有类似的提取逻辑。

## 改法

核心思路：**把 Claude 的用户 prompt 提取出来，作为 `taskSummary` 之下的第二优先 title 来源。**

### 1. 扩展 `ClaudeCodeTranscriptSnapshot`

**文件：** `AIIslandApp/Monitoring/ClaudeCodeSnapshotParser.swift`

新增两个字段：

```swift
struct ClaudeCodeTranscriptSnapshot: Equatable, Sendable {
    let fallbackState: AgentGlobalState
    let modelLabel: String?
    let taskSummary: String?
    let hasInProgressToolUse: Bool
    let lastPrompt: String?          // 新增
    let firstUserPrompt: String?     // 新增
}
```

在 `parseTranscriptTail()` 中：
- 从 `type: "last-prompt"` 条目提取 `lastPrompt`
- 从第一个 `type: "user"` + `userType: "external"` 的 `text` content block 提取 `firstUserPrompt`
- `isNoiseEntry` 不再无条件丢弃 `last-prompt`，至少在丢弃前把值提取出来

### 2. 扩展 `ThreadTitleResolver.resolveClaudeTitle()`

**文件：** `AIIslandApp/Monitoring/ThreadTitleResolver.swift`

在 `taskSummary` 失败后，增加 prompt 压缩分支，复用 Codex 侧已有的 `compactPromptCandidate` 逻辑：

```swift
static func resolveClaudeTitle(
    taskSummary: String?,
    lastPrompt: String?,          // 新增
    firstUserPrompt: String?,     // 新增
    waitingFor: String?,
    workspacePath: String?
) -> ResolvedThreadTitle
```

内部优先级链：

1. `taskSummary` — 有则用，最强来源
2. prompt 压缩 — 从 `lastPrompt` / `firstUserPrompt` 中提取，复用 `compactPromptCandidate` 的去噪、截断、质量门控
3. `workspaceLabel` — 从路径解析
4. `"Claude Code 任务"` — 兜底

### 3. 传递新字段到 arbitrator

**文件：** `AIIslandApp/Monitoring/ClaudeMonitorArbitrator.swift`

在 `evaluate()` 中把 `snapshot.transcript.lastPrompt` 和 `snapshot.transcript.firstUserPrompt` 传入 `ThreadTitleResolver.resolveClaudeTitle()`。

## 改进后的 Fallback 链

| 优先级 | 来源 | 例子 |
|--------|------|------|
| 1 | `taskSummary` | （稀有，有则用） |
| 2 | 用户 prompt 压缩 | "关闭灵动岛并构建最新版" |
| 3 | `workspaceLabel` | "ai-dynamic-island-macos" |
| 4 | 兜底 | "Claude Code 任务" |

## 为什么这样改

- **复用已有逻辑：** Codex 侧的 `compactPromptCandidate` 已经验证了去噪（`继续`/`帮我`/`please` 等前缀剥离）、截断（30 字上限）、质量门控（HTML/符号密度/replacement 字符检测），不需要重新发明。
- **最小改动面：** 不改 domain model（`AgentThread`），不改 UI 层，只扩展数据提取和 resolver 的输入。
- **解决实际痛点：** `last-prompt` 条目在几乎每个 Claude session 里都存在，是最高频可用的 title 来源，当前被白白丢弃了。
