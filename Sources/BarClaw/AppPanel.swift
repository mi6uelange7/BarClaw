import SwiftUI

enum Tab: String, CaseIterable {
    case status    = "Status"
    case chat      = "Chat"
    case sessions  = "Sessions"
    case logs      = "Logs"
    case workspace = "Workspace"
    case cron      = "Cron"
    case skills    = "Skills"

    var icon: String {
        switch self {
        case .status:    return "chart.bar.fill"
        case .chat:      return "bubble.left.fill"
        case .sessions:  return "list.bullet.rectangle.fill"
        case .logs:      return "terminal.fill"
        case .workspace: return "doc.text.fill"
        case .cron:      return "clock.fill"
        case .skills:    return "wrench.adjustable.fill"
        }
    }
}

struct AppPanel: View {
    @EnvironmentObject var service: OpenClawService
    @State private var tab: Tab = .status
    @State private var hoveredTab: Tab? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            tabBar
            Divider().opacity(0.5)
            content
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Text("🦞")
                .font(.system(size: 20))
            Text("BarClaw")
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundColor(.primary)
            Spacer()
            statusPill
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            PulsingDot(isOnline: service.isOnline)
            Text(service.isOnline ? "Online" : "Offline")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(service.isOnline ? .green : .red)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(service.isOnline ? Color.green.opacity(0.1) : Color.red.opacity(0.08))
                .overlay(
                    Capsule()
                        .stroke(service.isOnline ? Color.green.opacity(0.25) : Color.red.opacity(0.2), lineWidth: 0.5)
                )
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: service.isOnline)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(Tab.allCases, id: \.self) { t in
                tabButton(t)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func tabButton(_ t: Tab) -> some View {
        let isActive = tab == t
        let isHovered = hoveredTab == t

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { tab = t }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: t.icon)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                Text(t.rawValue)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(0.15)
                            : isHovered
                                ? Color(NSColor.labelColor).opacity(0.05)
                                : Color.clear
                    )
            )
            .foregroundColor(isActive ? .accentColor : Color(NSColor.secondaryLabelColor))
        }
        .buttonStyle(CPPressStyle(scale: 0.96))
        .onHover { hoveredTab = $0 ? t : nil }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .status:    StatusView()
        case .chat:      ChatView()
        case .sessions:  SessionsView()
        case .logs:      LogsView()
        case .workspace: WorkspaceView()
        case .cron:      CronView()
        case .skills:    SkillsView()
        }
    }
}

// MARK: - Shimmer modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.25),
                            Color.white.opacity(0),
                        ]),
                        startPoint: .init(x: phase - 0.3, y: 0.5),
                        endPoint:   .init(x: phase + 0.3, y: 0.5)
                    )
                    .blendMode(.plusLighter)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Pulsing status dot

struct PulsingDot: View {
    let isOnline: Bool
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if isOnline {
                Circle()
                    .fill(Color.green.opacity(0.35))
                    .frame(width: 13, height: 13)
                    .scaleEffect(pulsing ? 1.0 : 0.4)
                    .opacity(pulsing ? 0 : 0.6)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulsing)
            }
            Circle()
                .fill(isOnline ? Color.green : Color.red)
                .frame(width: 7, height: 7)
        }
        .onAppear { pulsing = true }
    }
}

// MARK: - Press button style

/// Gives buttons a satisfying Apple-like press-in scale effect.
struct CPPressStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Shared components

struct CPCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 0.5)
            )
    }
}

struct CPBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct LoadingOverlay: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.9)
            Text("Loading…")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(spacing: 7) {
            Text(icon)
                .font(.system(size: 34))
                .opacity(0.45)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
