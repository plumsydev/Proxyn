import OSLog

/// Unified logging. Visible in Console.app and in sysdiagnoses, which is what
/// makes a production issue on someone else's cluster diagnosable at all.
enum Log {
    private static let subsystem = "com.proxyn.app"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
}
