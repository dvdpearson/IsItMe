import Foundation

class LatencyStats {
    private var latencies: [Double] = []
    private(set) var current: Double?
    private(set) var average: Double?
    private(set) var minimum: Double?
    private(set) var maximum: Double?

    func update(latency: Double?) {
        current = latency

        guard let latency = latency else {
            return
        }

        latencies.append(latency)

        if minimum == nil || latency < minimum! {
            minimum = latency
        }

        if maximum == nil || latency > maximum! {
            maximum = latency
        }

        average = latencies.reduce(0.0, +) / Double(latencies.count)
    }

    func reset() {
        latencies.removeAll()
        current = nil
        average = nil
        minimum = nil
        maximum = nil
    }
}
