import CocoaLumberjack

/// Logger manager using CocoaLumberjack with Console + File output
enum LoggerManager {
    private static var fileLogger: DDFileLogger?

    /// Log levels
    enum Level {
        case debug, info, warn, error
    }

    /// Setup logger with Console + File output
    static func setup() {
        guard fileLogger == nil else { return }

        // Console logger
        let consoleLogger = DDOSLogger.sharedInstance
        DDLog.add(consoleLogger)

        // File logger with rotation
        let fileLogger = DDFileLogger(logFileManager: DDLogFileManagerDefault())
        fileLogger.maximumFileSize = 1024 * 1024 // 1MB
        fileLogger.logFileManager.maximumNumberOfLogFiles = 7 // 7 days retention
        DDLog.add(fileLogger)
        self.fileLogger = fileLogger

        // Set log level based on build configuration
        #if DEBUG
            dynamicLogLevel = .debug
        #else
            dynamicLogLevel = .info
        #endif

        DDLogInfo("LoggerManager initialized")
    }

    /// Flushes pending messages and returns retained log files, newest first.
    static func logFileURLs() -> [URL] {
        DDLog.flushLog()
        return fileLogger?.logFileManager.sortedLogFilePaths
            .reversed()
            .map(URL.init(fileURLWithPath:)) ?? []
    }

    /// Redact sensitive strings (API keys, long alphanumeric strings)
    static func redact(_ message: String) -> String {
        let patterns = [
            (#"(?i)(authorization\s*[:=]\s*(?:bearer\s+)?)[^\s,;]+"#, "$1[REDACTED]"),
            (#"(?i)(\bbearer\s+)[^\s,;]+"#, "$1[REDACTED]"),
            (#"(?i)((?:api[-_ ]?key|x-api-key)\s*[:=]\s*)[^\s,;]+"#, "$1[REDACTED]"),
            (#"(?i)([?&](?:api_key|key|token)=)[^&\s]+"#, "$1[REDACTED]"),
            (#"[a-zA-Z0-9]{20,}"#, "[REDACTED]")
        ]

        return patterns.reduce(message) { result, rule in
            guard let regex = try? NSRegularExpression(pattern: rule.0) else { return result }
            let range = NSRange(result.startIndex..., in: result)
            return regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.1)
        }
    }
}

/// Global logging convenience methods
enum Log {
    /// Debug level logging (only in DEBUG builds)
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let redacted = LoggerManager.redact(message)
        let fileName = (file as NSString).lastPathComponent
        DDLogVerbose("[\(fileName):\(line)] \(function): \(redacted)", level: dynamicLogLevel)
    }

    /// Info level logging
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let redacted = LoggerManager.redact(message)
        let fileName = (file as NSString).lastPathComponent
        DDLogInfo("[\(fileName):\(line)] \(function): \(redacted)", level: dynamicLogLevel)
    }

    /// Warning level logging
    static func warn(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let redacted = LoggerManager.redact(message)
        let fileName = (file as NSString).lastPathComponent
        DDLogWarn("[\(fileName):\(line)] \(function): \(redacted)", level: dynamicLogLevel)
    }

    /// Error level logging
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let redacted = LoggerManager.redact(message)
        let fileName = (file as NSString).lastPathComponent
        DDLogError("[\(fileName):\(line)] \(function): \(redacted)", level: dynamicLogLevel)
    }
}
