import SwiftUI

struct LogsView: View {
    @EnvironmentObject var service: OpenClawService
    @State private var autoScroll = true
    @State private var filter = ""

    private var filteredLogs: [LogLine] {
        guard !filter.isEmpty else { return service.logs }
        return service.logs.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("Filter logs…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.system(size: 10))
                Button {
                    Task { await service.loadLogs() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Refresh logs")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Log pane
            if service.isLoadingLogs && service.logs.isEmpty {
                LoadingOverlay()
            } else if service.logs.isEmpty {
                EmptyState(icon: "📜", title: "No logs", subtitle: "Run the gateway to see logs here")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredLogs) { line in
                                LogRow(line: line)
                                    .id(line.id)
                            }
                        }
                        .padding(8)
                    }
                    .background(Color.black)
                    .onChange(of: service.logs.count) { _ in
                        if autoScroll, let last = filteredLogs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .task { await service.loadLogs() }
    }
}

struct LogRow: View {
    let line: LogLine

    private var textColor: Color {
        switch line.level {
        case .error: return Color(red: 1.0, green: 0.42, blue: 0.44)
        case .warn:  return Color(red: 1.0, green: 0.84, blue: 0.04)
        case .info:  return Color(red: 0.2,  green: 0.85, blue: 0.45)
        case .debug: return Color(red: 0.4,  green: 0.82, blue: 1.0)
        case .plain: return Color(white: 0.78)
        }
    }

    var body: some View {
        Text(line.text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(textColor)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
    }
}
