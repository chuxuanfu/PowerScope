import SwiftUI
import Charts
import AppKit

private enum ScopeStyle {
    static let canvas = Color(red: 0.038, green: 0.055, blue: 0.085)
    static let panel = Color(red: 0.070, green: 0.090, blue: 0.125)
    static let inset = Color(red: 0.045, green: 0.065, blue: 0.098)
    static let line = Color.white.opacity(0.085)
    static let primary = Color(red: 0.91, green: 0.94, blue: 0.97)
    static let secondary = Color(red: 0.53, green: 0.60, blue: 0.69)
    static let teal = Color(red: 0.34, green: 0.89, blue: 0.76)
    static let blue = Color(red: 0.40, green: 0.71, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.37)
}

struct DashboardView: View {
    @ObservedObject var model: PowerModel
    @State private var showingCustomization = false
    @State private var showingSources = false

    private var secondaryMetrics: [MetricID] {
        MetricID.allCases.filter { $0 != .system && model.visibleMetrics.contains($0) }
    }
    private var statusColor: Color {
        model.isPaused || model.statusText != "实时监测中" ? ScopeStyle.amber : ScopeStyle.teal
    }
    private var monitoringLabel: String {
        if model.isPaused { return "监测已暂停" }
        if model.statusText == "实时监测中" { return "实时监测" }
        return model.lastUpdated == nil ? "正在读取" : "请留意传感器状态"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if model.visibleMetrics.contains(.system) || model.showFlow {
                    HStack(alignment: .top, spacing: 18) {
                        if model.visibleMetrics.contains(.system) {
                            totalPowerCard
                                .frame(maxWidth: model.showFlow ? 380 : .infinity)
                        }
                        if model.showFlow {
                            PowerFlowCard(model: model)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                if !secondaryMetrics.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeading("实时读数", subtitle: "单位 W · 缺失读数显示 —")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 198), spacing: 12)], spacing: 12) {
                            ForEach(secondaryMetrics) { metric in
                                MetricCard(model: model, metric: metric)
                            }
                        }
                    }
                }

                if model.showChart || model.showEnergy {
                    HStack(alignment: .top, spacing: 18) {
                        if model.showChart {
                            HistoryCard(model: model)
                                .frame(maxWidth: .infinity)
                        }
                        if model.showEnergy {
                            EnergyCard(model: model)
                                .frame(width: model.showChart ? 292 : nil)
                                .frame(maxWidth: model.showChart ? nil : .infinity)
                        }
                    }
                }

                if model.visibleMetrics.isEmpty && !model.showFlow && !model.showChart && !model.showEnergy {
                    VStack(spacing: 14) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(ScopeStyle.teal)
                        Text("创建你的监测面板")
                            .font(.system(size: 20, weight: .semibold))
                        Text("在显示设置中选择需要的功率读数、趋势和用电统计。")
                            .foregroundStyle(ScopeStyle.secondary)
                        Button("选择显示内容") { showingCustomization = true }
                            .buttonStyle(ScopeButtonStyle(emphasized: true))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(44)
                    .scopePanel()
                }

                sourcePanel
                footer
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 22)
            .frame(maxWidth: 1600)
            .frame(maxWidth: .infinity)
        }
        .background(ScopeStyle.canvas)
        .foregroundStyle(ScopeStyle.primary)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1000, minHeight: 700)
        .sheet(isPresented: $showingCustomization) {
            CustomizationSheet(model: model)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ScopeStyle.teal)
                    Text("POWER SCOPE")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(ScopeStyle.secondary)
                }
                Text("看见每一瓦")
                    .font(.system(size: 30, weight: .semibold))
                HStack(spacing: 8) {
                    Text(model.deviceName)
                    Text("·")
                    Text(model.statusText)
                        .lineLimit(1)
                }
                .font(.system(size: 12))
                .foregroundStyle(ScopeStyle.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 16) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(monitoringLabel)
                        .foregroundStyle(statusColor)
                    Text("/  \(Int(model.refreshInterval)) 秒采样")
                        .foregroundStyle(ScopeStyle.secondary)
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                HStack(spacing: 8) {
                    Button { model.refreshNow() } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 13)
                    }
                    .help("立即读取电源数据")
                    .accessibilityLabel("立即刷新")
                    Button { model.togglePause() } label: {
                        Label(model.isPaused ? "继续" : "暂停", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                    }
                    Button { showingCustomization = true } label: {
                        Label("显示设置", systemImage: "slider.horizontal.3")
                    }
                }
                .buttonStyle(ScopeButtonStyle())
            }
        }
    }

    private var totalPowerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("整机实时功率", systemImage: "laptopcomputer")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("SYSTEM")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(ScopeStyle.secondary)
            }
            .foregroundStyle(ScopeStyle.primary.opacity(0.88))
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(powerNumber(model.value(.system)))
                    .font(.system(size: 68, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(ScopeStyle.teal)
                Text("W")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(ScopeStyle.secondary)
            }
            .padding(.top, 15)
            Spacer(minLength: 12)
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                    .padding(.top, 1)
                Text("包含内置屏幕与内部硬件；不含电池充电及外部适配器损耗。")
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
            .font(.system(size: 11))
            .foregroundStyle(ScopeStyle.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 226, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color(red: 0.075, green: 0.16, blue: 0.17), ScopeStyle.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(ScopeStyle.teal.opacity(0.18), lineWidth: 1)
        }
        .help(model.source(.system) + "\n" + model.detail(.system))
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showingSources.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(ScopeStyle.teal)
                    Text("数据来源与测量边界")
                        .font(.system(size: 12, weight: .medium))
                    Text("真实遥测 · 缺失不补值")
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeStyle.secondary)
                    Spacer()
                    Image(systemName: showingSources ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ScopeStyle.secondary)
                }
                .padding(17)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showingSources {
                Rectangle().fill(ScopeStyle.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(Array(model.sensorNotes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(ScopeStyle.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top, spacing: 24) {
                        sourceNote(title: "芯片热功率估算", metric: .chip)
                        sourceNote(title: "屏幕背光（非完整屏幕）", metric: .display)
                    }
                    Text("整机与芯片的差值还包含内存、存储、无线通信、供电损耗等，不能作为屏幕功耗。")
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeStyle.amber.opacity(0.85))
                }
                .padding(18)
            }
        }
        .scopePanel(cornerRadius: 12)
    }

    private func sourceNote(title: String, metric: MetricID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(model.source(metric))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ScopeStyle.teal.opacity(0.85))
            Text(model.detail(metric))
                .font(.system(size: 11))
                .foregroundStyle(ScopeStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                Text("本机监测 · 数据保存在本机")
            }
            Spacer()
            if let lastUpdated = model.lastUpdated {
                Text("最近读取 " + lastUpdated.formatted(date: .omitted, time: .standard))
            } else {
                Text("等待首次读取")
            }
            if let age = model.firmwareAgeSeconds, age > 20 {
                Text("·  电池遥测约 \(Int(age)) 秒前")
                    .foregroundStyle(ScopeStyle.amber)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(ScopeStyle.secondary.opacity(0.85))
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(subtitle).font(.system(size: 10)).foregroundStyle(ScopeStyle.secondary)
        }
    }
}

private struct PowerFlowCard: View {
    @ObservedObject var model: PowerModel

    private var chargeWatts: Double? { model.value(.batteryCharge) }
    private var dischargeWatts: Double? { model.value(.batteryDischarge) }
    private var batteryIsCharging: Bool { (chargeWatts ?? 0) > 0 }
    private var batteryIsDischarging: Bool { (dischargeWatts ?? 0) > 0 }

    private var batteryState: String {
        if chargeWatts == nil && dischargeWatts == nil { return "状态未知" }
        if batteryIsCharging { return "正在充电" }
        if batteryIsDischarging { return "正在供电" }
        return "待机 / 未充放电"
    }

    private var batteryTitle: String {
        if batteryIsCharging { return "电池充电" }
        if batteryIsDischarging { return "电池供电" }
        return chargeWatts == nil && dischargeWatts == nil ? "电池功率" : "电池待机"
    }

    private var batteryArrow: String {
        if batteryIsCharging { return "arrow.right" }
        if batteryIsDischarging { return "arrow.left" }
        return "minus"
    }

    private var batteryFlowWatts: Double? {
        if batteryIsCharging { return chargeWatts }
        if batteryIsDischarging { return dischargeWatts }
        return chargeWatts ?? dischargeWatts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Text("电力从哪里来")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if let percent = model.batteryPercent {
                    Label("\(Int(percent))%", systemImage: "battery.75percent")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(ScopeStyle.secondary)
                }
            }
            HStack(spacing: 12) {
                flowNode(title: "充电器输入", icon: "powerplug.fill", value: model.value(.adapter), subtitle: model.externalConnected ? "外部电源已连接" : "外部电源未连接", color: ScopeStyle.blue)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ScopeStyle.secondary.opacity(0.6))
                VStack(spacing: 9) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 34, weight: .ultraLight))
                        .foregroundStyle(ScopeStyle.teal)
                    Text("Mac")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ScopeStyle.secondary)
                }
                .frame(width: 60)
                Image(systemName: batteryArrow)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ScopeStyle.secondary.opacity(0.6))
                flowNode(title: batteryTitle, icon: batteryIsCharging ? "battery.100percent.bolt" : "battery.75percent", value: batteryFlowWatts, subtitle: batteryState, color: ScopeStyle.amber)
            }
            Spacer(minLength: 0)
            Text("输入与输出由各传感器独立更新，短时读数可能存在时间差。")
                .font(.system(size: 10))
                .foregroundStyle(ScopeStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 226, alignment: .leading)
        .scopePanel()
    }

    private func flowNode(title: String, icon: String, value: Double?, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(powerNumber(value))
                    .font(.system(size: 30, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("W")
                    .font(.system(size: 12))
                    .foregroundStyle(ScopeStyle.secondary)
            }
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(ScopeStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricCard: View {
    @ObservedObject var model: PowerModel
    let metric: MetricID

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: metric.symbol)
                    .foregroundStyle(metric.tint)
                    .frame(width: 15)
                Text(metric.title)
                    .foregroundStyle(ScopeStyle.primary.opacity(0.85))
                Spacer(minLength: 2)
                if model.value(metric) == nil {
                    Image(systemName: "info.circle")
                        .foregroundStyle(ScopeStyle.secondary.opacity(0.6))
                }
            }
            .font(.system(size: 11, weight: .medium))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(powerNumber(model.value(metric)))
                    .font(.system(size: 30, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(model.value(metric) == nil ? ScopeStyle.secondary : ScopeStyle.primary)
                Text("W")
                    .font(.system(size: 12))
                    .foregroundStyle(ScopeStyle.secondary)
                Spacer()
                if model.value(metric) != nil {
                    MiniSparkline(model: model, metric: metric)
                        .frame(width: 63, height: 25)
                        .accessibilityHidden(true)
                }
            }
            Text(model.value(metric) == nil || metric == .chip || metric == .display ? model.detail(metric) : model.source(metric))
            .font(.system(size: 10))
            .foregroundStyle(ScopeStyle.secondary)
            .lineLimit(3)
            .frame(height: 40, alignment: .topLeading)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scopePanel(cornerRadius: 13)
        .help(model.source(metric) + "\n" + model.detail(metric))
    }
}

private struct MiniSparkline: View {
    @ObservedObject var model: PowerModel
    let metric: MetricID

    var body: some View {
        Chart(graphReadings(Array(model.history.suffix(25)), metric: metric)) { reading in
            LineMark(x: .value("时间", reading.time), y: .value("功率", reading.watts), series: .value("连续区间", reading.segment))
                .foregroundStyle(metric.tint.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.3))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

private struct HistoryCard: View {
    @ObservedObject var model: PowerModel
    @State private var selectedDate: Date?

    private var endDate: Date { model.history.last?.time ?? Date() }
    private var startDate: Date { endDate.addingTimeInterval(-model.chartWindow * 60) }
    private var points: [PowerPoint] { model.history.filter { $0.time >= startDate } }
    private var metrics: [MetricID] { MetricID.allCases.filter { model.chartMetrics.contains($0) } }
    private var nearestPoint: PowerPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) }
    }
    private var hasVisibleData: Bool {
        points.contains { point in metrics.contains { point.values[$0.rawValue] != nil } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("功率趋势").font(.system(size: 14, weight: .semibold))
                    Text("移动指针查看历史读数")
                        .font(.system(size: 10))
                        .foregroundStyle(ScopeStyle.secondary)
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach([1.0, 5.0, 15.0, 60.0], id: \.self) { minutes in
                        Button {
                            model.chartWindow = minutes
                            selectedDate = nil
                        } label: {
                            Text(minutes == 60 ? "1h" : "\(Int(minutes))m")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(model.chartWindow == minutes ? ScopeStyle.teal : ScopeStyle.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(model.chartWindow == minutes ? ScopeStyle.teal.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help("显示最近 \(Int(minutes)) 分钟")
                    }
                }
                .padding(3)
                .background(ScopeStyle.inset, in: RoundedRectangle(cornerRadius: 8))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 13) {
                    ForEach(metrics) { metric in
                        HStack(spacing: 5) {
                            Circle().fill(metric.tint).frame(width: 5, height: 5)
                            Text(metric.shortTitle)
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(ScopeStyle.secondary)
                    }
                }
            }
            .frame(height: 14, alignment: .leading)

            chart
                .frame(height: 207)
                .overlay {
                    if !hasVisibleData {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.path")
                                .font(.system(size: 23, weight: .light))
                            Text(metrics.isEmpty ? "尚未选择趋势曲线" : "等待所选传感器的数据")
                                .font(.system(size: 12))
                            Text("可在显示设置中选择曲线")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(ScopeStyle.secondary)
                        .padding(16)
                        .background(ScopeStyle.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

            HStack(spacing: 9) {
                if let point = nearestPoint {
                    Text(point.time.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(ScopeStyle.primary)
                    ForEach(metrics) { metric in
                        if let value = point.values[metric.rawValue] {
                            Text("\(metric.shortTitle) \(powerNumber(value)) W")
                                .foregroundStyle(metric.tint)
                        }
                    }
                } else {
                    Text("功率 W")
                    Spacer()
                    Text("显示最近 \(Int(model.chartWindow)) 分钟")
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(ScopeStyle.secondary)
            .lineLimit(1)
            .frame(height: 16)
        }
        .padding(22)
        .scopePanel()
    }

    private var chart: some View {
        Chart {
            ForEach(metrics) { metric in
                ForEach(graphReadings(points, metric: metric)) { reading in
                    LineMark(x: .value("时间", reading.time), y: .value("功率 W", reading.watts), series: .value("连续区间", reading.segment))
                        .foregroundStyle(metric.tint)
                        .lineStyle(StrokeStyle(lineWidth: metric == .system ? 2.3 : 1.5))
                        .interpolationMethod(.linear)
                }
            }
            if let point = nearestPoint {
                RuleMark(x: .value("选中时间", point.time))
                    .foregroundStyle(ScopeStyle.primary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                ForEach(metrics) { metric in
                    if let value = point.values[metric.rawValue] {
                        PointMark(x: .value("时间", point.time), y: .value("功率 W", value))
                            .foregroundStyle(metric.tint)
                            .symbolSize(30)
                    }
                }
            }
        }
        .chartXScale(domain: startDate...endDate)
        .chartYScale(domain: .automatic(includesZero: true))
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(ScopeStyle.line.opacity(0.5))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(ScopeStyle.secondary)
                    .font(.system(size: 9, design: .monospaced))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                    .foregroundStyle(ScopeStyle.line)
                AxisValueLabel()
                    .foregroundStyle(ScopeStyle.secondary)
                    .font(.system(size: 9, design: .monospaced))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let plot = geometry[plotFrame]
                            if plot.contains(location) {
                                selectedDate = proxy.value(atX: location.x - plot.minX, as: Date.self)
                            } else {
                                selectedDate = nil
                            }
                        case .ended:
                            selectedDate = nil
                        }
                    }
            }
        }
    }
}

private struct EnergyCard: View {
    @ObservedObject var model: PowerModel
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("累计用电").font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "bolt.circle")
                    .foregroundStyle(ScopeStyle.teal)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", model.totals.systemWh))
                        .font(.system(size: 36, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text("Wh")
                        .font(.system(size: 14))
                        .foregroundStyle(ScopeStyle.secondary)
                }
                Text("整机消耗 · 由有效功率样本积分")
                    .font(.system(size: 10))
                    .foregroundStyle(ScopeStyle.secondary)
            }
            VStack(spacing: 12) {
                energyRow("充电器输入", value: model.totals.adapterWh, color: ScopeStyle.blue)
                energyRow("电池放电", value: model.totals.batteryDischargeWh, color: ScopeStyle.amber)
                energyRow("充入电池", value: model.totals.batteryChargeWh, color: ScopeStyle.teal)
            }
            Rectangle().fill(ScopeStyle.line).frame(height: 1)
            HStack {
                Text("有效监测时长")
                Spacer()
                Text(durationText(model.totals.observedSeconds))
                    .monospacedDigit()
                    .foregroundStyle(ScopeStyle.primary.opacity(0.8))
            }
            .font(.system(size: 10))
            .foregroundStyle(ScopeStyle.secondary)
            HStack(spacing: 8) {
                Button { model.exportCSV() } label: {
                    Label("导出 CSV", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScopeButtonStyle())
                Button { confirmingReset = true } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(ScopeButtonStyle())
                .help("从现在开始重新累计用电")
                .accessibilityLabel("重置累计用电")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scopePanel()
        .confirmationDialog("重新累计用电？", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("重新累计", role: .destructive) { model.resetEnergy() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清零累计用电和有效监测时长，并从现在重新计数。历史功率曲线会保留。")
        }
    }

    private func energyRow(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(label).foregroundStyle(ScopeStyle.secondary)
            Spacer()
            Text(String(format: "%.2f", value))
                .foregroundStyle(ScopeStyle.primary.opacity(0.85))
                .monospacedDigit()
            Text("Wh").foregroundStyle(ScopeStyle.secondary)
        }
        .font(.system(size: 11))
    }
}

private struct CustomizationSheet: View {
    @ObservedObject var model: PowerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("你的功率面板")
                        .font(.system(size: 24, weight: .semibold))
                    Text("选择你关心的读数，设置会自动保存在本机。")
                        .font(.system(size: 12))
                        .foregroundStyle(ScopeStyle.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(ScopeButtonStyle())
                .accessibilityLabel("关闭显示设置")
            }
            .padding(26)

            Divider().overlay(ScopeStyle.line)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    settingsGroup("显示区域", caption: "按你的工作方式组织面板") {
                        HStack(spacing: 28) {
                            Toggle("电源流向", isOn: $model.showFlow)
                            Toggle("功率趋势", isOn: $model.showChart)
                            Toggle("累计用电", isOn: $model.showEnergy)
                        }
                        .toggleStyle(.checkbox)
                    }

                    settingsGroup("传感器与曲线", caption: "读数卡片与趋势曲线可以分别显示或隐藏") {
                        VStack(spacing: 0) {
                            HStack {
                                Text("传感器").frame(maxWidth: .infinity, alignment: .leading)
                                Text("读数卡片").frame(width: 74)
                                Text("趋势曲线").frame(width: 74)
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ScopeStyle.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            ForEach(MetricID.allCases) { metric in
                                Rectangle().fill(ScopeStyle.line).frame(height: 1)
                                HStack(spacing: 10) {
                                    Image(systemName: metric.symbol)
                                        .foregroundStyle(metric.tint)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(metric.title)
                                            .font(.system(size: 12, weight: .medium))
                                        if model.value(metric) == nil {
                                            Text("当前不可用")
                                                .font(.system(size: 10))
                                                .foregroundStyle(ScopeStyle.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Toggle("显示 \(metric.title) 卡片", isOn: metricBinding(metric, chart: false))
                                        .labelsHidden()
                                        .frame(width: 74)
                                    Toggle("显示 \(metric.title) 曲线", isOn: metricBinding(metric, chart: true))
                                        .labelsHidden()
                                        .frame(width: 74)
                                }
                                .toggleStyle(.checkbox)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .help(model.detail(metric))
                            }
                        }
                        .background(ScopeStyle.inset, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ScopeStyle.line, lineWidth: 1))
                    }

                    settingsGroup("采样与菜单栏", caption: "更高的读取频率不会加快硬件传感器自身的更新") {
                        HStack(spacing: 32) {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("读取间隔")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ScopeStyle.secondary)
                                Picker("读取间隔", selection: $model.refreshInterval) {
                                    ForEach(PowerModel.samplingIntervals, id: \.self) { seconds in
                                        Text("\(Int(seconds)) 秒").tag(seconds)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 9) {
                                Text("菜单栏显示")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ScopeStyle.secondary)
                                Picker("菜单栏显示", selection: $model.menuMetric) {
                                    ForEach(MetricID.allCases) { metric in
                                        Text(metric == .system ? "仅整机功率" : "整机 + \(metric.title)").tag(metric)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text("不可用的读数显示为「—」。不会通过整机减去芯片功率来推算屏幕功率，也不会用零代替缺失数据。")
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeStyle.secondary)
                        .lineSpacing(4)
                }
                .padding(26)
            }
            Divider().overlay(ScopeStyle.line)
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(ScopeStyle.teal)
                Text("更改立即生效")
                    .foregroundStyle(ScopeStyle.secondary)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(ScopeButtonStyle(emphasized: true))
                    .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 26)
            .padding(.vertical, 17)
        }
        .frame(width: 630, height: 740)
        .background(ScopeStyle.canvas)
        .foregroundStyle(ScopeStyle.primary)
        .preferredColorScheme(.dark)
    }

    private func metricBinding(_ metric: MetricID, chart: Bool) -> Binding<Bool> {
        Binding(
            get: { chart ? model.chartMetrics.contains(metric) : model.visibleMetrics.contains(metric) },
            set: { enabled in
                if chart {
                    if enabled { model.chartMetrics.insert(metric) } else { model.chartMetrics.remove(metric) }
                } else {
                    if enabled { model.visibleMetrics.insert(metric) } else { model.visibleMetrics.remove(metric) }
                }
            }
        )
    }

    private func settingsGroup<Content: View>(_ title: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(caption).font(.system(size: 10)).foregroundStyle(ScopeStyle.secondary)
            }
            content()
                .font(.system(size: 12))
        }
    }
}

private struct ScopeButtonStyle: ButtonStyle {
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(emphasized ? ScopeStyle.canvas : ScopeStyle.primary.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(emphasized ? ScopeStyle.teal : Color.white.opacity(configuration.isPressed ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(emphasized ? Color.clear : ScopeStyle.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private extension View {
    func scopePanel(cornerRadius: CGFloat = 18) -> some View {
        background(ScopeStyle.panel, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(ScopeStyle.line, lineWidth: 1))
    }
}

private func powerNumber(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    if value == 0 { return "0.0" }
    if abs(value) < 0.01 { return String(format: "%.3f", value) }
    if abs(value) < 1 { return String(format: "%.2f", value) }
    return String(format: "%.1f", value)
}

private func durationText(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let remaining = total % 60
    return hours > 0 ? "\(hours) 时 \(minutes) 分" : "\(minutes) 分 \(remaining) 秒"
}

private struct GraphReading: Identifiable {
    let id: UUID
    let time: Date
    let watts: Double
    let segment: String
}

/// A missing sensor reading or interrupted capture must leave a visible gap.
private func graphReadings(_ points: [PowerPoint], metric: MetricID) -> [GraphReading] {
    var readings: [GraphReading] = []
    var segmentIndex = 0
    var previous: Date?
    for point in points {
        guard let watts = point.values[metric.rawValue], watts.isFinite else {
            previous = nil
            segmentIndex += 1
            continue
        }
        if let previous, point.time.timeIntervalSince(previous) > 30 {
            segmentIndex += 1
        }
        readings.append(GraphReading(id: point.id, time: point.time, watts: watts, segment: "\(metric.rawValue)-\(segmentIndex)"))
        previous = point.time
    }
    return readings
}
