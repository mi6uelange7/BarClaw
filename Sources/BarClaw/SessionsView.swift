import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var service: OpenClawService
    @State private var confirmingClear = false
    @State private var clearing = false
    @State private var cleared = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar row
            HStack {
                Text("\(service.sessionCount) session\(service.sessionCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button { Task { await service.loadSessions() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .buttonStyle(CPPressStyle())
                .help("Refresh sessions")

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        confirmingClear = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: cleared ? "checkmark" : "trash")
                            .font(.system(size: 12, weight: .medium))
                        Text(cleared ? "Cleared" : "Clear")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(cleared ? .green : .red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(cleared ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    )
                }
                .buttonStyle(CPPressStyle())
                .disabled(clearing || service.sessions.isEmpty || confirmingClear)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cleared)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            // Inline confirmation banner — no system dialogs that steal focus
            if confirmingClear {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 13))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Delete all session history?")
                            .font(.system(size: 12, weight: .medium))
                        Text("Gateway will restart to reconnect Telegram.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Cancel") {
                        withAnimation { confirmingClear = false }
                    }
                    .buttonStyle(CPPressStyle())
                    .font(.system(size: 12))

                    Button {
                        withAnimation { confirmingClear = false }
                        Task {
                            clearing = true
                            await service.clearSessions()
                            clearing = false
                            cleared = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { cleared = false }
                            }
                        }
                    } label: {
                        Text(clearing ? "Clearing…" : "Delete")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.red))
                    }
                    .buttonStyle(CPPressStyle())
                    .disabled(clearing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.orange.opacity(0.08))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider().opacity(0.4)

            Group {
                if service.sessions.isEmpty && !service.isLoadingStatus {
                    EmptyState(icon: "🗂", title: "No sessions", subtitle: "Sessions appear here when the agent is active.")
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(service.sessions) { session in
                                SessionCard(session: session)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .overlay {
                if service.isLoadingStatus && service.sessions.isEmpty {
                    LoadingOverlay()
                }
            }
        }
        .task { await service.loadSessions() }
    }
}

struct SessionCard: View {
    let session: OCSession

    private var pct: Double { session.pct }
    private var barColor: Color {
        pct > 80 ? .red : pct > 50 ? .orange : .accentColor
    }

    var body: some View {
        CPCard {
            VStack(alignment: .leading, spacing: 8) {
                // Key + badge row
                HStack(alignment: .center, spacing: 6) {
                    Text(session.shortKey)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let kind = session.kind {
                        CPBadge(text: kind, color: kind == "direct" ? .blue : .secondary)
                    }
                }

                // Meta row
                HStack(spacing: 10) {
                    metaChip("clock", session.ageFormatted)
                    if let tokens = session.totalTokens {
                        metaChip("text.bubble", fmtNum(tokens) + " tokens")
                    }
                    if session.model != nil {
                        metaChip("cpu", session.modelShort)
                            .lineLimit(1)
                    }
                }

                // Context bar
                if pct > 0 {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Context")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(session.percentUsed ?? 0)%")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(barColor)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(NSColor.separatorColor).opacity(0.4))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(barColor)
                                    .frame(width: geo.size.width * (pct / 100))
                                    .animation(.easeInOut(duration: 0.4), value: pct)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                // Flags
                if let flags = session.flags, !flags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(flags.prefix(4), id: \.self) { flag in
                            CPBadge(text: flag, color: .secondary)
                        }
                    }
                }
            }
        }
    }

    private func metaChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10))
        }
        .foregroundColor(.secondary)
    }
}
