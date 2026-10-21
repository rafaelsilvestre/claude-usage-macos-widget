import Foundation

enum UsageFetcher {
    struct Creds: Decodable {
        struct OAuth: Decodable { let accessToken: String; let subscriptionType: String?; let rateLimitTier: String? }
        let claudeAiOauth: OAuth
    }
    struct Resp: Decodable {
        struct W: Decodable { let utilization: Double?; let resets_at: String? }
        struct Limit: Decodable {
            struct Scope: Decodable { struct Model: Decodable { let display_name: String? }; let model: Model? }
            let kind: String; let percent: Double?; let scope: Scope?
        }
        struct Breakdown: Decodable { struct Row: Decodable { let display_name: String; let percent: Double }; let rows: [Row] }
        let five_hour: W?
        let seven_day: W?
        let limits: [Limit]?
        let seven_day_breakdown: Breakdown?
    }
    struct Profile: Decodable {
        struct Account: Decodable { let email: String? }
        struct Org: Decodable { let rate_limit_tier: String?; let organization_type: String? }
        let account: Account?
        let organization: Org?
    }

    static func readCreds() throws -> Creds.OAuth {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0 else { throw err("Credenciais do Claude Code não encontradas — faça login no Claude Code") }
        return try JSONDecoder().decode(Creds.self, from: data).claudeAiOauth
    }

    private static func get<T: Decodable>(_ path: String, token: String) async throws -> T {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/\(path)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw err(code == 401 ? "Token expirado — abra o Claude Code" : "HTTP \(code)") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Perfil muda raramente; guardado em memória e buscado só quando falta.
    private static var cachedProfile: Profile?

    static func fetch() async throws -> UsageSnapshot {
        let creds = try readCreds()
        let r: Resp = try await get("usage", token: creds.accessToken)
        if cachedProfile == nil { cachedProfile = try? await get("profile", token: creds.accessToken) }

        let scoped = (r.limits ?? []).compactMap { l -> ScopedLimit? in
            guard l.kind == "weekly_scoped", let name = l.scope?.model?.display_name else { return nil }
            return ScopedLimit(name: name, percent: l.percent ?? 0)
        }
        let breakdown = (r.seven_day_breakdown?.rows ?? [])
            .filter { $0.percent > 0 }
            .map { BreakdownRow(name: $0.display_name, percent: $0.percent) }

        return UsageSnapshot(
            fiveHour: window(r.five_hour), sevenDay: window(r.seven_day), fetchedAt: Date(),
            email: cachedProfile?.account?.email,
            plan: planName(tier: cachedProfile?.organization?.rate_limit_tier ?? creds.rateLimitTier,
                           fallback: creds.subscriptionType),
            scoped: scoped, breakdown: breakdown)
    }

    private static func planName(tier: String?, fallback: String?) -> String? {
        let t = tier ?? ""
        if t.contains("max_20x") { return "Max 20x" }
        if t.contains("max_5x") { return "Max 5x" }
        if t.contains("max") { return "Max" }
        if t.contains("pro") { return "Pro" }
        return fallback?.capitalized
    }

    private static func window(_ w: Resp.W?) -> UsageWindow {
        UsageWindow(utilization: w?.utilization ?? 0, resetsAt: w?.resets_at.flatMap(parseDate))
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private static func err(_ m: String) -> NSError { NSError(domain: "ClaudeUsage", code: 1, userInfo: [NSLocalizedDescriptionKey: m]) }
}
