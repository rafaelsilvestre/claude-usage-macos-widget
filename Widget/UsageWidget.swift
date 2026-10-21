import WidgetKit
import SwiftUI

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: UsageStore.load() ?? .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let s = UsageStore.load() ?? .placeholder
        let now = Date()
        // Uma entrada por minuto (contagem regressiva); o app reabastece os dados a cada minuto.
        let entries = (0..<60).map { Entry(date: now.addingTimeInterval(Double($0) * 60), snapshot: s) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(60))))
    }
}

let accent = Color(red: 0.85, green: 0.47, blue: 0.34)

func color(for pct: Double) -> Color {
    pct >= 90 ? .red : pct >= 70 ? .orange : accent
}

struct Gauge: View {
    let title: String
    let window: UsageWindow
    let windowLength: TimeInterval
    let now: Date
    var showPace = false

    var body: some View {
        let elapsed = window.elapsed(windowLength: windowLength, now: now)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.utilization))%").font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(color(for: window.utilization))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color(for: window.utilization))
                        .frame(width: geo.size.width * min(window.utilization, 100) / 100)
                    // Marcador do tempo decorrido na janela: barra à direita dele = acima do ritmo.
                    if let elapsed {
                        Rectangle().fill(.primary.opacity(0.6))
                            .frame(width: 1.5, height: geo.size.height + 4)
                            .offset(x: geo.size.width * elapsed - 0.75)
                    }
                }
            }
            .frame(height: 6)
            HStack {
                Text("↻ \(formatRemaining(window.resetsAt, from: now))")
                Spacer()
                if showPace, let elapsed { PaceLabel(usage: window.utilization / 100, elapsed: elapsed) }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct PaceLabel: View {
    let usage: Double
    let elapsed: Double
    var body: some View {
        let diff = Int(((usage - elapsed) * 100).rounded())
        if diff > 5 {
            Text("▲ \(diff)% acima").foregroundStyle(.orange)
        } else if diff < -5 {
            Text("▼ \(-diff)% abaixo")
        } else {
            Text("no ritmo")
        }
    }
}

struct Header: View {
    let s: UsageSnapshot
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.email ?? "Claude").font(.caption.bold()).lineLimit(1).truncationMode(.middle)
                if let plan = s.plan { Text(plan).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if s.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }
}

struct Footer: View {
    let s: UsageSnapshot
    var body: some View {
        Text(s.error ?? "Atualizado às \(s.fetchedAt.formatted(date: .omitted, time: .shortened))")
            .font(.caption2).foregroundStyle(s.error == nil ? Color.secondary : Color.orange).lineLimit(1)
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    var body: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
            Header(s: s)
            let session = Gauge(title: "Sessão (5h)", window: s.fiveHour, windowLength: 5 * 3600,
                                now: entry.date, showPace: family != .systemSmall)
            let weekly = Gauge(title: "Semanal", window: s.sevenDay, windowLength: 7 * 86400,
                               now: entry.date, showPace: family != .systemSmall)
            if family == .systemMedium {
                HStack(alignment: .top, spacing: 16) { session; weekly }
            } else {
                session
                weekly
            }
            if family != .systemSmall {
                ForEach(s.scoped, id: \.self) { l in
                    HStack {
                        Text("Semanal · \(l.name)").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(l.percent))%").bold().foregroundStyle(color(for: l.percent))
                    }
                    .font(.caption)
                }
            }
            if family == .systemLarge, !s.breakdown.isEmpty {
                Divider()
                Text("Uso semanal por produto").font(.caption).foregroundStyle(.secondary)
                ForEach(s.breakdown, id: \.self) { r in
                    HStack {
                        Text(r.name).font(.caption)
                        Spacer()
                        Text("\(Int(r.percent))%").font(.caption.monospacedDigit())
                    }
                }
            }
            if family != .systemSmall {
                Spacer(minLength: 0)
                Footer(s: s)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UsageWidget", provider: Provider()) { UsageWidgetView(entry: $0) }
            .configurationDisplayName("Uso do Claude")
            .description("Conta, plano, limite de 5 horas e semanal.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
