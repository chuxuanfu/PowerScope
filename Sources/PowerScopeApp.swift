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
            Text(verbatim: model.menuTitle)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuContent: View {
    @ObservedObject var model: PowerModel
    @Environment(\.openWindow) private var openWindow

    private var statusTint: Color {
        model.statusText == "实时监测中" ? MetricID.system.tint : MetricID.batteryDischarge.tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("PowerScope")
                    .font(.headline)
                Spacer(minLength: 4)
                Text(model.statusText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(statusTint)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.visibleMetrics.contains(.system) {
                readingRow(title: MetricID.system.title, symbol: MetricID.system.symbol,
                           reading: powerText(.system), tint: MetricID.system.tint, prominent: true)
                    .padding(12)
                    .background(MetricID.system.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            ForEach(MetricID.allCases.filter { $0 != .system && model.visibleMetrics.contains($0) }) { metric in
                readingRow(title: metric.title, symbol: metric.symbol, reading: powerText(metric), tint: metric.tint)
            }

            if model.showEnergy {
                Divider()
                readingRow(title: "累计整机耗电", symbol: "bolt.circle",
                           reading: String(format: "%.3f Wh", model.totals.systemWh), tint: .yellow)
            }

            Divider()
            HStack(spacing: 10) {
                Button("打开详细窗口") {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button(model.isPaused ? "继续监测" : "暂停监测") { model.togglePause() }
                Spacer()
                Button("退出") { model.persist(); NSApp.terminate(nil) }
                    .accessibilityLabel("退出 PowerScope")
                    .keyboardShortcut("q")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 320)
        .foregroundStyle(.white)
        .background(Color(red: 0.055, green: 0.075, blue: 0.105))
        .environment(\.colorScheme, .dark)
    }

    private func powerText(_ metric: MetricID) -> String {
        model.value(metric).map { formatPower($0) + " W" } ?? "不可用"
    }

    private func readingRow(title: String, symbol: String, reading: String, tint: Color, prominent: Bool = false) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Spacer(minLength: 8)
            Text(reading)
                .font(.system(size: prominent ? 24 : 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}
