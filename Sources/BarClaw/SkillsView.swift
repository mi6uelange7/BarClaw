import SwiftUI

struct SkillsView: View {
    @EnvironmentObject var service: OpenClawService
    @State private var showMissing = false

    private var ready: [OCSkill]   { service.skills.filter { $0.ready } }
    private var missing: [OCSkill] { service.skills.filter { !$0.ready } }
    private var shown: [OCSkill]   { showMissing ? missing : ready }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 8) {
                if !service.skillsSummary.isEmpty {
                    Text(service.skillsSummary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: $showMissing) {
                    Text("Ready (\(ready.count))").tag(false)
                    Text("Missing (\(missing.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if service.isLoadingSkills {
                LoadingOverlay()
            } else if shown.isEmpty {
                EmptyState(
                    icon: showMissing ? "📦" : "🔧",
                    title: showMissing ? "No missing skills" : "No skills ready",
                    subtitle: showMissing ? "All skills are installed!" : "Install skills via BarClaw"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(shown) { skill in
                            SkillRow(skill: skill)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .task { await service.loadSkills() }
    }
}

struct SkillRow: View {
    let skill: OCSkill

    var body: some View {
        HStack(spacing: 10) {
            Text(skill.icon)
                .font(.system(size: 22))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.system(size: 12, weight: .semibold))
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            CPBadge(
                text: skill.ready ? "Ready" : "Missing",
                color: skill.ready ? .green : Color(NSColor.tertiaryLabelColor)
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .opacity(skill.ready ? 1 : 0.55)
    }
}
