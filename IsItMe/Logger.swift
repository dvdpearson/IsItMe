import Foundation
import os.log
import AppKit

class Logger {
    static let shared = Logger()

    private let osLog = OSLog(subsystem: "com.dpearson.IsItMe", category: "general")
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.dpearson.IsItMe.logging", qos: .utility)
    private let dateFormatter: DateFormatter

    private init() {
        // Set up file logging in ~/Library/Logs/IsItMe/
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
            .appendingPathComponent("IsItMe")

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Create log file with timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
        fileURL = logsDir.appendingPathComponent("isitme-\(timestamp).log")

        // Set up date formatter for log entries
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Log startup
        info("=== IsItMe Started ===")
        info("Log file: \(fileURL.path)")
        info("Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        info("OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    // MARK: - Public Logging Methods

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .default, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }

    func fault(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .fault, file: file, function: function, line: line)
    }

    // MARK: - Memory Logging

    func logMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            self.info("Memory usage: \(String(format: "%.2f", usedMB)) MB")
        } else {
            self.warning("Failed to get memory info: \(kerr)")
        }
    }

    // MARK: - Crash Handler

    func setupCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let crashInfo = """

            ============ UNCAUGHT EXCEPTION ============
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "Unknown")
            User Info: \(exception.userInfo ?? [:])
            Call Stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            ============================================

            """
            Logger.shared.fault(crashInfo)

            // Force flush to disk
            Logger.shared.flush()
        }

        // Also capture signals
        signal(SIGABRT) { signal in
            Logger.shared.fault("Received SIGABRT (signal \(signal))")
            Logger.shared.flush()
        }

        signal(SIGSEGV) { signal in
            Logger.shared.fault("Received SIGSEGV (signal \(signal)) - Segmentation Fault")
            Logger.shared.flush()
        }

        signal(SIGBUS) { signal in
            Logger.shared.fault("Received SIGBUS (signal \(signal)) - Bus Error")
            Logger.shared.flush()
        }

        signal(SIGILL) { signal in
            Logger.shared.fault("Received SIGILL (signal \(signal)) - Illegal Instruction")
            Logger.shared.flush()
        }

        info("Crash handlers installed")
    }

    // MARK: - Internal Logging

    private func log(_ message: String, level: OSLogType, file: String, function: String, line: Int) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        let levelStr = levelString(for: level)

        // Log to OSLog
        os_log("%{public}@", log: osLog, type: level, message)

        // Log to file
        let logEntry = "[\(timestamp)] [\(levelStr)] [\(fileName):\(line) \(function)] \(message)\n"

        queue.async { [weak self] in
            guard let self = self else { return }

            if let data = logEntry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: self.fileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: self.fileURL)
                }
            }
        }
    }

    private func levelString(for level: OSLogType) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .default: return "WARN"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        default: return "LOG"
        }
    }

    func flush() {
        queue.sync {
            // Ensure all pending writes complete
        }
    }

    // MARK: - Log File Management

    func getLogFileURL() -> URL {
        return fileURL
    }

    func openLogFile() {
        NSWorkspace.shared.open(fileURL)
    }

    func revealLogFile() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func cleanOldLogs(olderThanDays days: Int = 7) {
        let logsDir = fileURL.deletingLastPathComponent()

        guard let files = try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 60 * 60))

        for file in files {
            guard file.pathExtension == "log" else { continue }

            if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < cutoffDate {
                try? FileManager.default.removeItem(at: file)
                info("Cleaned old log file: \(file.lastPathComponent)")
            }
        }
    }
}

// MARK: - Convenience Global Functions

func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.debug(message, file: file, function: function, line: line)
}

func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.info(message, file: file, function: function, line: line)
}

func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.warning(message, file: file, function: function, line: line)
}

func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.error(message, file: file, function: function, line: line)
}

func logFault(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.fault(message, file: file, function: function, line: line)
}
