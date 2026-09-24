import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct PowerScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = PowerModel()

    var body: some Scene {
        Window("PowerScope · 实时功率", id: "dashboard") {
            DashboardView(model: model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .defaultSize(width: 1180, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("监测") {
                Button(model.isPaused ? "继续监测" : "暂停监测") { model.togglePause() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("导出历史 CSV…") { model.exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command])
            }
        }
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Label(model.menuTitle, systemImage: "bolt.fill")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuContent: View {
    @ObservedObject var model: PowerModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("PowerScope · \(model.statusText)")
        ForEach(MetricID.allCases.filter { model.visibleMetrics.contains($0) }) { metric in
            Text("\(metric.title)   \(model.value(metric).map { formatPower($0) + " W" } ?? "不可用")")
        }
        if model.showEnergy { Text(String(format: "累计整机耗电   %.3f Wh", model.totals.systemWh)) }
        Divider()
        Button("打开详细窗口") {
            openWindow(id: "dashboard")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(model.isPaused ? "继续监测" : "暂停监测") { model.togglePause() }
        Divider()
        Button("退出 PowerScope") { model.persist(); NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
