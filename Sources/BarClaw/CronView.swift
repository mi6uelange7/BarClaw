import SwiftUI

struct CronView: View {
    @EnvironmentObject var service: OpenClawService
    @State private var message = ""
    @State private var every = ""
    @State private var label = ""
    @State private var adding = false
    @State private var feedback = ""

    // Parse "No cron jobs." vs table output
    private var hasJobs: Bool {
        !service.cronRaw.isEmpty && !service.cronRaw.contains("No cron jobs")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Job list
            Group {
                if service.isLoadingCron {
                    LoadingOverlay()
                } else if !hasJobs {
                    EmptyState(icon: "⏰", title: "No scheduled jobs", subtitle: "Add one below")
                } else {
                    ScrollView {
                        CPCard {
                            Text(service.cronRaw)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Add form
            VStack(alignment: .leading, spacing: 10) {
                Text("NEW JOB")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                TextField("What should the agent do?", text: $message)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Schedule")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("30m, 2h, daily…", text: $every)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(7)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color(NSColor.controlBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Label (optional)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("My task", text: $label)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(7)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color(NSColor.controlBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
                    }
                }

                HStack {
                    Button {
                        guard !message.isEmpty, !every.isEmpty else {
                            feedback = "Message and schedule required"
                            return
                        }
                        adding = true
                        feedback = ""
                        Task {
                            await service.addCronJob(message: message, every: every, label: label)
                            message = ""; every = ""; label = ""
                            feedback = "✓ Job added"
                            adding = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if adding { ProgressView().scaleEffect(0.7).frame(width: 12, height: 12) }
                            Text(adding ? "Adding…" : "Add Job")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                    .disabled(adding)

                    if !feedback.isEmpty {
                        Text(feedback)
                            .font(.system(size: 11))
                            .foregroundColor(feedback.hasPrefix("✓") ? .green : .red)
                    }

                    Spacer()

                    Button {
                        Task { await service.loadCron() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .task { await service.loadCron() }
    }
}
