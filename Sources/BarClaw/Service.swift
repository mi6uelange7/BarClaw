import Foundation

// MARK: - Shell helper
func runClaw(_ args: String, timeout: TimeInterval = 15) async -> String {
    await withCheckedContinuation { cont in
        let proc = Process()
        // Use /bin/sh (not login zsh) — avoids loading .zshrc/.zprofile, saves 300-800ms
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "/usr/local/bin/openclaw \(args)"]
        // Inject common binary paths so openclaw can find node without a login shell
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        var resumed = false
        let lock = NSLock()

        func finish(_ s: String) {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            cont.resume(returning: s)
        }

        proc.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            finish(String(data: data, encoding: .utf8) ?? "")
        }

        // Timeout watchdog
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            proc.terminate()
            finish("")
        }

        do { try proc.run() }
        catch { finish("") }
    }
}

// MARK: - Models

struct OCSession: Identifiable, Codable {
    var id: String { key }
    let key: String
    let agentId: String
    let kind: String?
    let sessionId: String?
    let updatedAt: Double?
    let ageMs: Double?
    let age: Double?
    let totalTokens: Int?
    let contextTokens: Int?
    let percentUsed: Int?
    let remainingTokens: Int?
    let model: String?
    let flags: [String]?

    var ageFormatted: String {
        let ms = ageMs ?? age ?? 0
        let s = Int(ms / 1000)
        if s < 60 { return "\(s)s ago" }
        let m = s / 60; if m < 60 { return "\(m)m ago" }
        let h = m / 60; if h < 24 { return "\(h)h ago" }
        return "\(h / 24)d ago"
    }

    var shortKey: String {
        key
            .replacingOccurrences(of: "agent:main:", with: "")
            .replacingOccurrences(of: "agent:", with: "")
    }

    var pct: Double { Double(percentUsed ?? 0) }

    var modelShort: String {
        (model ?? "—")
            .replacingOccurrences(of: "anthropic/", with: "")
            .replacingOccurrences(of: "openai/", with: "")
    }
}

struct OCSessionsResponse: Codable {
    let count: Int?
    let sessions: [OCSession]
}

struct OCHeartbeatAgent: Codable {
    let agentId: String?
    let enabled: Bool?
    let every: String?
}

struct OCHeartbeat: Codable {
    let defaultAgentId: String?
    let agents: [OCHeartbeatAgent]?
}

struct OCStatus: Codable {
    let runtimeVersion: String?
    let heartbeat: OCHeartbeat?
    let channelSummary: [String]?
}

struct OCSkill: Identifiable {
    var id: String { name }
    let name: String
    let icon: String
    let description: String
    let ready: Bool
}

struct LogLine: Identifiable {
    let id = UUID()
    let text: String
    var level: Level {
        let l = text.lowercased()
        if l.contains("error") || l.contains("err") { return .error }
        if l.contains("warn") { return .warn }
        if l.contains("info") { return .info }
        if l.contains("debug") { return .debug }
        return .plain
    }
    enum Level { case error, warn, info, debug, plain }
}

// MARK: - Service

@MainActor
final class OpenClawService: ObservableObject {

    // Status
    @Published var status: OCStatus?
    @Published var healthRaw: String = ""
    @Published var isOnline = false
    @Published var isLoadingStatus = false

    // Sessions
    @Published var sessions: [OCSession] = []
    @Published var sessionCount: Int = 0

    // Logs
    @Published var logs: [LogLine] = []
    @Published var isLoadingLogs = false

    // Skills
    @Published var skills: [OCSkill] = []
    @Published var skillsSummary: String = ""
    @Published var isLoadingSkills = false

    // Workspace
    @Published var workspaceFiles: [String] = []
    @Published var selectedFileContent: String = ""
    @Published var selectedFile: String = ""
    @Published var isLoadingFile = false

    // Cron
    @Published var cronRaw: String = ""
    @Published var isLoadingCron = false

    // Model
    @Published var currentModel: String = ""
    @Published var isModelLoaded: Bool = false

    // Chat
    @Published var chatMessages: [ChatMessage] = []
    @Published var isSending = false

    // Gateway operation in progress
    enum GatewayOp { case starting, stopping, restarting }
    @Published var gatewayOp: GatewayOp? = nil
    // Brief result flash ("started", "stopped", "restarted", "failed")
    @Published var gatewayResult: String? = nil

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
        let time = Date()
        enum Role { case user, agent }
    }

    private let wsPath = NSHomeDirectory() + "/.openclaw/workspace"
    private let cache = UserDefaults.standard

    init() {
        // Restore cached state — first frame shows real data before any async work
        isOnline     = cache.bool(forKey: "ch.isOnline")
        sessionCount = cache.integer(forKey: "ch.sessionCount")
        healthRaw    = cache.string(forKey: "ch.healthRaw") ?? ""
        loadCurrentModel()      // sync file read, <1ms
        loadSessionsDirect()    // sync file read, <1ms, populates sessions instantly
        Task { await loadStatus() }
    }

    // MARK: - Status

    private var lastStatusCheck: Date = .distantPast

    func loadStatus(force: Bool = false) async {
        guard force || status == nil || Date().timeIntervalSince(lastStatusCheck) > 30 else { return }
        isLoadingStatus = true
        defer { isLoadingStatus = false }
        lastStatusCheck = Date()

        // Fast path: HTTP ping resolves in ~100ms (no Node startup)
        // CLI status runs concurrently for richer data
        async let pingResult  = pingGateway()
        async let sOut        = runClaw("status --json")
        async let hOut        = runClaw("health 2>/dev/null", timeout: 6)

        // Update online indicator as soon as ping resolves (fastest)
        let online = await pingResult
        isOnline = online
        cache.set(online, forKey: "ch.isOnline")

        // Refresh sessions from disk while CLI finishes (zero subprocess cost)
        loadSessionsDirect()

        let (s, h) = await (sOut, hOut)

        if let data = s.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(OCStatus.self, from: data) {
            status = decoded
            if !isOnline { isOnline = true; cache.set(true, forKey: "ch.isOnline") }
        } else if !s.isEmpty {
            isOnline = false
            cache.set(false, forKey: "ch.isOnline")
        }

        let health = h.trimmingCharacters(in: .whitespacesAndNewlines)
        if !health.isEmpty {
            healthRaw = health
            cache.set(health, forKey: "ch.healthRaw")
        }
    }

    // MARK: - Sessions

    /// Fast: reads sessions.json directly from disk — no subprocess, instant.
    func loadSessionsDirect() {
        let path = NSHomeDirectory() + "/.openclaw/agents/main/sessions/sessions.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        let now = Date().timeIntervalSince1970 * 1000
        var result: [OCSession] = []
        for (key, value) in dict {
            guard let obj = value as? [String: Any] else { continue }
            let updatedAt = obj["updatedAt"] as? Double
            let ageMs = updatedAt.map { now - $0 }
            result.append(OCSession(
                key: key,
                agentId: obj["agentId"] as? String ?? "main",
                kind: obj["kind"] as? String,
                sessionId: obj["sessionId"] as? String,
                updatedAt: updatedAt,
                ageMs: ageMs,
                age: nil,
                totalTokens: obj["totalTokens"] as? Int,
                contextTokens: obj["contextTokens"] as? Int,
                percentUsed: obj["percentUsed"] as? Int,
                remainingTokens: obj["remainingTokens"] as? Int,
                model: obj["model"] as? String,
                flags: obj["flags"] as? [String]
            ))
        }
        sessions = result.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
        sessionCount = result.count
        cache.set(sessionCount, forKey: "ch.sessionCount")
    }

    /// Slow fallback: CLI-based session load (keeps richer CLI-computed fields if needed).
    func loadSessions() async {
        let out = await runClaw("sessions --json")
        guard let data = out.data(using: .utf8),
              let resp = try? JSONDecoder().decode(OCSessionsResponse.self, from: data)
        else { return }
        sessions = resp.sessions
        sessionCount = resp.count ?? resp.sessions.count
        cache.set(sessionCount, forKey: "ch.sessionCount")
    }

    // MARK: - HTTP ping (fast online check — no subprocess)

    private func pingGateway() async -> Bool {
        guard let url = URL(string: "http://localhost:18789/") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 1.5)
        req.httpMethod = "HEAD"
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse) != nil
        } catch { return false }
    }

    // MARK: - Logs

    func loadLogs(limit: Int = 150) async {
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        let logPath = NSHomeDirectory() + "/.openclaw/logs/gateway.log"
        if let raw = try? String(contentsOfFile: logPath, encoding: .utf8) {
            let lines = raw.components(separatedBy: "\n")
            let tail = lines.suffix(limit)
            logs = tail.compactMap { line -> LogLine? in
                return line.isEmpty ? nil : LogLine(text: line)
            }
        } else {
            // Fallback to CLI if file not found
            let out = await runClaw("logs --limit \(limit) --plain --timeout 6000", timeout: 12)
            logs = out.split(separator: "\n").compactMap { line -> LogLine? in
                let s = String(line)
                return s.isEmpty ? nil : LogLine(text: s)
            }
        }
    }

    // MARK: - Skills

    func loadSkills() async {
        isLoadingSkills = true
        defer { isLoadingSkills = false }
        let out = await runClaw("skills list", timeout: 20)

        // Summary line
        if let r = out.range(of: #"Skills \(\d+/\d+ ready\)"#, options: .regularExpression) {
            skillsSummary = String(out[r])
        }

        var result: [OCSkill] = []
        for line in out.components(separatedBy: "\n") {
            guard line.contains("│") else { continue }
            let cols = line.components(separatedBy: "│")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 4 else { continue }
            let statusCol = cols[1]
            guard statusCol.contains("ready") || statusCol.contains("missing") else { continue }
            let nameFull = cols[2]
            let descStr = cols[3]
            let ready = statusCol.contains("✓")
            let (icon, name) = splitIconName(nameFull)
            guard !name.isEmpty else { continue }
            result.append(OCSkill(name: name, icon: icon, description: descStr, ready: ready))
        }
        skills = result
    }

    private func splitIconName(_ s: String) -> (String, String) {
        // Find first ASCII letter to split emoji prefix from name
        for (i, c) in s.enumerated() {
            if c.isASCII, c.isLetter || c.isNumber {
                let idx = s.index(s.startIndex, offsetBy: i)
                let icon = String(s[..<idx]).trimmingCharacters(in: .whitespaces)
                let name = String(s[idx...]).trimmingCharacters(in: .whitespaces)
                return (icon.isEmpty ? "🔧" : icon, name)
            }
        }
        return ("🔧", s)
    }

    // MARK: - Workspace

    func loadWorkspaceFiles() async {
        let fm = FileManager.default
        var files: [String] = []
        if let main = try? fm.contentsOfDirectory(atPath: wsPath)
            .filter({ $0.hasSuffix(".md") }).sorted() {
            files.append(contentsOf: main)
        }
        let memPath = wsPath + "/memory"
        if let mem = try? fm.contentsOfDirectory(atPath: memPath)
            .filter({ $0.hasSuffix(".md") }).sorted()
            .map({ "memory/" + $0 }) {
            files.append(contentsOf: mem)
        }
        workspaceFiles = files
        // Auto-select today's memory file if it exists, otherwise first file
        let todayFile = "memory/" + todayFilename()
        if files.contains(todayFile) {
            await loadFile(todayFile)
        } else if selectedFile.isEmpty, let first = files.first {
            await loadFile(first)
        }
    }

    private func todayFilename() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date()) + ".md"
    }

    func loadFile(_ filename: String) async {
        isLoadingFile = true
        defer { isLoadingFile = false }
        selectedFile = filename
        let path = wsPath + "/" + filename
        selectedFileContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "(Could not read file)"
    }

    func saveFile(_ filename: String, content: String) {
        let path = wsPath + "/" + filename
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        selectedFileContent = content
    }

    // MARK: - Model

    func loadCurrentModel() {
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agents = json["agents"] as? [String: Any],
              let defaults = agents["defaults"] as? [String: Any],
              let model = defaults["model"] as? [String: Any],
              let primary = model["primary"] as? String
        else { return }
        currentModel = primary
        isModelLoaded = true
    }

    func switchModel(_ model: String) {
        let configPath = NSHomeDirectory() + "/.openclaw/openclaw.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var agents = json["agents"] as? [String: Any],
              var defaults = agents["defaults"] as? [String: Any],
              var modelDict = defaults["model"] as? [String: Any]
        else { return }
        modelDict["primary"] = model
        defaults["model"] = modelDict
        agents["defaults"] = defaults
        json["agents"] = agents
        guard let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) else { return }
        try? newData.write(to: URL(fileURLWithPath: configPath))
        currentModel = model
    }

    // MARK: - Cron

    func loadCron() async {
        isLoadingCron = true
        defer { isLoadingCron = false }
        cronRaw = await runClaw("cron list")
    }

    func addCronJob(message: String, every: String, label: String) async {
        let msg = message.replacingOccurrences(of: "'", with: "'\\''")
        let lbl = (label.isEmpty ? "BarClaw task" : label).replacingOccurrences(of: "'", with: "'\\''")
        _ = await runClaw("cron add --every '\(every)' --message '\(msg)' --label '\(lbl)'")
        await loadCron()
    }

    func removeCronJob(_ label: String) async {
        let lbl = label.replacingOccurrences(of: "'", with: "'\\''")
        _ = await runClaw("cron rm '\(lbl)'")
        await loadCron()
    }

    // MARK: - Chat

    func sendChat(_ message: String) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatMessages.append(.init(role: .user, text: trimmed))
        isSending = true
        defer { isSending = false }
        // Escape single quotes for shell
        let escaped = trimmed.replacingOccurrences(of: "'", with: "'\\''")
        // No --json: plain stdout always contains the reply text.
        // With --json, payloads is empty when the gateway delivers to Telegram directly.
        let out = await runClaw("agent --agent main --local -m '\(escaped)'", timeout: 90)
        // Strip any leading gateway warning lines (start with known prefixes)
        let reply = out
            .components(separatedBy: "\n")
            .filter { line in
                !line.hasPrefix("Gateway agent failed") &&
                !line.hasPrefix("gateway connect failed") &&
                !line.hasPrefix("[tools]")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        chatMessages.append(.init(role: .agent, text: reply.isEmpty ? "…" : reply))
    }

    // MARK: - Clear sessions

    func clearSessions() async {
        let dir = NSHomeDirectory() + "/.openclaw/agents/main/sessions"
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: dir) {
            for file in files where file.hasSuffix(".jsonl") {
                try? fm.removeItem(atPath: dir + "/" + file)
            }
        }
        try? "{}".write(toFile: dir + "/sessions.json", atomically: true, encoding: .utf8)
        sessions = []
        sessionCount = 0
        // Restart daemon so it rebuilds session map and Telegram reconnects
        await restartGateway()
    }

    // MARK: - Heartbeat

    @Published var heartbeatEnabled: Bool = true

    func sendHeartbeat() async {
        _ = await runClaw("agent --agent main --local -m '/heartbeat'", timeout: 30)
    }

    // MARK: - Gateway control

    func startGateway() async {
        gatewayOp = .starting
        defer { gatewayOp = nil }
        _ = await runClaw("daemon start", timeout: 15)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await loadStatus(force: true)
        flashResult(isOnline ? "started" : "failed")
    }

    func stopGateway() async {
        gatewayOp = .stopping
        defer { gatewayOp = nil }
        _ = await runClaw("daemon stop", timeout: 10)
        isOnline = false
        status = nil
        flashResult("stopped")
    }

    func restartGateway() async {
        gatewayOp = .restarting
        defer { gatewayOp = nil }
        _ = await runClaw("daemon restart", timeout: 20)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await loadStatus(force: true)
        flashResult(isOnline ? "restarted" : "failed")
    }

    private func flashResult(_ msg: String) {
        gatewayResult = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.gatewayResult = nil
        }
    }

    func toggleHeartbeat() async {
        let cmd = heartbeatEnabled ? "system heartbeat disable" : "system heartbeat enable"
        _ = await runClaw(cmd, timeout: 10)
        heartbeatEnabled.toggle()
    }
}

// MARK: - Helpers
func fmtNum(_ n: Int) -> String {
    n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
}
