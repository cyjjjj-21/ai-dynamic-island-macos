import Foundation

import AIIslandCore

struct ResolvedThreadTitle: Equatable, Sendable {
    let title: String
    let detail: String?
    let workspaceLabel: String?
    let source: AgentThreadTitleSource
}

private struct PromptTitleCandidate: Equatable {
    let title: String
    let priority: Int
    let index: Int
}

private enum PromptTitleSource {
    case codex
    case claude
}

enum ThreadTitleResolver {
    private static let placeholderValues: Set<String> = [
        "undefined",
        "null",
        "nil",
        "none",
        "nan"
    ]

    static func resolveCodexTitle(
        prompts: [String],
        sessionIndexTitle: String?,
        workspacePath: String?,
        latestAssistantMessage: String?
    ) -> ResolvedThreadTitle {
        let workspaceLabel = resolveWorkspaceLabel(from: workspacePath)
        let cleanedPrompts = prompts.enumerated().compactMap { index, prompt in
            compactPromptCandidate(from: prompt, index: index, source: .codex)
        }
        let detail = compactAssistantDetail(from: latestAssistantMessage)

        if let firstPrompt = cleanedPrompts.max(by: promptCandidatePrecedes(_:_:)) {
            return ResolvedThreadTitle(
                title: firstPrompt.title,
                detail: detail,
                workspaceLabel: workspaceLabel,
                source: .codexPromptSummary
            )
        }

        if let sessionIndexTitle = sessionIndexTitle {
            let cleanedSessionIndexTitle = sanitizeCodexSessionIndexTitle(sessionIndexTitle)
            if isViableTitleCandidate(cleanedSessionIndexTitle) {
                return ResolvedThreadTitle(
                    title: cleanedSessionIndexTitle,
                    detail: detail,
                    workspaceLabel: workspaceLabel,
                    source: .codexSessionIndexHint
                )
            }
        }

        return ResolvedThreadTitle(
            title: workspaceLabel ?? "Codex 任务",
            detail: compactAssistantDetail(from: latestAssistantMessage),
            workspaceLabel: workspaceLabel,
            source: workspaceLabel == nil ? .unknown : .workspaceFallback
        )
    }

    static func resolveClaudeTitle(
        taskSummary: String?,
        promptCandidates: [String],
        lastPrompt: String?,
        waitingFor: String?,
        workspacePath: String?
    ) -> ResolvedThreadTitle {
        let workspaceLabel = resolveWorkspaceLabel(from: workspacePath)

        if let taskSummary {
            let cleanedTaskSummary = sanitizeTitle(taskSummary)
            if isViableTitleCandidate(cleanedTaskSummary) {
                return ResolvedThreadTitle(
                    title: cleanedTaskSummary,
                    detail: compactWaitingDetail(from: waitingFor),
                    workspaceLabel: workspaceLabel,
                    source: .claudeTaskSummary
                )
            }
        }

        let cleanedPrompts = (promptCandidates + [lastPrompt].compactMap { $0 })
            .enumerated()
            .compactMap { index, prompt in
                compactPromptCandidate(from: prompt, index: index, source: .claude)
            }
        if let prompt = cleanedPrompts.max(by: promptCandidatePrecedes(_:_:)) {
            return ResolvedThreadTitle(
                title: prompt.title,
                detail: compactWaitingDetail(from: waitingFor),
                workspaceLabel: workspaceLabel,
                source: .claudePromptSummary
            )
        }

        return ResolvedThreadTitle(
            title: workspaceLabel ?? "Claude Code 任务",
            detail: compactWaitingDetail(from: waitingFor),
            workspaceLabel: workspaceLabel,
            source: workspaceLabel == nil ? .unknown : .workspaceFallback
        )
    }

    static func resolveWorkspaceLabel(from path: String?) -> String? {
        guard let path else { return nil }

        let components = path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !components.isEmpty else { return nil }

        if let worktreeIndex = components.lastIndex(where: { $0 == ".worktrees" || $0 == "worktrees" }),
           worktreeIndex > 0
        {
            let candidate = components[worktreeIndex - 1]
            if isMeaningfulWorkspaceComponent(candidate) {
                return candidate
            }
        }

        var trimmedComponents = components
        if let first = trimmedComponents.first?.lowercased(), first == "users" || first == "home" {
            guard trimmedComponents.count > 2 else { return nil }
            trimmedComponents = Array(trimmedComponents.dropFirst(2))
        }

        while trimmedComponents.count > 1,
              let first = trimmedComponents.first,
              isContainerWorkspaceComponent(first)
        {
            trimmedComponents.removeFirst()
        }

        for component in trimmedComponents.reversed() {
            if !isMeaningfulWorkspaceComponent(component) {
                continue
            }
            return component
        }

        return nil
    }

    private static func compactPromptCandidate(
        from raw: String,
        index: Int,
        source: PromptTitleSource
    ) -> PromptTitleCandidate? {
        let text = stripLeadingPromptNoise(from: sanitizeTitle(raw))
        guard isViableTitleCandidate(text), !isWeakFollowUpPrompt(text) else { return nil }

        guard !text.isEmpty else {
            return nil
        }

        if text.contains("自动化未读消息来源") {
            return PromptTitleCandidate(title: "自动化未读消息排查", priority: 3, index: index)
        }
        if source == .codex, text.contains("配额") && text.contains("展示") {
            return PromptTitleCandidate(title: "Codex 配额展示优化", priority: 3, index: index)
        }
        if text.contains("动态岛") || text.lowercased().contains("dynamic island") {
            return PromptTitleCandidate(title: "AI Dynamic Island 优化", priority: 3, index: index)
        }
        if looksLikeExecutionMetaPrompt(text) {
            return nil
        }

        let priority = looksLikeTopicPrompt(text) ? 2 : 1
        return PromptTitleCandidate(title: compactLength(text, limit: 30), priority: priority, index: index)
    }

    private static func compactWaitingDetail(from raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if raw.lowercased().contains("approve bash") {
            return "等待批准 Bash"
        }
        return compactLength(sanitizeTitle(raw), limit: 18)
    }

    private static func compactAssistantDetail(from raw: String?) -> String? {
        guard let raw, isViableTitleCandidate(raw) else { return nil }
        let lowered = raw.lowercased()
        if lowered.contains("need your approval") || lowered.contains("please confirm") {
            return "等待你的确认"
        }
        return compactLength(sanitizeTitle(raw), limit: 18)
    }

    private static func sanitizeTitle(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "<br>", with: " ")
            .replacingOccurrences(of: "<br/>", with: " ")
            .replacingOccurrences(of: "<br />", with: " ")
            .replacingOccurrences(of: #"<\s*/?\s*[A-Za-z][^>]{0,80}>"#, with: " ", options: .regularExpression)
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLeadingPromptNoise(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let leadingNoise = [
            "继续", "接着", "顺便", "帮我", "请你", "看一下", "展开说说",
            "please", "re-review", "review", "okay", "ok", "好的", "好", "嗯", "行", "再"
        ]

        for noise in leadingNoise {
            if text.lowercased().hasPrefix(noise.lowercased()) {
                text = String(text.dropFirst(noise.count))
                    .trimmingCharacters(in: promptNoiseSeparators)
                break
            }
        }

        return text
    }

    private static func sanitizeCodexSessionIndexTitle(_ raw: String) -> String {
        let brPattern = #"<\s*br\s*/?\s*>"#
        if let range = raw.range(of: brPattern, options: [.regularExpression, .caseInsensitive]) {
            let prefix = sanitizeTitle(String(raw[..<range.lowerBound]))
            if isViableTitleCandidate(prefix) {
                return prefix
            }
        }
        return sanitizeTitle(raw)
    }

    private static var promptNoiseSeparators: CharacterSet {
        CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,、:：。.!！?？"))
    }

    private static func isWeakFollowUpPrompt(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: promptNoiseSeparators)
        let weakPrompts: Set<String> = [
            "go",
            "ok",
            "okay",
            "好的",
            "好",
            "嗯",
            "行",
            "可以",
            "收到",
            "继续",
            "接着",
            "review",
            "re-review",
            "展开说说",
            "说说",
            "开始",
            "开始吧"
        ]
        return weakPrompts.contains(normalized)
    }

    private static func isViableTitleCandidate(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !isPlaceholderValue(trimmed) else { return false }
        guard !looksLikeStructuredNotification(trimmed) else { return false }
        guard !trimmed.contains("\u{FFFD}") else { return false }
        guard !looksLikeAbsolutePath(trimmed) else { return false }
        let htmlLikePattern = #"<\s*/?\s*[A-Za-z][^>]{0,40}>"#
        if trimmed.range(of: htmlLikePattern, options: .regularExpression) != nil {
            return false
        }

        let symbolCount = trimmed.unicodeScalars.filter {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }.count
        if Double(symbolCount) / Double(max(trimmed.count, 1)) > 0.28 {
            return false
        }

        return true
    }

    private static func compactLength(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let boundary = text.index(text.startIndex, offsetBy: max(limit, 1))
        return String(text[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLikelyUsername(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered == "chenyuanjie"
            || lowered == "root"
            || lowered == "admin"
            || lowered == "user"
    }

    private static func isContainerWorkspaceComponent(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered == "developer"
            || lowered == "projects"
            || lowered == "project"
            || lowered == "workspace"
            || lowered == "workspaces"
            || lowered == "repos"
            || lowered == "repo"
            || lowered == "src"
            || lowered == "code"
    }

    private static func isMeaningfulWorkspaceComponent(_ value: String) -> Bool {
        if isPlaceholderValue(value) {
            return false
        }
        if value.hasPrefix(".") {
            return false
        }
        if isContainerWorkspaceComponent(value) {
            return false
        }
        if value == "Users" || value == "home" {
            return false
        }
        if isLikelyUsername(value) {
            return false
        }
        return true
    }

    private static func isPlaceholderValue(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return placeholderValues.contains(normalized)
    }

    private static func looksLikeStructuredNotification(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered.contains("<subagent_notification") || lowered.contains("</subagent_notification>") {
            return true
        }

        if trimmed.hasPrefix("{"), lowered.contains("\"agent_path\""), lowered.contains("\"status\"") {
            return true
        }

        return lowered.contains("\"agent_path\"") && lowered.contains("::code-comment{")
    }

    private static func promptCandidatePrecedes(_ lhs: PromptTitleCandidate, _ rhs: PromptTitleCandidate) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.index < rhs.index
    }

    private static func looksLikeAbsolutePath(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("/Users/") || normalized.hasPrefix("/home/") || normalized.hasPrefix("~/") {
            return true
        }
        return false
    }

    private static func looksLikeExecutionMetaPrompt(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let metaNeedles = [
            "按这份 plan",
            "按这份计划",
            "开始 coding",
            "start coding",
            "begin coding",
            "开始开发",
            "开始实现",
            "开始执行",
            "照着这个 plan",
            "根据这个 plan"
        ]
        guard metaNeedles.contains(where: { lowered.contains($0.lowercased()) }) else {
            return false
        }

        let topicNeedles = [
            "dynamic island",
            "动态岛",
            "配额",
            "quota",
            "监控",
            "monitor",
            "线程",
            "thread",
            "标题",
            "命名",
            "展示",
            "fallback",
            "subagent",
            "claude",
            "codex",
            "ai-dynamic-island"
        ]
        return !topicNeedles.contains(where: { lowered.contains($0) })
    }

    private static func looksLikeTopicPrompt(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let topicNeedles = [
            "dynamic island",
            "ai-dynamic-island",
            "动态岛",
            "线程",
            "thread",
            "标题",
            "命名",
            "展示",
            "监控",
            "monitor",
            "配额",
            "quota",
            "codex",
            "claude",
            "subagent",
            "fallback",
            "诊断",
            "优化",
            "改进",
            "方案",
            "任务",
            "视觉",
            "交互"
        ]
        return topicNeedles.contains(where: { lowered.contains($0) })
    }
}
