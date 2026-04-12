import SwiftUI

import AIIslandCore

struct ExpandedIslandCardView: View {
    let codex: AgentState
    let claude: AgentState
    let codexDiagnostics: AgentMonitorDiagnostics
    let claudeDiagnostics: AgentMonitorDiagnostics

    @AppStorage(IslandPalette.diagnosticsUserDefaultsKey) private var diagnosticsEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            AgentSectionView(presentation: AgentSectionPresentation(state: codex))
            Divider()
                .overlay(Color.white.opacity(0.08))
            AgentSectionView(presentation: AgentSectionPresentation(state: claude))

            if diagnosticsEnabled {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.top, 6)

                DiagnosticsPanel(codex: codexDiagnostics, claude: claudeDiagnostics)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(width: IslandPalette.expandedCardWidth)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.116, green: 0.116, blue: 0.124),
                            Color(red: 0.084, green: 0.084, blue: 0.092),
                            Color(red: 0.058, green: 0.058, blue: 0.064)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
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
}

private struct DiagnosticsPanel: View {
    let codex: AgentMonitorDiagnostics
    let claude: AgentMonitorDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header(for: codex)
            rows(for: codex)
            header(for: claude)
            rows(for: claude)
            Text("Toggle: Cmd+Shift+D")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))
        }
        .padding(.top, 2)
    }

    private func header(for diagnostics: AgentMonitorDiagnostics) -> some View {
        HStack(spacing: 8) {
            Text(diagnostics.kind == .codex ? "Codex Debug" : "Claude Debug")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.76))

            Spacer(minLength: 0)

            Text(diagnostics.triggerMode)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.52))
        }
    }

    private func rows(for diagnostics: AgentMonitorDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if diagnostics.threads.isEmpty {
                Text("no threads")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
            } else {
                ForEach(diagnostics.threads.prefix(2)) { thread in
                    HStack(spacing: 6) {
                        Text(shortID(thread.id))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.58))

                        Text(thread.stage.rawValue)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.66))

                        Text(relativeCopy(for: thread.lastSignalAt))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.58))

                        Spacer(minLength: 0)

                        Text(thread.sourceHits.joined(separator: "+"))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.44))
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
