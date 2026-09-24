import Foundation

/// Cumulative energy measured only over intervals covered by valid samples.
/// Persist this value, rather than the ledger: a restored ledger starts a new
/// continuity segment and never charges unobserved time to the saved totals.
struct EnergyTotals: Codable, Equatable {
    var systemWh: Double = 0
    var adapterWh: Double = 0
    var batteryDischargeWh: Double = 0
    var batteryChargeWh: Double = 0
    var observedSeconds: Double = 0
    var systemObservedSeconds: Double = 0
    var adapterObservedSeconds: Double = 0
    var batteryObservedSeconds: Double = 0
    var startedAt: Date = Date()
}

/// Integrates watts into watt-hours using the trapezoidal rule.
///
/// All inputs are watts; battery is positive when charging and negative when
/// discharging. Missing/nonfinite values are unavailable; negative system or
/// adapter values are also unavailable. No domain is interpolated across a
/// missing endpoint. `observedSeconds` is the union of covered domain intervals.
///
/// Call on one serial executor. Supply fresh measurement timestamps, not a new
/// timestamp for an unchanged cached reading. Pass nil for stale domains, and
/// call `breakContinuity()` on pause, sleep, sensor loss, or source changes.
final class EnergyLedger {
    private(set) var totals: EnergyTotals
    let maxGapSeconds: Double

    private struct Sample {
        let time: Date
        let system: Double?
        let adapter: Double?
        let battery: Double?
    }

    private var previous: Sample?

    init(totals: EnergyTotals = EnergyTotals(), maxGapSeconds: Double = 30) {
        precondition(maxGapSeconds.isFinite && maxGapSeconds > 0,
                     "Maximum sample gap must be finite and positive")
        self.totals = totals
        self.maxGapSeconds = maxGapSeconds
    }

    func ingest(time: Date, system: Double?, adapter: Double?, battery: Double?) {
        guard time.timeIntervalSince1970.isFinite else {
            breakContinuity()
            return
        }

        let current = Sample(
            time: time,
            system: Self.validPower(system, signed: false),
            adapter: Self.validPower(adapter, signed: false),
            battery: Self.validPower(battery, signed: true)
        )

        guard let previous else {
            self.previous = current
            return
        }

        let seconds = time.timeIntervalSince(previous.time)
        // Duplicate/out-of-order observations cannot move the accepted anchor.
        guard seconds > 0 else { return }
        self.previous = current

        // The first observation after an outage establishes a fresh baseline.
        guard seconds.isFinite, seconds <= maxGapSeconds else { return }

        var covered = false
        if let start = previous.system, let end = current.system {
            totals.systemWh += Self.trapezoid(start, end, seconds: seconds)
            totals.systemObservedSeconds += seconds
            covered = true
        }
        if let start = previous.adapter, let end = current.adapter {
            totals.adapterWh += Self.trapezoid(start, end, seconds: seconds)
            totals.adapterObservedSeconds += seconds
            covered = true
        }
        if let start = previous.battery, let end = current.battery {
            integrateBattery(start: start, end: end, seconds: seconds)
            totals.batteryObservedSeconds += seconds
            covered = true
        }
        if covered {
            totals.observedSeconds += seconds
        }
    }

    /// Ends a measured segment without erasing its accumulated energy.
    func breakContinuity() {
        previous = nil
    }

    /// Begins a new accounting period; the next sample establishes its baseline.
    func reset(at time: Date = Date()) {
        totals = EnergyTotals(startedAt: time)
        breakContinuity()
    }

    private static func validPower(_ value: Double?, signed: Bool) -> Double? {
        guard let value, value.isFinite, signed || value >= 0 else { return nil }
        return value
    }

    private static func trapezoid(_ start: Double, _ end: Double, seconds: Double) -> Double {
        (start / 2 + end / 2) * (seconds / 3600)
    }

    private func integrateBattery(start: Double, end: Double, seconds: Double) {
        if start >= 0 && end >= 0 {
            totals.batteryChargeWh += Self.trapezoid(start, end, seconds: seconds)
        } else if start <= 0 && end <= 0 {
            totals.batteryDischargeWh += Self.trapezoid(-start, -end, seconds: seconds)
        } else {
            // Linear interpolation crosses zero. Integrate the two triangles
            // separately so opposite flows neither cancel nor count twice.
            let startMagnitude = abs(start)
            let endMagnitude = abs(end)
            let scale = max(startMagnitude, endMagnitude)
            let firstFraction = (startMagnitude / scale)
                / (startMagnitude / scale + endMagnitude / scale)
            let firstSeconds = seconds * firstFraction
            let firstWh = Self.trapezoid(startMagnitude, 0, seconds: firstSeconds)
            let secondWh = Self.trapezoid(0, endMagnitude, seconds: seconds - firstSeconds)
            if start > 0 {
                totals.batteryChargeWh += firstWh
                totals.batteryDischargeWh += secondWh
            } else {
                totals.batteryDischargeWh += firstWh
                totals.batteryChargeWh += secondWh
            }
        }
    }
}
