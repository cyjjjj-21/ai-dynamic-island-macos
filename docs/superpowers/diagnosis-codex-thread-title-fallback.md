# 诊断：Codex 线程标题回退到 "Codex 任务"

**日期：** 2026-04-17
**现象：** Codex 线程在灵动岛中统一显示为 "Codex 任务"，未按 plan 预期展示有意义的标题摘要。

## 根因

**Codex 的 title fallback 链在多个环节同时断裂，比 Claude 的问题更深。**

当前 `resolveCodexTitle` 的 title 来源优先级：

1. `promptCandidates`（经 `compactPromptCandidate` 压缩后的用户 prompt）→ 取最高优先级候选
2. `sessionIndexTitle`（即 `titleHint`，来自 `session_index.jsonl` 的 `thread_name`）→ 经 `isViableTitleCandidate` 质量门控
3. `workspaceLabel`（从 `cwd` 解析项目名）→ 经 `resolveWorkspaceLabel` 过滤
4. `"Codex 任务"` — 兜底

三个环节分别出了问题：

### 问题 1：`promptCandidates` 全部被质量门控拒绝

当前 `compactPromptCandidate` 的过滤规则过于激进：

- **前缀去噪**会剥掉 `继续`、`接着`、`帮我`、`请你`、`ok`、`go`、`1` 等常见短 prompt
- **`looksLikeExecutionMetaPrompt`** 会拒绝 `按这份 plan 开始 coding`、`开始实现`、`开始执行` 等指令型 prompt
- 剥完之后为空字符串，整个候选被丢弃

实际验证：主线程最近的用户输入是：

```
[0] ok，把我们刚刚讨论的形成一个详细的代码coding plan。
[1] 再讨论下你当前是怎么处理一个线程中的subagent的？
[2] 这个也合并到刚才到plan.md里，感觉有必要做
[3] 我觉得ok，你可以开始按这份plan进行coding，注意分阶段进行subagent审核。
[4] 把当前的假app关掉，打开你刚刚改动过的那一版app，我来审查一下
[5] 好的，那你准备具体怎么去做？
[6] go
```

- `[3]` "我觉得ok，你可以开始按这份plan进行coding..." → 被 `looksLikeExecutionMetaPrompt` 拒绝（含"开始" + 不含 topic needle）
- `[2]` "这个也合并到刚才到plan.md里" → 可能被当作执行指令拒绝
- `[4]` "把当前的假app关掉..." → 剥完前缀后可能超过 30 字截断
- `[0]`、`[1]`、`[5]`、`[6]` → 太短或被去噪剥光

**本质问题：长会话中，用户最近几轮 prompt 往往是跟进指令（"go"、"ok"、"继续"），真正的主题性内容在更早的 prompt 里。但 `compactPromptCandidate` 没有区分"这轮在做什么"和"这个线程的主题是什么"。**

### 问题 2：`sessionIndexTitle` 被 `isViableTitleCandidate` 拒绝

Codex `session_index.jsonl` 里的 `thread_name` 本身是很好的摘要来源（例如 "审查 Claude 线程标题 fallback"、"Review phase-2 implementation"），但很多条目包含 HTML 标签、乱码、截断（例如 "了解派生到本地与工作树含义」} PMID maybe? but must"），被 `isViableTitleCandidate` 的 HTML 正则或符号密度门控拒绝。

**问题不在门控本身（门控是必要的），在于没有对 `thread_name` 做轻量清洗后再检查。** 当前 `resolveCodexTitle` 是先调 `isViableTitleCandidate(sessionIndexTitle)` 再调 `sanitizeTitle`，但 `sanitizeTitle` 只做 `<br>` 替换和空白合并，不会清洗更复杂的 HTML 碎片。正确顺序应该是：先 `sanitizeTitle`，再 `isViableTitleCandidate`。

### 问题 3：`workspaceLabel` 对常见路径返回 nil

当 `cwd` 是 `/Users/chenyuanjie/developer` 时：

- `resolveWorkspaceLabel` 剥掉 "Users" + "chenyuanjie"（username）
- 剩下 `["developer"]`
- `"developer"` 在 `isContainerWorkspaceComponent` 中被判定为容器目录，返回 nil
- fallback 到 "Codex 任务"

同理，`/Users/chenyuanjie/developer/ai-dynamic-island-macos` 的 `.worktrees/visual-polish-steady-premium` 子路径可以正确提取，但如果 Codex 是从 `/Users/chenyuanjie/developer` 启动的（如上面验证的数据），就提取不到项目名。

## 改法

### 1. 修复 `sessionIndexTitle` 的清洗-验证顺序

**文件：** `AIIslandApp/Monitoring/ThreadTitleResolver.swift`

当前代码（line 40-49）：

```swift
if let sessionIndexTitle = sessionIndexTitle,
   isViableTitleCandidate(sessionIndexTitle)  // 先验证，后清洗
{
    return ResolvedThreadTitle(
        title: sanitizeTitle(sessionIndexTitle),  // 清洗在这里才做
        ...
    )
}
```

应改为：先 `sanitizeTitle`，再对清洗后的结果做 `isViableTitleCandidate`：

```swift
if let sessionIndexTitle = sessionIndexTitle {
    let cleaned = sanitizeTitle(sessionIndexTitle)
    if isViableTitleCandidate(cleaned) {
        return ResolvedThreadTitle(title: cleaned, ...)
    }
}
```

同时加强 `sanitizeTitle`，清洗常见 HTML 碎片（`」}`、`PMID`、trailing `...` 截断等）。

### 2. 提升早期主题性 prompt 的优先级

**文件：** `AIIslandApp/Monitoring/ThreadTitleResolver.swift`

当前 `promptCandidatePrecedes` 只看 `priority` 和 `index`（顺序），导致长会话中真正的主题性 prompt（早期、较长、描述性）被后来的短跟进指令挤出。

建议在 `PromptTitleCandidate` 中增加一个 `isTopicPrompt` 标记：

- 包含具体名词（项目名、功能名、技术术语）的长 prompt → `isTopicPrompt = true`
- 纯指令/跟进型 prompt → `isTopicPrompt = false`
- 在排序中，`isTopicPrompt` 的权重高于 `index`（时间顺序）

这样"请你接手我这个 ai dynamic island 方向，基于当前工程和最近思路..." 会胜过 "go"。

### 3. 放宽 `workspaceLabel` 对容器目录的判定

**文件：** `AIIslandApp/Monitoring/ThreadTitleResolver.swift`

当路径只剩容器目录时（如 `["developer"]`），不要直接返回 nil，而是再往上一层看是否还有非容器组件可用。或者，当所有其他 title 来源都失败时，即使 workspaceLabel 不够"有意义"也接受它，因为 `"developer"` 仍然比 `"Codex 任务"` 更有信息量。

更合理的做法：当 `workspaceLabel` 为 nil 且所有 title 候选都失败时，回退到 `cwd` 的最后一个非 username 组件，即使它是容器目录。

### 4. `compactPromptCandidate` 去噪规则精细化

**文件：** `AIIslandApp/Monitoring/ThreadTitleResolver.swift`

- `looksLikeExecutionMetaPrompt` 的 `topicNeedles` 列表太窄，导致包含技术关键词的执行指令也被拒绝（因为关键词没命中）。应该允许包含项目名/技术词的执行指令通过。
- 前缀去噪应该留下剥完后的剩余内容，而不是丢弃整个候选。当前逻辑：剥完前缀如果为空则丢弃，但"ok，把我们刚刚讨论的形成一个详细的代码coding plan"剥完"ok"后剩余"把我们刚刚讨论的形成一个详细的代码coding plan"，这其实是有意义的。

## 改进后的 Fallback 链

| 优先级 | 来源 | 例子 | 修复项 |
|--------|------|------|--------|
| 1 | `promptCandidates`（主题性优先） | "AI Dynamic Island 方向改进" | 改法 2、4 |
| 2 | `sessionIndexTitle`（先清洗后验证） | "审查 Claude 线程标题 fallback" | 改法 1 |
| 3 | `workspaceLabel`（放宽容器判定） | "developer" 或项目名 | 改法 3 |
| 4 | 兜底 | "Codex 任务" | — |

## 与 Claude 诊断的共性问题

两边共享同一个 `ThreadTitleResolver` 和 `resolveWorkspaceLabel`，所以改法 1（清洗-验证顺序）和改法 3（放宽 workspace 判定）是两边都受益的。

Codex 独有的问题是 `compactPromptCandidate` 的主题识别和去噪逻辑（改法 2、4），Claude 独有的问题是数据提取层太薄（Claude 诊断中的 `last-prompt` 提取）。
