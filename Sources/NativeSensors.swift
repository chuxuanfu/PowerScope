import Foundation
import IOKit
import Darwin

struct SensorReading: Sendable {
    var key: String
    var name: String
    var watts: Double
    var source: String
}

struct NativeSnapshot: Sendable {
    var timestamp: Date
    var smcSystemWatts: Double?
    var telemetrySystemWatts: Double?
    var adapterWatts: Double?
    /// Positive means charging; negative means discharging.
    var batteryWatts: Double?
    var batteryPercent: Double?
    var externalConnected: Bool
    var isCharging: Bool
    var sensorReadings: [SensorReading]
    var notes: [String]
    /// Firmware update counter, NOT an energy counter. Used only for freshness.
    var firmwareCounter: UInt64?
}

/// All hardware calls are read-only, in-process, and need no root/helper process.
/// Private interfaces vary across models and OS versions: absence stays absent.
final class NativeSensors: @unchecked Sendable {
    private let lock = NSLock()
    private let smc = ReadOnlySMC()
    private let energy = EnergyModelReader()

    func read() -> NativeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        let battery = batteryProperties()
        let telemetry = battery?["PowerTelemetryData"] as? [String: Any]
        let external = (battery?["ExternalConnected"] as? NSNumber)?.boolValue ?? false
        let charging = (battery?["IsCharging"] as? NSNumber)?.boolValue ?? false
        let telemetrySystem = milliwatts(telemetry?["SystemLoad"])
        let smcSystem = smc?.power("PSTR").flatMap { $0 > 0 ? $0 : nil }
        let adapter = milliwatts(telemetry?["SystemPowerIn"])
        var batteryPower = milliwatts(telemetry?["BatteryPower"], signed: true)
        var notes = [String]()
        if battery == nil { notes.append("未能读取 AppleSmartBattery；此设备可能没有电池或不开放此接口。") }
        if smcSystem == nil && telemetrySystem == nil { notes.append("当前未取得有效的整机功率读数。") }
        if batteryPower == nil, let voltage = number(battery?["Voltage"]),
           let current = signedNumber(battery?["InstantAmperage"] ?? battery?["Amperage"]),
           voltage > 0, voltage < 100_000 {
            let value = voltage * current / 1_000_000
            if value.isFinite, abs(value) < 1_000 { batteryPower = value }
        }
        var percent: Double?
        if let current = number(battery?["CurrentCapacity"]), let maximum = number(battery?["MaxCapacity"]), maximum > 0 {
            let value = current / maximum * 100
            if value.isFinite, (0...100).contains(value) { percent = value }
        }
        var readings = [SensorReading]()
        if let value = smc?.power("PDTR") {
            readings.append(SensorReading(key: "smc_adapter", name: "输入 SMC 传感器", watts: value,
                                          source: "AppleSMC PDTR · W；Mac 侧直流输入，非插座功率"))
        }
        // PDBR/PBwo are backlight-related rails, not all display electronics.
        if let value = smc?.power("PDBR") {
            readings.append(SensorReading(key: "display", name: "背光通道 · 不代表完整屏幕功率", watts: value,
                                          source: "AppleSMC PDBR · W；背光相关电源轨，不代表整块屏幕功耗"))
        } else if let value = smc?.power("PBwo") {
            readings.append(SensorReading(key: "display", name: "背光通道 · 不代表完整屏幕功率", watts: value,
                                          source: "AppleSMC PBwo · W；背光电源轨，不代表整块屏幕功耗"))
        }
        // Asahi macsmc-hwmon explicitly describes PHPC as a derived estimate of
        // heat dissipated by the SoC. It is NOT a measured electrical rail.
        // https://github.com/AsahiLinux/linux/blob/asahi/drivers/hwmon/macsmc-hwmon.c
        if let value = smc?.power("PHPC") {
            readings.append(SensorReading(key: "chip", name: "SoC 热功率模型 · 非电源轨实测", watts: value,
                                          source: "SMC PHPC · 热功率估算；不能与 CPU/GPU 或整机电功率相加"))
        }
        if let value = smc?.power("PHPS") {
            readings.append(SensorReading(key: "smc_PHPS", name: "SMC PHPS（范围未确认）", watts: value,
                                          source: "AppleSMC PHPS · 原始功率通道，未验证组件归属；不参与合计"))
        }
        if let energy {
            let result = energy.read()
            readings.append(contentsOf: result.readings.filter { $0.key != "chip" || !readings.contains(where: { $0.key == "chip" }) })
            notes.append(contentsOf: result.notes)
        } else {
            notes.append("IOReport 能量接口不可用；CPU、GPU、ANE 分项不会伪装为零。")
        }
        if smc == nil { notes.append("SMC 只读连接不可用，未提供背光及其他 SMC 读数。") }
        return NativeSnapshot(timestamp: now, smcSystemWatts: smcSystem, telemetrySystemWatts: telemetrySystem, adapterWatts: adapter,
                              batteryWatts: batteryPower, batteryPercent: percent,
                              externalConnected: external, isCharging: charging,
                              sensorReadings: readings, notes: notes,
                              firmwareCounter: (telemetry?["SystemLoadAccumulatorCount"] as? NSNumber)?.uint64Value)
    }

    private func batteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() else { return nil }
        return dictionary as NSDictionary as? [String: Any]
    }

    private func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
    private func signedNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        // CF/NSNumber can expose negative 64-bit firmware values as unsigned.
        return Double(Int64(bitPattern: number.uint64Value))
    }
    private func milliwatts(_ value: Any?, signed: Bool = false) -> Double? {
        guard let raw = signed ? signedNumber(value) : number(value) else { return nil }
        let watts = raw / 1_000
        guard watts.isFinite, abs(watts) < 1_000, signed || watts >= 0 else { return nil }
        return watts
    }
}

/// AppleSMC's 80-byte user-client ABI. Only operations 9 (key info) and 5 (read)
/// are implemented; no write opcode is present. Metadata is cached, not values.
/// ABI reference: github.com/lavoiesl/osx-cpu-temp/blob/master/smc.h
/// Power-key meanings: github.com/exelban/stats/blob/master/Modules/Sensors/values.swift
private final class ReadOnlySMC {
    private var connection: io_connect_t = 0
    private var info: [String: (size: UInt32, type: String)] = [:]
    private var unavailable = Set<String>()

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }

    func power(_ key: String) -> Double? {
        guard key.utf8.count == 4, !unavailable.contains(key) else { return nil }
        var request = [UInt8](repeating: 0, count: 80)
        put(key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }, into: &request, at: 0)
        if info[key] == nil {
            request[42] = 9
            guard let response = call(request), response[40] == 0 else { unavailable.insert(key); return nil }
            let size = uint(response, at: 28)
            guard size > 0, size <= 32 else { unavailable.insert(key); return nil }
            let typeCode = uint(response, at: 32)
            let type = String(bytes: (0..<4).map { UInt8((typeCode >> ((3 - $0) * 8)) & 255) }, encoding: .ascii) ?? ""
            info[key] = (size, type)
        }
        guard let metadata = info[key] else { return nil }
        put(metadata.size, into: &request, at: 28)
        request[42] = 5
        guard let response = call(request), response[40] == 0 else { return nil }
        let value: Double
        if metadata.type == "flt ", metadata.size == 4 {
            value = Double(Float(bitPattern: uint(response, at: 48)))
        } else if metadata.type.hasPrefix("sp"), metadata.size == 2,
                  let fraction = Int(String(metadata.type.suffix(1)), radix: 16) {
            let bits = UInt16(response[48]) << 8 | UInt16(response[49])
            value = Double(Int16(bitPattern: bits)) / pow(2, Double(fraction))
        } else if metadata.type.hasPrefix("fp"), metadata.size == 2,
                  let fraction = Int(String(metadata.type.suffix(1)), radix: 16) {
            let bits = UInt16(response[48]) << 8 | UInt16(response[49])
            value = Double(bits) / pow(2, Double(fraction))
        } else { return nil }
        guard value.isFinite, (0..<1_000).contains(value) else { return nil }
        return value
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: 80)
        var outputSize = output.count
        let result = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                IOConnectCallStructMethod(connection, 2, source.baseAddress, 80, destination.baseAddress, &outputSize)
            }
        }
        guard result == KERN_SUCCESS, outputSize == 80 else { return nil }
        return output
    }
    private func put(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        for i in 0..<4 { bytes[offset + i] = UInt8((value >> (i * 8)) & 255) }
    }
    private func uint(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | (UInt32(bytes[offset + $1]) << ($1 * 8)) }
    }
}

/// Dynamically resolved IOReport ABI: a missing symbol disables this provider
/// instead of making the app fail to link or launch. Formula: Δjoules / Δseconds.
/// Interface references: Stats Sensors/readers.swift and OSHI IOReportClient.
private final class EnergyModelReader {
    private typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias Subscribe = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary?, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> UnsafeMutableRawPointer?
    private typealias Samples = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelString = @convention(c) (CFDictionary?) -> Unmanaged<CFString>?
    private typealias IntegerValue = @convention(c) (CFDictionary?, Int32) -> Int64
    private struct Counter { var raw: Int64; var scale: Double; var unit: String }

    private let library: UnsafeMutableRawPointer
    private let subscription: UnsafeMutableRawPointer
    private let channels: CFMutableDictionary
    private let samples: Samples
    private let channelName: ChannelString
    private let channelUnit: ChannelString
    private let integerValue: IntegerValue
    private var previous: [String: Counter] = [:]
    private var previousTime: TimeInterval?
    private var observedProgress = Set<String>()

    init?() {
        guard let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        func resolve<T>(_ name: String, _ type: T.Type) -> T? {
            guard let address = dlsym(library, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        guard let copy = resolve("IOReportCopyChannelsInGroup", CopyChannels.self),
              let subscribe = resolve("IOReportCreateSubscription", Subscribe.self),
              let samples = resolve("IOReportCreateSamples", Samples.self),
              let name = resolve("IOReportChannelGetChannelName", ChannelString.self),
              let unit = resolve("IOReportChannelGetUnitLabel", ChannelString.self),
              let integer = resolve("IOReportSimpleGetIntegerValue", IntegerValue.self),
              let requested = copy("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue()
        else { dlclose(library); return nil }
        var accepted: Unmanaged<CFMutableDictionary>?
        guard let subscription = subscribe(nil, requested, &accepted, 0, nil) else {
            accepted?.release(); dlclose(library); return nil
        }
        self.library = library
        self.subscription = subscription
        self.channels = accepted?.takeRetainedValue() ?? requested
        self.samples = samples
        self.channelName = name
        self.channelUnit = unit
        self.integerValue = integer
    }
    deinit {
        Unmanaged<AnyObject>.fromOpaque(subscription).release()
        // Keep the system library mapped: CF objects may release after this body.
        // dlopen's one reference is bounded to this application's lifetime.
    }

    func read() -> (readings: [SensorReading], notes: [String]) {
        guard let sample = samples(subscription, channels, nil)?.takeRetainedValue(),
              let items = (sample as NSDictionary)["IOReportChannels"] as? [NSDictionary]
        else { previous = [:]; previousTime = nil; return ([], ["IOReport 采样失败，分项功耗暂不可用。"]) }
        let now = ProcessInfo.processInfo.systemUptime
        var current: [String: Counter] = [:]
        for item in items {
            let dictionary = item as CFDictionary
            guard let name = channelName(dictionary)?.takeUnretainedValue() as String?,
                  let unit = channelUnit(dictionary)?.takeUnretainedValue() as String?,
                  let scale = Self.joulesPerUnit(unit) else { continue }
            let raw = integerValue(dictionary, 0)
            guard raw >= 0 else { continue } // Includes INT64_MIN unavailable sentinel.
            current[name] = Counter(raw: raw, scale: scale, unit: unit)
        }
        defer { previous = current; previousTime = now }
        guard let then = previousTime, now > then, now - then <= 60 else {
            observedProgress.removeAll()
            return ([], ["分项功耗正在建立能量计数器基线。"])
        }
        let seconds = now - then
        var deltas: [String: Double] = [:]
        for (name, counter) in current {
            guard let before = previous[name], counter.unit == before.unit, counter.raw >= before.raw else {
                observedProgress.remove(name); continue
            }
            let delta = counter.raw - before.raw
            if delta > 0 { observedProgress.insert(name) }
            let watts = Double(delta) * counter.scale / seconds
            if watts.isFinite, (0..<1_000).contains(watts) { deltas[name] = watts }
        }
        func matching(_ exact: String) -> [String] {
            if current[exact] != nil { return [exact] }
            return current.keys.filter { $0.hasSuffix(" " + exact) }.sorted()
        }
        func numbered(_ prefix: String) -> [String] {
            current.keys.filter { name in
                let unit = name.split(separator: " ").last.map(String.init) ?? name
                return unit.hasPrefix(prefix) && !unit.dropFirst(prefix.count).isEmpty && unit.dropFirst(prefix.count).allSatisfy(\.isNumber)
            }.sorted()
        }
        let cpuNames = matching("CPU Energy")
        let modelAdvancing = cpuNames.contains { (deltas[$0] ?? 0) > 0 }
        var result = [SensorReading]()
        func add(_ key: String, _ label: String, _ names: [String], allowIdle: Bool) {
            guard !names.isEmpty, names.allSatisfy({ deltas[$0] != nil }),
                  allowIdle || names.allSatisfy({ observedProgress.contains($0) }) else { return }
            let value = names.reduce(0) { $0 + (deltas[$1] ?? 0) }
            guard value < 1_000 else { return }
            let units = Set(names.compactMap { current[$0]?.unit }).sorted().joined(separator: "/")
            result.append(SensorReading(key: key, name: label, watts: value,
                                       source: "IOReport Energy Model · \(names.joined(separator: "+")) · Δ\(units)/Δs → W；模型估计"))
        }
        // A present but frozen CPU counter is not evidence of zero consumption.
        if modelAdvancing { add("cpu", "CPU", cpuNames, allowIdle: true) }
        let gpuNames = matching("GPU Energy")
        if modelAdvancing || gpuNames.contains(where: { (deltas[$0] ?? 0) > 0 }) {
            add("gpu", "GPU", gpuNames, allowIdle: false)
        }
        let aneNames = matching("ANE Energy").isEmpty ? numbered("ANE") : matching("ANE Energy")
        let dramNames = matching("DRAM Energy").isEmpty ? numbered("DRAM") : matching("DRAM Energy")
        if modelAdvancing {
            add("ane", "神经网络引擎", aneNames, allowIdle: true)
            add("dram", "内存能量模型", dramNames, allowIdle: true)
        }
        // Never substitute an electrical-domain sum for the separately labeled
        // SoC thermal model (PHPC). These have different physical meanings.
        let notes = modelAdvancing ? [] : ["CPU/ANE 等能量计数器未确认更新，暂不显示其瓦数；这不表示耗电为零。"]
        return (result, notes)
    }
    private static func joulesPerUnit(_ unit: String) -> Double? {
        switch unit {
        case "J": return 1
        case "mJ": return 1e-3
        case "uJ", "µJ", "μJ": return 1e-6
        case "nJ": return 1e-9
        default: return nil
        }
    }
}
