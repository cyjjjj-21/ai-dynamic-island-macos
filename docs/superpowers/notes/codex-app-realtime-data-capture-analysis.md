# Codex App 实时信息流抓取分析

**分析日期**: 2026-04-11  
**修订**: 2026-04-11（勘误引用、补全 schema 说明、JSONL/`tokens_used` 措辞）  
**分析目标**: 评估从 Codex App 获取实时状态信息的可行性  
**数据来源**: `~/.codex/state_5.sqlite`, `~/.codex/sessions/`, Codex 开源侧 `codex-rs/state`（rollout → SQLite 镜像逻辑）

---

## 1. 背景与对比

### Claude Code 的优势

Claude Code 能提供较细的实时状态，常见机制包括（**具体路径与字段以本机安装版本为准**）：

- **实时会话文件**: `~/.claude/sessions/<pid>.json`
  - 常包含 `status`: `"busy" | "idle" | "waiting"` 一类枚举
  - 常包含 `waitingFor`: 等待用户的说明
  - 常包含 `updatedAt`: 时间戳
  - 文件随进程更新，适合轮询或监听

- **桥接文件**: `/tmp/claude-ctx-<sessionId>.json`
  - 常由 **StatusLine** 类钩子写出
  - 可包含 `used_pct` 等上下文占用指标

> **说明**: 上述为与 Codex 对比时的「能力参照」，不是本文对 Anthropic 产品的正式规格承诺；集成前请在目标版本上打开样例文件核对字段名。

### Codex 的局限

Codex 以 Electron 应用交付，**未提供与 Claude Code 会话 JSON 等价的、文档化的实时状态 API**。下文说明能从磁盘读到什么，以及为何仍不足以代表「当前这一刻 agent 在干什么」。

---

## 2. SQLite 数据源分析 (`~/.codex/state_5.sqlite`)

### 2.1 数据库角色（为何不是实时状态机）

开源组件 `codex-rs/state` 将 SQLite 描述为 **rollout 元数据的本地镜像**：从各 Thread 对应的 **JSONL rollout** 中解析事件，合并为 `ThreadMetadata` 再写入库。  
因此：**库表反映的是「已从 rollout 观察到的元数据」**，不是 UI 内存里的细粒度状态机；也没有类似 `busy | waiting` 的权威列。

文件名 `state_5.sqlite` 与内部 **state DB 版本号 5**（`STATE_DB_VERSION`）对应；若未来版本升级，文件名可能变为 `state_6.sqlite` 等，需以 `~/.codex` 下实际文件为准。

### 2.2 数据库结构：`threads` 表

下表列出 **集成时最常关心的列**，以及迁移里出现的**其余重要列**。新增列会随 Codex 版本增加，**以本机 `PRAGMA table_info(threads);` 为准**。

**常用列（监控/UI）**

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | TEXT | Thread UUID，主键 |
| `title` | TEXT | 线程标题（通常来自首条用户消息等推导） |
| `first_user_message` | TEXT | 首条用户消息摘要（可为空串，视数据） |
| `model` | TEXT | 模型标识（若当前 schema 含该列；见下） |
| `model_provider` | TEXT | 提供商（如 `openai`） |
| `cwd` | TEXT | 工作目录 |
| `tokens_used` | INTEGER | 见 2.4，**不是** context 窗口占用率 |
| `created_at` | INTEGER | 创建时间 (Unix 时间戳) |
| `updated_at` | INTEGER | 最后更新时间 (Unix 时间戳) |
| `archived` | INTEGER | 是否归档 (0=活跃, 1=归档) |
| `source` | TEXT | 来源 (`cli` / `gui` 等) |
| `memory_mode` | TEXT | 记忆模式（若迁移已加入；默认可能为 `enabled`） |
| `reasoning_effort` | TEXT | 推理强度（若 schema 含该列） |

**其余列（策略、路径、Git、子 Agent）**

| 字段 | 说明 |
|------|------|
| `rollout_path` | 对应该线程的 rollout 文件路径 |
| `sandbox_policy` | 沙箱策略 |
| `approval_mode` | 审批/自动批准策略 |
| `has_user_event` | 是否已观察到用户事件 |
| `archived_at` | 归档时间 |
| `git_sha` / `git_branch` / `git_origin_url` | 会话关联的 Git 信息 |
| `cli_version` | 创建会话的 CLI 版本 |
| `agent_nickname` / `agent_role` | 子 Agent / 角色类元数据（可选） |

另有关联表 **`thread_dynamic_tools`**（按 `thread_id` 挂动态工具定义），一般不作为「实时状态」数据源。

### 2.3 能获取的信息

```sql
-- 获取活跃线程列表（示例）
SELECT id, title, model, tokens_used, updated_at
FROM threads
WHERE archived = 0
ORDER BY updated_at DESC;
```

若某环境无 `model` 列，请去掉该列或改用 `PRAGMA table_info` 确认。

**典型可获得数据**：

- Thread 列表与排序（按 `updated_at`）
- 标题 / 首条消息相关字段
- 模型与 provider（列存在时）
- 工作目录
- **Rollout 侧同步的 token 用量字段**（含义见下节）
- 最后更新时间

活跃线程数量因使用习惯差异很大（例如长期不归档会出现大量 `archived=0`），文中不再写死个数。

### 2.4 缺失的关键信息

| 信息 | SQLite 中是否存在 | 说明 |
|------|------------------|------|
| **实时 Agent 状态** | ❌ 不存在 | 无 `status` 列区分「思考中 / 工具中 / 空闲」 |
| **当前 Context 占用比例** | ❌ 不存在 | 无「当前窗口已用 / 上限」类持久化字段 |
| **Quota 额度** | ❌ 不存在 | 如周额度等通常不在此库 |
| **进程 PID** | ❌ 不存在 | 无法直接与系统进程绑定 |
| **等待用户输入** | ❌ 不存在 | 无等价 `waitingFor` |
| **当前焦点 Thread** | ❌ 不存在 | 无法从库得知 GUI 当前选中标签 |

### 2.5 核心问题

**问题 1: 无法判断实时状态**

仅有 `updated_at` 等时间戳时的启发式示例：

```swift
// 伪代码：基于时间差的推测（易误判，仅作「最近活动」暗示）
let timeSinceUpdate = now - thread.updated_at
if timeSinceUpdate < 60 {
    state = .recentlyActive
} else if timeSinceUpdate < 300 {
    state = .possiblyActive
} else {
    state = .idle
}
```

**局限**：无法区分「正在生成」「等待用户」「已结束」；网络、用户暂停、后台任务都会干扰。

**问题 2: `tokens_used` 不是 Context 使用率**

在 `codex-rs/state` 的 `extract.rs` 中，`tokens_used` 来自 rollout 里的 **`EventMsg::TokenCount`**，取 `total_token_usage.total_tokens` 写入元数据。它是 **协议里上报的用量类指标**，用于同步到 DB；**不是**「当前上下文窗口填充百分比」。  
GUI 若展示 context 比例，通常在 **渲染层 / 内存状态** 中计算，**不保证**写入这份 SQLite。

```sql
-- 示例：大数字多为长期会话上的用量累计，勿直接当「条百分比」
-- tokens_used: 90888158
```

**问题 3: 多 Thread 仲裁**

多个 `archived=0` 的线程并存时，只能自行约定：例如按 `updated_at` 取 Top N；**无法**从库得知用户当前正在查看哪一条。

---

## 3. JSONL 事件文件分析 (`~/.codex/sessions/`)

### 3.1 文件结构

```
~/.codex/sessions/
├── 2026/
│   ├── 03/
│   └── 04/
│       └── 11/
│           └── <uuid>.jsonl
```

实际目录层级以本机为准（年/月/日 或策略变更时可能不同）。

### 3.2 能获取的信息

JSONL 为 **按行追加** 的 rollout / 事件记录，可回溯用户消息、助手输出、工具调用等。**每条记录的 `type` 由 `codex_protocol` 等定义，且随版本演进**；下列名称仅为常见/示例性描述，**集成前请对样例文件做 `jq`/`grep` 统计实际 `type` 分布**。

- 用户消息、助手消息、工具调用等（具体 tag 可能是 `snake_case` 或 `kebab-case`）
- 部分版本或导出路径下可能出现 **任务摘要、配额刷新** 类事件；是否在文件中出现、字段长什么样，**以本机 JSONL 为准**（不宜在文档中写死为唯一字符串）

### 3.3 关键局限

- **非广播**：追加写 ≠ 当前帧状态；末尾几行也未必等于「此刻 UI 状态」。
- **缓冲**：进程/OS 缓冲可能导致 tail 略滞后。
- **无法回答**：「这一秒 agent 正在执行哪一步」——除非自行根据事件流推断，且仍有延迟与丢尾风险。

**用户反馈（需求侧）**：

> 「用 jsonl 抓状态我不推荐，没有实时性；需要实时知道每个 thread 上 agent 的状态。」

与上文技术判断一致。

---

## 4. UI 抓取方案分析 (Accessibility API)

### 4.1 技术可行性

- macOS 上可通过 `AXUIElement` 读取窗口标题、部分控件文案或列表。
- Electron 应用的可访问性树 **往往较稀疏**；Web 视图内动态文案未必映射为稳定 AX 节点。

### 4.2 能获取的信息

- 窗口标题、部分侧栏（若暴露）
- 当前选中项（**不保证**稳定）
- 难以依赖：细粒度 agent 状态、context 百分比、quota

### 4.3 实施障碍

- 需 **辅助功能** 授权
- UI 改版易导致选择器失效
- 需应用前台或至少存在可枚举窗口

---

## 5. 方案对比总结

| 数据源 | Thread 列表 | 实时状态 | Context 占用率 | Quota | 实施难度 |
|--------|------------|----------|----------------|-------|----------|
| **SQLite** | ✅ 元数据完整 | ❌ 无 | ❌ 无 | ❌ 无 | 低 |
| **JSONL** | ✅ 可追溯 | ⚠️ 延迟/推断 | ❌ 无直接字段 | ⚠️ 视是否含相关事件 | 中 |
| **UI 抓取** | ⚠️ 可能 | ❌ 通常不可靠 | ❌ 无 | ❌ 无 | 高 |
| **Claude Code** | ✅（会话模型） | ✅（会话文件） | ✅（如 statusline 桥接） | ❌（一般无） | 低（对该产品而言） |

---

## 6. 结论

### 核心发现

**Codex App 未提供与 Claude Code 会话 JSON 同级、可当作实时状态机读取的公开接口。**  
磁盘上可读的是：**线程元数据（SQLite）** 与 **历史事件流（JSONL）**，二者都不等价于「当前 UI 瞬时状态」。

### 可选方案

**方案 A: SQLite + 启发式**（可落地）

- 展示最近 `updated_at` 的 Thread
- 明确文案为「最近活动」而非「正在运行」

**方案 B: 混合**

- SQLite：列表与元数据
- JSONL：历史分析、若存在则解析配额相关行
- 辅助功能：尝试当前窗口/选中 thread（易碎）

**方案 C: 降低实时预期**

- 产品叙事改为「最近活动 / 历史概况」，不与 Claude Code 的 session 精度对标

### 建议

1. **短期**: SQLite 列表 + `updated_at` 排序 + 用户可选手动「关注」的 thread（弥补库中无焦点信息）。
2. **中期**: 小规模试验 AX，仅作补充，不写死为唯一数据源。
3. **长期**: 向 OpenAI / Codex 产品反馈 **机器可读的实时状态或会话快照 API**（类似 Claude Code 的 session 文件能力）。

---

**文档创建时间**: 2026-04-11  
**修订记录**: 勘误「Codex Context」误引 Claude Code `StatusLine.tsx`；补充 `threads` 全量列说明与 `tokens_used` 源码含义；JSONL `type` 改为版本敏感表述；Claude 路径加注实测说明。
