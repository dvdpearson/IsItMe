import Foundation

class PingService {
    static func ping(host: String = "google.com") -> Double? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "1000", host]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }

            return parseLatency(from: output)
        } catch {
            return nil
        }
    }

    private static func parseLatency(from output: String) -> Double? {
        let pattern = "time=([0-9.]+) ms"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range) else {
            return nil
        }

        guard let latencyRange = Range(match.range(at: 1), in: output) else {
            return nil
        }

        let latencyString = String(output[latencyRange])
        return Double(latencyString)
    }
}
