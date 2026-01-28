import Foundation

class PingService {
    private static let processTimeout: TimeInterval = 3.0 // 3 second hard timeout
    private static var activeProcesses = 0
    private static let processLock = NSLock()

    static func ping(host: String = "google.com") -> Double? {
        let startTime = Date()
        logDebug("Starting ping to \(host)")

        processLock.lock()
        activeProcesses += 1
        let currentActive = activeProcesses
        processLock.unlock()

        if currentActive > 3 {
            logWarning("High number of active ping processes: \(currentActive)")
        }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "1000", host]
        process.standardOutput = pipe
        process.standardError = pipe

        var result: Double? = nil
        var accumulatedOutput = Data()
        let semaphore = DispatchSemaphore(value: 0)

        do {
            // Set up termination handler to collect output after process completes
            process.terminationHandler = { proc in
                semaphore.signal()
            }

            try process.run()
            let pid = process.processIdentifier
            logDebug("Ping process started with PID: \(pid)")

            // Read output asynchronously in chunks to prevent pipe buffer from filling
            let fileHandle = pipe.fileHandleForReading
            DispatchQueue.global(qos: .utility).async {
                while process.isRunning {
                    if let data = try? fileHandle.read(upToCount: 4096), !data.isEmpty {
                        accumulatedOutput.append(data)
                    } else {
                        usleep(10000) // 10ms delay if no data
                    }
                }
                // Read any remaining data
                if let remainingData = try? fileHandle.readToEnd() {
                    accumulatedOutput.append(remainingData)
                }
            }

            // Wait with timeout
            let timeoutResult = semaphore.wait(timeout: .now() + processTimeout)

            if timeoutResult == .timedOut {
                logError("Ping process timed out after \(processTimeout)s, terminating PID: \(pid)")
                process.terminationHandler = nil
                process.terminate()

                // Give it a moment to clean up, then force kill if needed
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    if process.isRunning {
                        logError("Force killing hung ping process PID: \(pid)")
                        kill(pid, SIGKILL)
                    }
                }
            } else {
                let exitCode = process.terminationStatus
                let exitReason = process.terminationReason

                if exitCode != 0 {
                    logWarning("Ping process exited with code \(exitCode), reason: \(exitReason.rawValue)")
                }

                // Give the reader thread a moment to finish
                usleep(50000) // 50ms

                guard let output = String(data: accumulatedOutput, encoding: .utf8) else {
                    logError("Failed to decode ping output as UTF-8")
                    processLock.lock()
                    activeProcesses -= 1
                    processLock.unlock()
                    return nil
                }

                logDebug("Ping output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                result = parseLatency(from: output)

                if let latency = result {
                    let elapsed = Date().timeIntervalSince(startTime)
                    logInfo("Ping to \(host) succeeded: \(String(format: "%.2f", latency))ms (total time: \(String(format: "%.2f", elapsed * 1000))ms)")
                } else {
                    logWarning("Ping completed but failed to parse latency from output")
                }
            }
        } catch {
            logError("Failed to start ping process: \(error.localizedDescription)")
        }

        processLock.lock()
        activeProcesses -= 1
        processLock.unlock()

        return result
    }

    private static func parseLatency(from output: String) -> Double? {
        let pattern = "time=([0-9.]+) ms"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            logError("Failed to create regex for latency parsing")
            return nil
        }

        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range) else {
            logDebug("No latency match found in output")
            return nil
        }

        guard let latencyRange = Range(match.range(at: 1), in: output) else {
            logError("Failed to convert match range to Swift Range")
            return nil
        }

        let latencyString = String(output[latencyRange])
        guard let latency = Double(latencyString) else {
            logError("Failed to parse latency string '\(latencyString)' as Double")
            return nil
        }

        return latency
    }
}
