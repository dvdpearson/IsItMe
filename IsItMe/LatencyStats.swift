import Foundation

class LatencyStats {
    private var latencies: [Double] = []
    private(set) var current: Double?
    private(set) var average: Double?
    private(set) var minimum: Double?
    private(set) var maximum: Double?
    private var lastMemoryWarning: Date?

    func update(latency: Double?) {
        current = latency

        guard let latency = latency else {
            return
        }

        latencies.append(latency)

        // Log memory warning if array grows too large
        if latencies.count % 10000 == 0 {
            let shouldLog = lastMemoryWarning == nil || Date().timeIntervalSince(lastMemoryWarning!) > 60
            if shouldLog {
                logWarning("LatencyStats array has grown to \(latencies.count) entries")
                lastMemoryWarning = Date()
            }
        }

        if minimum == nil || latency < minimum! {
            minimum = latency
        }

        if maximum == nil || latency > maximum! {
            maximum = latency
        }

        average = latencies.reduce(0.0, +) / Double(latencies.count)
    }

    func reset() {
        logInfo("Resetting latency stats (was \(latencies.count) entries)")
        latencies.removeAll()
        current = nil
        average = nil
        minimum = nil
        maximum = nil
    }

    func getLatencyCount() -> Int {
        return latencies.count
    }
}
