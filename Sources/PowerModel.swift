import AppKit
import SwiftUI
import Foundation

enum MetricID: String, CaseIterable, Identifiable, Codable {
    case system, adapter, batteryDischarge, batteryCharge, chip, cpu, gpu, ane, display
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "整机功率"
        case .adapter: return "充电器输入"
        case .batteryDischarge: return "电池供电"
        case .batteryCharge: return "电池充电"
        case .chip: return "芯片热功率估算"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ane: return "神经网络引擎"
        case .display: return "屏幕背光"
        }
    }
    var shortTitle: String {
        switch self {
        case .system: return "整机"
        case .adapter: return "输入"
        case .batteryDischarge: return "电池供电"
        case .batteryCharge: return "充电"
        case .chip: return "芯片热估算"
        case .ane: return "ANE"
        default: return title
        }
    }
    var symbol: String {
        switch self {
        case .system: return "laptopcomputer"
        case .adapter: return "powerplug.fill"
        case .batteryDischarge: return "battery.75percent"
        case .batteryCharge: return "battery.100percent.bolt"
        case .chip, .cpu: return "cpu"
        case .gpu: return "square.stack.3d.up.fill"
        case .ane: return "brain.head.profile"
        case .display: return "display"
        }
    }
    var tint: Color {
        switch self {
        case .system: return Color(red: 0.29, green: 0.89, blue: 0.74)
        case .adapter: return Color(red: 0.38, green: 0.70, blue: 1.00)
        case .batteryDischarge: return Color(red: 1.00, green: 0.70, blue: 0.36)
        case .batteryCharge: return Color(red: 0.76, green: 0.65, blue: 1.00)
        case .chip: return Color(red: 0.96, green: 0.55, blue: 0.66)
        case .cpu: return Color(red: 0.95, green: 0.44, blue: 0.50)
        case .gpu: return Color(red: 0.68, green: 0.62, blue: 1.00)
        case .ane: return Color(red: 0.85, green: 0.77, blue: 0.39)
        case .display: return Color(red: 0.46, green: 0.85, blue: 0.98)
        }
    }
}

struct PowerPoint: Identifiable, Codable {
    var id = UUID()
    var time: Date
    var values: [String: Double]
}

private struct SavedState: Codable {
    var totals: EnergyTotals
    var history: [PowerPoint]
    var visibleMetrics: Set<MetricID>
    var chartMetrics: Set<MetricID>
    var refreshInterval: Double
    var chartWindow: Double
    var showEnergy: Bool
    var showChart: Bool
    var showFlow: Bool
    var menuMetric: MetricID
}

@MainActor
final class PowerModel: ObservableObject {
    @Published var history: [PowerPoint] = []
    @Published var totals = EnergyTotals()
    @Published var visibleMetrics: Set<MetricID> = [.system, .adapter, .batteryDischarge, .batteryCharge, .chip, .display] { didSet { persist() } }
    @Published var chartMetrics: Set<MetricID> = [.system, .adapter, .batteryDischarge] { didSet { persist() } }
    @Published var isPaused = false
    @Published var refreshInterval: Double = 5 { didSet { if !loading { restartTimer(); persist() } } }
    @Published var chartWindow: Double = 15 { didSet { persist() } }
    @Published var showEnergy = true { didSet { persist() } }
    @Published var showChart = true { didSet { persist() } }
    @Published var showFlow = true { didSet { persist() } }
    @Published var menuMetric: MetricID = .system { didSet { persist() } }
    @Published var lastUpdated: Date?
    @Published var statusText = "正在连接电源传感器"
    @Published private var latest: NativeSnapshot?
    @Published private var firmwareUpdated: Date?
    @Published var storageMessage: String?

    private var ledger = EnergyLedger()
    private let queue = DispatchQueue(label: "local.PowerScope.sensors", qos: .utility)
    private let sensors = NativeSensors()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var pending = false
    private var loading = true
    private var sleeping = false
    private var lastCounter: UInt64?
    private var lastFingerprint: String?
    private var lastSave = Date.distantPast
    private var readingGeneration = 0
    private let stateURL: URL
    let deviceName: String

    var batteryPercent: Double? { latest?.batteryPercent }
    var externalConnected: Bool { latest?.externalConnected ?? false }
    var isCharging: Bool { latest?.isCharging ?? false }
    var firmwareAgeSeconds: Double? { firmwareUpdated.map { max(0, Date().timeIntervalSince($0)) } }
    var sensorNotes: [String] {
        var notes = latest?.notes ?? []
        notes.append("整机读数包含内置屏幕等机内负载，不含外部电源适配器损耗及独立供电显示器。")
        notes.append("充电器输入 + 电池供电 ≈ 整机功率 + 电池充电；充电功率不重复计入整机耗电。")
        notes.append("累计 Wh 是监测期间的估算。暂停、睡眠、退出及超过 30 秒的采样中断不补算。")
        if let warning = storageMessage { notes.append(warning) }
        return notes
    }
    var menuTitle: String {
        if isPaused { return "暂停" }
        guard let watts = value(menuMetric) else { return "— W" }
        let prefix = menuMetric == .system ? "" : menuMetric.shortTitle + " "
        return prefix + formatPower(watts) + " W"
    }

    init() {
        let override = ProcessInfo.processInfo.environment["POWERSCOPE_STATE_DIR"]
        let directory = override.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PowerScope", isDirectory: true)
        stateURL = directory.appendingPathComponent("state.json")
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        deviceName = String(cString: bytes)
        if let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            totals = saved.totals
            ledger = EnergyLedger(totals: saved.totals)
            history = saved.history.filter { $0.time > Date().addingTimeInterval(-86400) }
            visibleMetrics = saved.visibleMetrics
            chartMetrics = saved.chartMetrics
            refreshInterval = [2.0, 5.0, 10.0].contains(saved.refreshInterval) ? saved.refreshInterval : 5
            chartWindow = [1.0, 5.0, 15.0, 60.0].contains(saved.chartWindow) ? saved.chartWindow : 15
            showEnergy = saved.showEnergy
            showChart = saved.showChart
            showFlow = saved.showFlow
            menuMetric = saved.menuMetric
        }
        loading = false
        // Explicitly mark a new run so charts do not bridge even brief app exits.
        if !history.isEmpty { history.append(PowerPoint(time: Date(), values: [:])) }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleepChanged(true) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleepChanged(false) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.persist() }
        })
        restartTimer()
        refreshNow()
    }

    func value(_ metric: MetricID) -> Double? {
        guard let snapshot = latest else { return nil }
        if !isPaused, (firmwareAgeSeconds ?? 0) > 120,
           [.system, .adapter, .batteryDischarge, .batteryCharge].contains(metric) { return nil }
        switch metric {
        case .system: return snapshot.systemWatts
        case .adapter: return snapshot.adapterWatts
        case .batteryDischarge: return snapshot.batteryWatts.map { max(0, -$0) }
        case .batteryCharge: return snapshot.batteryWatts.map { max(0, $0) }
        default: return snapshot.sensorReadings.first { $0.key == metric.rawValue }?.watts
        }
    }

    func source(_ metric: MetricID) -> String {
        switch metric {
        case .system: return "电源遥测 · SystemLoad"
        case .adapter: return "电源遥测 · SystemPowerIn"
        case .batteryDischarge, .batteryCharge: return "电源遥测 · BatteryPower"
        default: return latest?.sensorReadings.first { $0.key == metric.rawValue }?.source ?? "此设备未提供可用的独立读数"
        }
    }

    func detail(_ metric: MetricID) -> String {
        switch metric {
        case .system: return "机内总负载 · 包含内置屏幕"
        case .adapter: return "进入 Mac 的实际输入功率"
        case .batteryDischarge: return "电池向电脑提供的功率"
        case .batteryCharge: return "存入电池的功率 · 不计入整机耗电"
        case .chip:
            return latest?.sensorReadings.first { $0.key == "chip" }?.name ?? "无可用的 SoC 热功率模型；不以整机功率代替"
        case .display:
            return latest?.sensorReadings.first { $0.key == "display" }?.name ?? "无独立传感器；不把整机减去芯片当作屏幕"
        default:
            return latest?.sensorReadings.first { $0.key == metric.rawValue }?.name ?? "传感器不可用或等待首个采样区间"
        }
    }

    func refreshNow() {
        guard !pending, !isPaused, !sleeping else { return }
        pending = true
        let generation = readingGeneration
        queue.async { [weak self, sensors] in
            let snapshot = sensors.read()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending = false
                guard !self.isPaused, !self.sleeping, self.readingGeneration == generation else { return }
                self.receive(snapshot)
            }
        }
    }

    private func receive(_ snapshot: NativeSnapshot) {
        let now = snapshot.timestamp
        latest = snapshot
        lastUpdated = now
        let fingerprint = "\(snapshot.systemWatts ?? -1)|\(snapshot.adapterWatts ?? -1)|\(snapshot.batteryWatts ?? -1)"
        if let counter = snapshot.firmwareCounter {
            if lastCounter != counter { firmwareUpdated = now }
            lastCounter = counter
        } else if lastFingerprint != fingerprint || firmwareUpdated == nil {
            firmwareUpdated = now
        }
        lastFingerprint = fingerprint
        let stale = firmwareUpdated.map { now.timeIntervalSince($0) > 120 } ?? false
        if snapshot.systemWatts == nil {
            statusText = "整机遥测暂不可用"
        } else if stale {
            statusText = "电源遥测超过 2 分钟未更新"
        } else {
            statusText = "实时监测中"
        }
        if stale {
            ledger.breakContinuity()
        } else {
            ledger.ingest(time: now, system: snapshot.systemWatts, adapter: snapshot.adapterWatts, battery: snapshot.batteryWatts)
        }
        totals = ledger.totals
        var values: [String: Double] = [:]
        for metric in MetricID.allCases {
            if let v = value(metric), v.isFinite, !stale || ![.system, .adapter, .batteryDischarge, .batteryCharge].contains(metric) {
                values[metric.rawValue] = v
            }
        }
        history.append(PowerPoint(time: now, values: values))
        if history.count > 18000 { history.removeFirst(history.count - 18000) }
        history.removeAll { $0.time < now.addingTimeInterval(-86400) }
        if now.timeIntervalSince(lastSave) > 60 { persist() }
    }

    private func restartTimer() {
        timer?.invalidate()
        guard !isPaused, !sleeping else { return }
        timer = Timer.scheduledTimer(withTimeInterval: max(2, refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        timer?.tolerance = min(1, refreshInterval * 0.15)
    }

    func togglePause() {
        isPaused.toggle()
        readingGeneration += 1
        ledger.breakContinuity()
        history.append(PowerPoint(time: Date(), values: [:]))
        statusText = isPaused ? "已暂停 · 累计耗电停止计数" : "正在恢复采样"
        restartTimer()
        persist()
        if !isPaused { refreshNow() }
    }

    private func sleepChanged(_ asleep: Bool) {
        sleeping = asleep
        readingGeneration += 1
        ledger.breakContinuity()
        history.append(PowerPoint(time: Date(), values: [:]))
        if !asleep { firmwareUpdated = nil; lastCounter = nil }
        restartTimer()
        persist()
        if !asleep { refreshNow() }
    }

    func resetEnergy() {
        ledger.reset(at: Date())
        totals = ledger.totals
        persist()
    }

    func persist() {
        guard !loading else { return }
        let saved = SavedState(totals: totals, history: history, visibleMetrics: visibleMetrics, chartMetrics: chartMetrics, refreshInterval: refreshInterval, chartWindow: chartWindow, showEnergy: showEnergy, showChart: showChart, showFlow: showFlow, menuMetric: menuMetric)
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: stateURL, options: .atomic)
            lastSave = Date()
            if storageMessage != nil { storageMessage = nil }
        } catch {
            storageMessage = "本地记录暂未保存：\(error.localizedDescription)"
        }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PowerScope-\(Date().formatted(.iso8601.year().month().day())) .csv".replacingOccurrences(of: " .csv", with: ".csv")
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.message = "导出已记录的功率历史；空白表示该时刻无可用读数。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let formatter = ISO8601DateFormatter()
        let keys = MetricID.allCases
        var csv = "timestamp," + keys.map { $0.rawValue + "_W" }.joined(separator: ",") + "\n"
        for point in history {
            csv += formatter.string(from: point.time) + "," + keys.map { key in
                point.values[key.rawValue].map { String(format: "%.6f", $0) } ?? ""
            }.joined(separator: ",") + "\n"
        }
        do { try csv.write(to: url, atomically: true, encoding: .utf8) }
        catch { storageMessage = "导出失败：\(error.localizedDescription)" }
    }
}

func formatPower(_ watts: Double) -> String {
    let magnitude = abs(watts)
    let decimals = magnitude > 0 && magnitude < 0.01 ? 3 : magnitude > 0 && magnitude < 1 ? 2 : 1
    return String(format: "%.*f", decimals, watts == 0 ? 0 : watts)
}
