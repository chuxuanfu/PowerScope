import Foundation

// Run from the PowerScope directory:
// swiftc -module-cache-path /tmp/PowerScopeSwiftModuleCache \
//   Sources/EnergyAccounting.swift Tests/EnergyAccountingTests.swift \
//   -o /tmp/PowerScopeEnergyTests && /tmp/PowerScopeEnergyTests
@main
enum EnergyAccountingTests {
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private static var assertions = 0

    static func main() throws {
        testOneHour()
        testBatteryCrossings()
        testDuplicateAndBackwardTimestamps()
        testGapsAndBoundaries()
        testMissingAndInvalidValues()
        testReset()
        try testPersistence()
        print("EnergyAccounting: \(assertions) assertions passed.")
    }

    private static func feed(_ ledger: EnergyLedger, _ seconds: Double,
                             system: Double? = 10, adapter: Double? = nil,
                             battery: Double? = nil) {
        ledger.ingest(time: epoch.addingTimeInterval(seconds),
                      system: system, adapter: adapter, battery: battery)
    }

    private static func equal(_ actual: Double, _ expected: Double, _ context: String,
                              tolerance: Double = 1e-10) {
        assertions += 1
        precondition(abs(actual - expected) <= tolerance,
                     "\(context): expected \(expected), got \(actual)")
    }

    private static func testOneHour() {
        let ledger = EnergyLedger()
        for seconds in stride(from: 0, through: 3600, by: 20) {
            feed(ledger, Double(seconds), adapter: 12, battery: 2)
        }
        equal(ledger.totals.systemWh, 10, "10 W for one measured hour")
        equal(ledger.totals.adapterWh, 12, "adapter one-hour energy")
        equal(ledger.totals.batteryChargeWh, 2, "charging one-hour energy")
        equal(ledger.totals.batteryDischargeWh, 0, "no discharge")
        equal(ledger.totals.observedSeconds, 3600, "union coverage counted once")
        equal(ledger.totals.systemObservedSeconds, 3600, "system coverage")
        equal(ledger.totals.adapterObservedSeconds, 3600, "adapter coverage")
        equal(ledger.totals.batteryObservedSeconds, 3600, "battery coverage")
    }

    private static func testBatteryCrossings() {
        let forward = EnergyLedger()
        feed(forward, 0, system: nil, battery: -4)
        feed(forward, 20, system: nil, battery: 12)
        // Crosses zero at 5 s: 10 W.s discharge and 90 W.s charge.
        equal(forward.totals.batteryDischargeWh, 10 / 3600, "negative to positive discharge")
        equal(forward.totals.batteryChargeWh, 90 / 3600, "negative to positive charge")
        equal(forward.totals.batteryChargeWh - forward.totals.batteryDischargeWh,
              80 / 3600, "signed integral conserved")

        let reverse = EnergyLedger()
        feed(reverse, 0, system: nil, battery: 12)
        feed(reverse, 20, system: nil, battery: -4)
        equal(reverse.totals.batteryDischargeWh, 10 / 3600, "positive to negative discharge")
        equal(reverse.totals.batteryChargeWh, 90 / 3600, "positive to negative charge")

        let zeros = EnergyLedger()
        feed(zeros, 0, system: nil, battery: -10)
        feed(zeros, 10, system: nil, battery: 0)
        feed(zeros, 20, system: nil, battery: 10)
        feed(zeros, 30, system: nil, battery: 0)
        equal(zeros.totals.batteryDischargeWh, 50 / 3600, "zero endpoint discharge")
        equal(zeros.totals.batteryChargeWh, 100 / 3600, "zero endpoint charge")
    }

    private static func testDuplicateAndBackwardTimestamps() {
        let ledger = EnergyLedger()
        feed(ledger, 0)
        feed(ledger, 10)
        feed(ledger, 10, system: 1000)
        feed(ledger, 5, system: 1000)
        feed(ledger, 20)
        equal(ledger.totals.systemWh, 200 / 3600, "duplicate/backward samples ignored")
        equal(ledger.totals.observedSeconds, 20, "duplicate/backward coverage ignored")
    }

    private static func testGapsAndBoundaries() {
        let ledger = EnergyLedger()
        feed(ledger, 0)
        feed(ledger, 30)
        feed(ledger, 61) // 31 s exceeds the default limit.
        feed(ledger, 71)
        ledger.breakContinuity() // Pause/sleep must not span even a short gap.
        feed(ledger, 72)
        feed(ledger, 82)
        equal(ledger.totals.systemWh, 500 / 3600, "gap and explicit boundary excluded")
        equal(ledger.totals.observedSeconds, 50, "coverage excludes pause and outage")

        let shortGap = EnergyLedger(maxGapSeconds: 5)
        feed(shortGap, 0)
        feed(shortGap, 6)
        feed(shortGap, 11)
        equal(shortGap.totals.observedSeconds, 5, "custom gap threshold")
    }

    private static func testMissingAndInvalidValues() {
        let ledger = EnergyLedger()
        feed(ledger, 0, adapter: 20, battery: -3)
        feed(ledger, 10, system: nil, adapter: 20, battery: -3)
        feed(ledger, 20, adapter: 20, battery: nil)
        feed(ledger, 30, adapter: nil, battery: -3)
        feed(ledger, 40, adapter: 20, battery: -3)
        equal(ledger.totals.systemWh, 200 / 3600, "no system interpolation across missing data")
        equal(ledger.totals.adapterWh, 400 / 3600, "no adapter interpolation across missing data")
        equal(ledger.totals.batteryDischargeWh, 60 / 3600, "no battery interpolation across missing data")
        equal(ledger.totals.systemObservedSeconds, 20, "partial system coverage")
        equal(ledger.totals.adapterObservedSeconds, 20, "partial adapter coverage")
        equal(ledger.totals.batteryObservedSeconds, 20, "partial battery coverage")
        equal(ledger.totals.observedSeconds, 40, "coverage is union, not sum")

        feed(ledger, 50, system: .nan, adapter: -.infinity, battery: .infinity)
        feed(ledger, 60, system: -1, adapter: -1, battery: nil)
        feed(ledger, 70, system: nil)
        feed(ledger, 80)
        feed(ledger, 90)
        equal(ledger.totals.systemWh, 300 / 3600, "invalid powers unavailable")
        equal(ledger.totals.observedSeconds, 50, "all-missing intervals excluded")
    }

    private static func testReset() {
        let ledger = EnergyLedger()
        feed(ledger, 0, adapter: 15, battery: 5)
        feed(ledger, 10, adapter: 15, battery: 5)
        let resetTime = epoch.addingTimeInterval(15)
        ledger.reset(at: resetTime)
        equal(ledger.totals.systemWh, 0, "reset system")
        equal(ledger.totals.adapterWh, 0, "reset adapter")
        equal(ledger.totals.batteryChargeWh, 0, "reset charging")
        equal(ledger.totals.observedSeconds, 0, "reset coverage")
        equal(ledger.totals.startedAt.timeIntervalSince1970,
              resetTime.timeIntervalSince1970, "reset start date")
        feed(ledger, 20)
        equal(ledger.totals.systemWh, 0, "reset clears previous anchor")
        feed(ledger, 30)
        equal(ledger.totals.systemWh, 100 / 3600, "new accounting period")
    }

    private static func testPersistence() throws {
        let ledger = EnergyLedger(totals: EnergyTotals(startedAt: epoch))
        feed(ledger, 0, adapter: 9, battery: -1)
        feed(ledger, 10, adapter: 9, battery: -1)
        let encoded = try JSONEncoder().encode(ledger.totals)
        let decoded = try JSONDecoder().decode(EnergyTotals.self, from: encoded)
        assertions += 1
        precondition(decoded == ledger.totals, "Codable round trip preserves every total")
        let restored = EnergyLedger(totals: decoded)
        feed(restored, 20, adapter: 9, battery: -1)
        equal(restored.totals.observedSeconds, 10, "restore does not bridge app downtime")
        feed(restored, 30, adapter: 9, battery: -1)
        equal(restored.totals.systemWh, 200 / 3600, "restore continues saved energy")
        equal(restored.totals.observedSeconds, 20, "restore continues measured coverage")
    }
}
