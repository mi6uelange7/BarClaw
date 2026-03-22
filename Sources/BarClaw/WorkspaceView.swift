import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject var service: OpenClawService
    @State private var isEditing = false
    @State private var editBuffer = ""
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            // File tabs
            if !service.workspaceFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(service.workspaceFiles, id: \.self) { file in
                            fileTab(file)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .background(Color(NSColor.controlBackgroundColor))
                Divider().opacity(0.5)
            }

            // Toolbar
            HStack(spacing: 8) {
                Text(service.selectedFile)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if isEditing {
                    Button {
                        isEditing = false
                        editBuffer = service.selectedFileContent
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        service.saveFile(service.selectedFile, content: editBuffer)
                        isEditing = false
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                    } label: {
                        Text(saved ? "Saved ✓" : "Save")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(saved ? .green : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(saved ? Color.green : Color.accentColor))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        editBuffer = service.selectedFileContent
                        isEditing = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(service.selectedFile.isEmpty)

                    Button {
                        Task { await service.loadFile(service.selectedFile) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(NSColor.windowBackgroundColor))

            Divider().opacity(0.4)

            // Content
            if service.isLoadingFile {
                LoadingOverlay()
            } else if service.selectedFile.isEmpty {
                EmptyState(icon: "🧠", title: "Select a file above")
            } else if isEditing {
                TextEditor(text: $editBuffer)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.textBackgroundColor))
                    .padding(10)
            } else {
                ScrollView {
                    Text(service.selectedFileContent)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(2)
                        .padding(12)
                }
            }
        }
        .task { await service.loadWorkspaceFiles() }
    }

    private func fileTab(_ file: String) -> some View {
        let short = file.components(separatedBy: "/").last?.replacingOccurrences(of: ".md", with: "") ?? file
        let isSelected = service.selectedFile == file
        let isToday = file.contains(todayStr())

        return Button {
            isEditing = false
            Task { await service.loadFile(file) }
        } label: {
            HStack(spacing: 3) {
                if isToday { Text("★").font(.system(size: 8)).foregroundColor(.yellow) }
                Text(short)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func todayStr() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
