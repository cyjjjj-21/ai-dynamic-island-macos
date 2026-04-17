import SwiftUI

import AIIslandCore

struct ExpandedIslandCardView: View {
    let codex: AgentState
    let claude: AgentState
    let codexDiagnostics: AgentMonitorDiagnostics
    let claudeDiagnostics: AgentMonitorDiagnostics

    @AppStorage(IslandPalette.diagnosticsUserDefaultsKey) private var diagnosticsEnabled = false

    var body: some View {
        VStack(spacing: 8) {
            AgentSectionView(presentation: AgentSectionPresentation(state: codex))
                .background(sectionSurface)

            AgentSectionView(presentation: AgentSectionPresentation(state: claude))
                .background(sectionSurface)

            if diagnosticsEnabled {
                DiagnosticsPanel(codex: codexDiagnostics, claude: claudeDiagnostics)
                    .background(sectionSurface)
            }
        }
        .padding(8)
        .frame(width: IslandPalette.expandedCardWidth)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(IslandPalette.cardFill)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.075),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(1)
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(IslandPalette.cardStroke, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(IslandPalette.cardInnerStroke, lineWidth: 1)
                .padding(1)
        )
        .shadow(
            color: IslandPalette.shellEdgeHalo.opacity(0.95),
            radius: IslandPalette.shellEdgeHaloExpandedRadius,
            x: 0,
            y: 0
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex and Claude Code expanded status")
    }

    private var sectionSurface: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(IslandPalette.sectionFill)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(IslandPalette.sectionStroke, lineWidth: 1)
            )
    }
}

private struct DiagnosticsPanel: View {
    let codex: AgentMonitorDiagnostics
    let claude: AgentMonitorDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(for: codex)
            rows(for: codex)
                .padding(.bottom, 2)
            header(for: claude)
            rows(for: claude)

            Text("Toggle: Cmd+Shift+D")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(IslandPalette.tertiaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func header(for diagnostics: AgentMonitorDiagnostics) -> some View {
        HStack(spacing: 8) {
            Text(diagnostics.kind == .codex ? "Codex Debug" : "Claude Debug")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(IslandPalette.primaryText.opacity(0.8))

            Spacer(minLength: 0)

            Text(diagnostics.triggerMode)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(IslandPalette.tertiaryText)
        }
    }

    private func rows(for diagnostics: AgentMonitorDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if diagnostics.threads.isEmpty {
                Text("no threads")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(IslandPalette.tertiaryText)
            } else {
                ForEach(diagnostics.threads.prefix(2)) { thread in
                    HStack(spacing: 6) {
                        Text(shortID(thread.id))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(IslandPalette.secondaryText)

                        Text(thread.stage.rawValue)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(IslandPalette.primaryText.opacity(0.76))

                        Text(relativeCopy(for: thread.lastSignalAt))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(IslandPalette.secondaryText)

                        Spacer(minLength: 0)

                        Text(thread.sourceHits.joined(separator: "+"))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(IslandPalette.tertiaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func shortID(_ value: String) -> String {
        if value.count <= 8 {
            return value
        }
        return String(value.prefix(8))
    }

    private func relativeCopy(for date: Date?) -> String {
        guard let date else {
            return "--"
        }
        let delta = Int(max(0, Date().timeIntervalSince(date)))
        if delta < 60 {
            return "\(delta)s"
        }
        return "\(delta / 60)m"
    }
}
