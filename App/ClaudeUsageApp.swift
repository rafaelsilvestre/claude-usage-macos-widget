import SwiftUI
import WidgetKit
import ServiceManagement

@MainActor
final class UsageModel: ObservableObject {
    @Published var snapshot: UsageSnapshot? = UsageStore.load()
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task {
            do {
                let s = try await UsageFetcher.fetch()
                snapshot = s
                UsageStore.save(s)
            } catch {
                var s = snapshot ?? .placeholder
                s.error = error.localizedDescription
                snapshot = s
                UsageStore.save(s)
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

@main
struct ClaudeUsageApp: App {
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            if let s = model.snapshot {
                if let email = s.email { Text("\(email)\(s.plan.map { " · \($0)" } ?? "")") }
                Text("5 horas: \(Int(s.fiveHour.utilization))% · reseta em \(formatRemaining(s.fiveHour.resetsAt))")
                Text("Semanal: \(Int(s.sevenDay.utilization))% · reseta em \(formatRemaining(s.sevenDay.resetsAt))")
                if let e = s.error { Text("⚠️ \(e)") }
                Text("Atualizado \(s.fetchedAt.formatted(date: .omitted, time: .shortened))")
            }
            Divider()
            Button("Atualizar agora") { model.refresh() }
            Toggle("Abrir no login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { try? $0 ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }))
            Button("Sair") { NSApp.terminate(nil) }
        } label: {
            Text("✳︎ \(Int(model.snapshot?.fiveHour.utilization ?? 0))%")
        }
    }
}
