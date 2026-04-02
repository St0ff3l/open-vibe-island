import SwiftUI
import VibeIslandCore

struct IslandPanelView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("LIVE SESSIONS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.surfacedSessions.count) shown · \(model.state.attentionCount) attention")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if model.surfacedSessions.isEmpty {
                Text("Waiting for Codex sessions.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.surfacedSessions) { session in
                        IslandSessionRow(
                            session: session,
                            isSelected: session.id == model.focusedSession?.id,
                            onSelect: { model.select(sessionID: session.id) },
                            onJump: { model.jumpToSession(session) },
                            onApprove: { approved in
                                model.approvePermission(for: session.id, approved: approved)
                            },
                            onAnswer: { answer in
                                model.answerQuestion(for: session.id, answer: answer)
                            }
                        )
                    }
                }

                if model.hiddenSessionCount > 0 {
                    Text("+\(model.hiddenSessionCount) recent session(s) are hidden from the island. Open Control Center to inspect them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(
            width: OverlayDisplayResolver.defaultPanelSize.width,
            height: OverlayDisplayResolver.defaultPanelSize.height,
            alignment: .topLeading
        )
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.92),
                        Color(red: 0.11, green: 0.13, blue: 0.18).opacity(0.96),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct IslandSessionRow: View {
    let session: AgentSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onJump: () -> Void
    let onApprove: (Bool) -> Void
    let onAnswer: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(session.spotlightPrimaryText)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 8) {
                            badge(session.tool.displayName, tint: .white.opacity(0.12))
                            if let terminalBadge = session.spotlightTerminalBadge {
                                badge(terminalBadge, tint: .white.opacity(0.10))
                            }
                            badge(session.spotlightStatusLabel, tint: statusColor.opacity(0.22))
                        }

                        Text(session.updatedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isSelected {
                selectedActionRow
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isSelected ? .white.opacity(0.16) : .white.opacity(0.06))
        )
    }

    @ViewBuilder
    private var selectedActionRow: some View {
        if let request = session.permissionRequest {
            HStack(spacing: 10) {
                Text(request.summary)
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.92))
                    .lineLimit(2)
                Spacer(minLength: 12)
                Button(request.secondaryActionTitle) {
                    onApprove(false)
                }
                .buttonStyle(.bordered)
                Button(request.primaryActionTitle) {
                    onApprove(true)
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let prompt = session.questionPrompt {
            HStack(spacing: 10) {
                Text(prompt.title)
                    .font(.caption)
                    .foregroundStyle(.yellow.opacity(0.92))
                    .lineLimit(2)
                Spacer(minLength: 12)
                ForEach(prompt.options.prefix(2), id: \.self) { option in
                    Button(option) {
                        onAnswer(option)
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else {
            HStack {
                Text(session.phase == .completed
                    ? "Idle in terminal. Jump back when needed."
                    : "Live in terminal. Keep flow here and jump back when needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button("Jump") {
                    onJump()
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.jumpTarget == nil)
            }
        }
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint, in: Capsule())
    }

    private var statusColor: Color {
        switch session.phase {
        case .running:
            return .mint
        case .waitingForApproval:
            return .orange
        case .waitingForAnswer:
            return .yellow
        case .completed:
            return session.jumpTarget != nil ? .white : .blue
        }
    }
}

struct MenuBarContentView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vibe Island OSS")
                .font(.headline)
            Text("\(model.state.runningCount) running · \(model.state.attentionCount) attention")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button("Open Control Center") {
                model.showControlCenter()
            }

            Text(model.acceptanceStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.acceptanceStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button(model.isOverlayVisible ? "Hide Island Overlay" : "Show Island Overlay") {
                model.toggleOverlay()
            }

            Divider()

            Text(model.codexHookStatusTitle)
                .font(.subheadline.weight(.semibold))
            Text(model.codexHookStatusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Refresh Codex Hook Status") {
                model.refreshCodexHookStatus()
            }

            if model.codexHooksInstalled {
                Button("Uninstall Codex Hooks") {
                    model.uninstallCodexHooks()
                }
            } else {
                Button("Install Codex Hooks") {
                    model.installCodexHooks()
                }
                .disabled(model.hooksBinaryURL == nil)
            }

            if let session = model.focusedSession {
                Divider()
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                Text(session.spotlightPrimaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let currentTool = session.spotlightCurrentToolLabel {
                    Text("Live tool: \(currentTool)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let trackingLabel = session.spotlightTrackingLabel {
                    Text("Tracking: \(trackingLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
