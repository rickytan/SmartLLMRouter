import CocoaLumberjack

/// Logger manager using CocoaLumberjack with Console + File output
enum LoggerManager {
    /// Log levels
    enum Level {
        case debug, info, warn, error
    }

    /// Setup logger with Console + File output
    static func setup() {
        // Console logger
        let consoleLogger = DDOSLogger.sharedInstance
        DDLog.add(consoleLogger)

        // File logger with rotation
        let fileLogger = DDFileLogger(logFileManager: DDLogFileManagerDefault())
        fileLogger.maximumFileSize = 1024 * 1024 // 1MB
        fileLogger.logFileManager.maximumNumberOfLogFiles = 7 // 7 days retention
        DDLog.add(fileLogger)

        // Set log level based on build configuration
        #if DEBUG
            dynamicLogLevel = .debug
        #else
            dynamicLogLevel = .info
        #endif

        DDLogInfo("LoggerManager initialized")
    }

    /// Redact sensitive strings (API keys, long alphanumeric strings)
    static func redact(_ message: String) -> String {
        // Pattern: >20 character alphanumeric strings (potential API keys)
        let pattern = "[a-zA-Z0-9]{20,}"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(message.startIndex..., in: message)
            return regex.stringByReplacingMatches(
                in: message,
                options: [],
                range: range,
                withTemplate: "[REDACTED]"
            )
        } catch {
            // Cannot use Log.error here since redact is called within Log methods
            // Just return original message if regex fails
            return message
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
