import SwiftUI

struct StatusView: View {
    @EnvironmentObject var service: OpenClawService
    @State private var heartbeatSent = false

    var body: some View {
        VStack(spacing: 11) {
            heroCard
            statsRow
            modelCard
            channelActionsCard
            Spacer(minLength: 0)
        }
        .padding(13)
        .task {
            await service.loadStatus()  // debounced — won't spam on every tab switch
            service.loadCurrentModel()
        }
    }

    // MARK: - Hero card (gateway info + channel inline)

    private var heroCard: some View {
        CPCard {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(service.isOnline ? Color.green.opacity(0.15) : Color.red.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: service.isOnline ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(service.isOnline ? .green : .red)
                    }

                    // Text info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.isOnline ? "Gateway Running" : "Gateway Offline")
                            .font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 6) {
                            if let ver = service.status?.runtimeVersion {
                                Text("OpenClaw \(ver)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            if let hb = service.status?.heartbeat?.agents?.first?.every {
                                Text("·")
                                    .foregroundColor(Color(NSColor.quaternaryLabelColor))
                                    .font(.system(size: 11))
                                Text("Heartbeat \(hb)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    // Refresh
                    Button {
                        guard !service.isLoadingStatus else { return }
                        Task { await service.loadStatus(force: true) }
                    } label: {
                        if service.isLoadingStatus {
                            ProgressView().scaleEffect(0.55)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isLoadingStatus)
                    .help("Refresh")
                }

                // Inline channel status
                if let channels = service.status?.channelSummary {
                    Divider()
                        .padding(.vertical, 8)

                    HStack(spacing: 0) {
                        ForEach(channels.filter { !$0.hasPrefix("  ") }, id: \.self) { line in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(service.isOnline ? Color.green : Color(NSColor.tertiaryLabelColor))
                                    .frame(width: 5, height: 5)
                                Text(line)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Stats (4-column single row, no scroll)

    private var statsRow: some View {
        let loading = service.isLoadingStatus && service.sessions.isEmpty
        let main = service.sessions.first(where: { $0.key.hasSuffix(":main") }) ?? service.sessions.first
        let pct = main?.percentUsed ?? 0
        let tokens = main?.totalTokens ?? 0

        return HStack(spacing: 8) {
            compactStat(
                icon: "list.bullet.rectangle.fill",
                value: loading ? "—" : "\(service.sessionCount)",
                label: "Sessions",
                color: .blue,
                loading: loading
            )
            compactStat(
                icon: "brain.head.profile",
                value: loading ? "—" : "\(pct)%",
                label: "Context",
                color: pct > 80 ? .red : pct > 50 ? .orange : .green,
                loading: loading
            )
            compactStat(
                icon: "text.bubble.fill",
                value: loading ? "—" : fmtNum(tokens),
                label: "Tokens",
                color: .purple,
                loading: loading
            )
            compactStat(
                icon: "clock.arrow.2.circlepath",
                value: loading ? "—" : (service.status?.heartbeat?.agents?.first?.every ?? "—"),
                label: "Heartbeat",
                color: .teal,
                loading: loading
            )
        }
    }

    private func compactStat(icon: String, value: String, label: String, color: Color, loading: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(loading ? Color(NSColor.tertiaryLabelColor) : color)
            if loading {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(NSColor.tertiaryLabelColor).opacity(0.3))
                    .frame(width: 32, height: 18)
                    .shimmering()
            } else {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Model switcher

    private let modelOptions: [(label: String, value: String)] = [
        ("Claude 3.5 Haiku",  "openrouter/anthropic/claude-3.5-haiku"),
        ("Claude 3.5 Sonnet", "openrouter/anthropic/claude-3.5-sonnet"),
        ("Claude 3 Haiku",    "openrouter/anthropic/claude-3-haiku"),
        ("Claude 3 Opus",     "openrouter/anthropic/claude-3-opus"),
    ]

    private var modelCard: some View {
        CPCard {
            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(service.isModelLoaded ? .orange : Color(NSColor.tertiaryLabelColor))

                Text("Model")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if service.isModelLoaded {
                    Picker("", selection: Binding(
                        get: { service.currentModel },
                        set: { service.switchModel($0) }
                    )) {
                        ForEach(modelOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                        if !modelOptions.map(\.value).contains(service.currentModel) {
                            Text(service.currentModel).tag(service.currentModel)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .font(.system(size: 12))
                    .frame(maxWidth: 170)
                } else {
                    // Locked skeleton — prevents accidental model change while loading
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.65)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(NSColor.tertiaryLabelColor).opacity(0.3))
                            .frame(width: 100, height: 12)
                            .shimmering()
                    }
                }
            }
        }
    }

    // MARK: - Channel + actions combined card

    private var channelActionsCard: some View {
        CPCard {
            VStack(spacing: 8) {
                // Gateway result flash banner
                if let result = service.gatewayResult {
                    let isFailure = result == "failed"
                    HStack(spacing: 6) {
                        Image(systemName: isFailure ? "xmark.circle.fill" : "checkmark.circle.fill")
                        Text("Gateway \(result)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(isFailure ? .red : .green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isFailure ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                // Gateway power controls
                HStack(spacing: 8) {
                    gatewayButton(
                        label: "Start", icon: "play.fill", color: .green,
                        op: .starting,
                        disabled: service.isOnline || service.gatewayOp != nil
                    ) { Task { await service.startGateway() } }

                    gatewayButton(
                        label: "Restart", icon: "arrow.counterclockwise", color: .orange,
                        op: .restarting,
                        disabled: service.gatewayOp != nil
                    ) { Task { await service.restartGateway() } }

                    gatewayButton(
                        label: "Stop", icon: "stop.fill", color: .red,
                        op: .stopping,
                        disabled: !service.isOnline || service.gatewayOp != nil
                    ) { Task { await service.stopGateway() } }
                }
                .animation(.easeInOut(duration: 0.2), value: service.gatewayOp != nil)

                Divider().opacity(0.4)

                HStack(spacing: 8) {
                    // Heartbeat send
                    Button {
                        guard !heartbeatSent else { return }
                        Task {
                            await service.sendHeartbeat()
                            heartbeatSent = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { heartbeatSent = false }
                        }
                    } label: {
                        Label(heartbeatSent ? "Sent!" : "Heartbeat",
                              systemImage: heartbeatSent ? "checkmark" : "heart.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(heartbeatSent ? .green : .pink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(heartbeatSent ? Color.green.opacity(0.1) : Color.pink.opacity(0.1))
                            )
                    }
                    .buttonStyle(CPPressStyle())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: heartbeatSent)
                    .disabled(heartbeatSent)

                    // Refresh
                    Button {
                        guard !service.isLoadingStatus else { return }
                        Task { await service.loadStatus(force: true) }
                    } label: {
                        HStack(spacing: 5) {
                            if service.isLoadingStatus {
                                ProgressView().scaleEffect(0.6)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Text("Refresh")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                    .buttonStyle(CPPressStyle())
                    .disabled(service.isLoadingStatus)

                    // Heartbeat toggle
                    Button {
                        Task { await service.toggleHeartbeat() }
                    } label: {
                        Image(systemName: service.heartbeatEnabled ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(service.heartbeatEnabled ? .orange : .green)
                            .frame(width: 36, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(service.heartbeatEnabled ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                            )
                    }
                    .buttonStyle(CPPressStyle())
                    .help(service.heartbeatEnabled ? "Pause heartbeat" : "Resume heartbeat")
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: service.heartbeatEnabled)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: service.gatewayResult != nil)
    }

    private func gatewayButton(label: String, icon: String, color: Color,
                                op: OpenClawService.GatewayOp, disabled: Bool,
                                action: @escaping () -> Void) -> some View {
        let isRunning = service.gatewayOp == op
        return Button(action: action) {
            VStack(spacing: 3) {
                if isRunning {
                    ProgressView().scaleEffect(0.6).frame(width: 13, height: 13)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(isRunning ? "…" : label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(disabled && !isRunning ? Color(NSColor.tertiaryLabelColor) : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(disabled && !isRunning
                          ? Color(NSColor.tertiaryLabelColor).opacity(0.05)
                          : isRunning ? color.opacity(0.18) : color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isRunning ? color.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(CPPressStyle())
        .disabled(disabled)
        .animation(.easeInOut(duration: 0.15), value: isRunning)
    }
}
