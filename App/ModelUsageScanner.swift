import Foundation

/// Lê os logs locais do Claude Code (~/.claude/projects/**/*.jsonl) e soma tokens por modelo.
/// Leitura incremental: cada arquivo é lido só a partir do último byte já processado.
actor ModelUsageScanner {
    static let shared = ModelUsageScanner()

    private struct Record { let date: Date; let model: String; let tokens: Int }
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?; let output_tokens: Int?
                let cache_creation_input_tokens: Int?; let cache_read_input_tokens: Int?
            }
            let id: String?; let model: String?; let usage: Usage?
        }
        let type: String?; let timestamp: String?; let message: Message?
    }

    private var offsets: [String: UInt64] = [:]
    private var records: [String: Record] = [:]   // por message id (streaming repete o mesmo id)
    /// ~/.claude/projects costuma ser um symlink; o enumerator não entra em symlinks, então resolve antes.
    private let root: URL = {
        let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return base.appendingPathComponent("projects").resolvingSymlinksInPath()
    }()
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    func scan(now: Date = Date()) -> (session: [ModelUsage], week: [ModelUsage]) {
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) {
            for case let url as URL in e where url.pathExtension == "jsonl" {
                guard let v = try? url.resourceValues(forKeys: Set(keys)),
                      let mod = v.contentModificationDate, mod > weekAgo,
                      let size = v.fileSize.map(UInt64.init) else { continue }
                let start = offsets[url.path] ?? 0
                if size > start { read(url, from: start) }
            }
        }
        records = records.filter { $0.value.date > weekAgo }
        let all = Array(records.values)
        return (aggregate(all.filter { $0.date > now.addingTimeInterval(-5 * 3600) }), aggregate(all))
    }

    private func read(_ url: URL, from start: UInt64) {
        guard let h = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? h.close() }
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd(), let lastNL = data.lastIndex(of: 0x0A) else { return }
        // Só processa até a última quebra de linha; uma linha incompleta fica para a próxima leitura.
        offsets[url.path] = start + UInt64(lastNL + 1)
        let dec = JSONDecoder()
        for line in data[..<lastNL].split(separator: 0x0A) {
            guard line.count > 50, line.range(of: Data("\"assistant\"".utf8)) != nil,
                  let l = try? dec.decode(Line.self, from: Data(line)), l.type == "assistant",
                  let m = l.message, let id = m.id, let model = m.model, model.hasPrefix("claude"),
                  let u = m.usage, let ts = l.timestamp, let date = iso.date(from: ts) else { continue }
            let tokens = (u.input_tokens ?? 0) + (u.output_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0)
            records[id] = Record(date: date, model: model, tokens: tokens)
        }
    }

    private func aggregate(_ rs: [Record]) -> [ModelUsage] {
        var tokens: [String: Int] = [:], count: [String: Int] = [:]
        for r in rs {
            let name = Self.prettyName(r.model)
            tokens[name, default: 0] += r.tokens
            count[name, default: 0] += 1
        }
        let total = max(1, tokens.values.reduce(0, +))
        return tokens.map { ModelUsage(name: $0.key, tokens: $0.value, messages: count[$0.key] ?? 0,
                                       share: Double($0.value) / Double(total) * 100) }
            .sorted { $0.tokens > $1.tokens }
    }

    /// "claude-opus-5-5" → "Opus 5.5"; "claude-sonnet-4-5-20250929" → "Sonnet 4.5"
    static func prettyName(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init).filter { $0 != "claude" && $0.count < 8 }
        guard !parts.isEmpty else { return id }
        let family = parts.removeFirst().capitalized
        return parts.isEmpty ? family : "\(family) \(parts.joined(separator: "."))"
    }
}
