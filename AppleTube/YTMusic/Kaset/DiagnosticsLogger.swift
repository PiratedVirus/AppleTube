import os

/// Stand-in for Kaset's DiagnosticsLogger so its parsers compile unchanged.
enum DiagnosticsLogger {
    static let api = Logger(subsystem: "dev.saurabhk.AppleTube", category: "api")
}
