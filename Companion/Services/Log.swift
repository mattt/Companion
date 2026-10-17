import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "me.mattt.Companion"

    static let server = Logger(subsystem: subsystem, category: "Server")
    static let connection = Logger(subsystem: subsystem, category: "Connection")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let ui = Logger(subsystem: subsystem, category: "UI")
}
