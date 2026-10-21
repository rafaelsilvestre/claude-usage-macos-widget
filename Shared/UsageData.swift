import Foundation

let appGroupID = "G9PHDKA735.com.rafaelsilvestre.claudeusage"

struct UsageWindow: Codable {
    var utilization: Double
    var resetsAt: Date?
}

struct ScopedLimit: Codable, Hashable {
    var name: String
    var percent: Double
}

struct BreakdownRow: Codable, Hashable {
    var name: String
    var percent: Double
}

struct ModelUsage: Codable, Hashable {
    var name: String
    var tokens: Int
    var messages: Int
    var share: Double
}

struct UsageSnapshot: Codable {
    var fiveHour: UsageWindow
    var sevenDay: UsageWindow
    var fetchedAt: Date
    var error: String?
    var email: String?
    var plan: String?
    var scoped: [ScopedLimit] = []
    var breakdown: [BreakdownRow] = []
    var modelsSession: [ModelUsage] = []
    var modelsWeek: [ModelUsage] = []

    static let placeholder = UsageSnapshot(
        fiveHour: .init(utilization: 25, resetsAt: Date().addingTimeInterval(7200)),
        sevenDay: .init(utilization: 40, resetsAt: Date().addingTimeInterval(86400 * 3)),
        fetchedAt: Date(), email: "voce@exemplo.com", plan: "Max 5x",
        scoped: [.init(name: "Fable", percent: 5)],
        breakdown: [.init(name: "Claude Code", percent: 90), .init(name: "Chats", percent: 10)],
        modelsSession: [.init(name: "Opus 5.5", tokens: 1_840_000, messages: 212, share: 81),
                        .init(name: "Haiku 5.5", tokens: 430_000, messages: 96, share: 19)],
        modelsWeek: [.init(name: "Opus 5.5", tokens: 21_400_000, messages: 2310, share: 72),
                     .init(name: "Sonnet 5.5", tokens: 5_900_000, messages: 840, share: 20),
                     .init(name: "Haiku 5.5", tokens: 2_400_000, messages: 1120, share: 8)])
}

extension UsageWindow {
    /// Fração do tempo da janela já decorrida (0...1), para comparar com o uso.
    func elapsed(windowLength: TimeInterval, now: Date = Date()) -> Double? {
        guard let resetsAt else { return nil }
        return min(1, max(0, 1 - resetsAt.timeIntervalSince(now) / windowLength))
    }
}

enum UsageStore {
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("usage.json")
    }

    static func save(_ s: UsageSnapshot) {
        guard let url = fileURL else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try? enc.encode(s).write(to: url, options: .atomic)
    }

    static func load() -> UsageSnapshot? {
        guard let url = fileURL, let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(UsageSnapshot.self, from: d)
    }
}

func formatRemaining(_ date: Date?, from now: Date = Date()) -> String {
    guard let date else { return "—" }
    let s = max(0, Int(date.timeIntervalSince(now)))
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)min" }
    return "\(m)min"
}

func formatTokens(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...: return String(format: "%.0fk", Double(n) / 1_000)
    default: return "\(n)"
    }
}
