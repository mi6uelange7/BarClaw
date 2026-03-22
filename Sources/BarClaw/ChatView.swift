import SwiftUI

struct ChatView: View {
    @EnvironmentObject var service: OpenClawService
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if service.chatMessages.isEmpty {
                            emptyState
                        }
                        ForEach(service.chatMessages) { msg in
                            MessageBubble(msg: msg)
                                .id(msg.id)
                        }
                        if service.isSending {
                            typingIndicator
                        }
                    }
                    .padding(12)
                }
                .onChange(of: service.chatMessages.count) { _ in
                    if let last = service.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: service.isSending) { _ in
                    if let last = service.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Quick commands
            quickCommands

            // Input row
            inputRow
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🦞")
                .font(.system(size: 32))
                .opacity(0.4)
            Text("Talk to your agent")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("Messages go to the main session")
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    TypingDot(delay: Double(i) * 0.2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            Spacer()
        }
    }

    private let quickCmds = [
        ("💓", "Heartbeat"),
        ("📋", "Summarize today"),
        ("📊", "Give me a status update"),
        ("🧹", "What's on my plate?"),
        ("🧠", "What do you remember about today?"),
    ]

    private var quickCommands: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(quickCmds, id: \.1) { emoji, label in
                    Button {
                        guard !service.isSending else { return }
                        Task { await service.sendChat("\(emoji) \(label)") }
                    } label: {
                        Text("\(emoji) \(label)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isSending)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message the agent…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                )
                .onSubmit {
                    guard !service.isSending else { return }
                    send()
                }

            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(input.trimmingCharacters(in: .whitespaces).isEmpty || service.isSending
                        ? Color(NSColor.tertiaryLabelColor)
                        : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || service.isSending)
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !service.isSending else { return }
        input = ""
        Task { await service.sendChat(text) }
    }
}

struct MessageBubble: View {
    let msg: OpenClawService.ChatMessage

    var isUser: Bool { msg.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                Text(msg.text)
                    .font(.system(size: 13))
                    .foregroundColor(isUser ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isUser
                                ? Color.accentColor
                                : Color(NSColor.controlBackgroundColor)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isUser ? Color.clear : Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
                    )
                    .textSelection(.enabled)

                Text(msg.time, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

struct TypingDot: View {
    let delay: Double
    @State private var up = false

    var body: some View {
        Circle()
            .fill(Color(NSColor.tertiaryLabelColor))
            .frame(width: 6, height: 6)
            .offset(y: up ? -4 : 0)
            .animation(
                .easeInOut(duration: 0.5).repeatForever().delay(delay),
                value: up
            )
            .onAppear { up = true }
    }
}
