import Foundation
import MCP
import Testing

@testable import Companion

struct AppSettingsTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")!
    }

    @Test func defaultLogLevelFallsBackToDebug() {
        #expect(AppSettings.defaultLogLevel(in: makeDefaults()) == .debug)
    }

    @Test func defaultLogLevelRoundTrips() {
        let defaults = makeDefaults()
        AppSettings.setDefaultLogLevel(.warning, in: defaults)
        #expect(AppSettings.defaultLogLevel(in: defaults) == .warning)
    }

    @Test func defaultLogLevelIgnoresInvalidValue() {
        let defaults = makeDefaults()
        defaults.set("loud", forKey: AppSettingsKey.defaultLogLevel)
        #expect(AppSettings.defaultLogLevel(in: defaults) == .debug)
    }

    @Test func requestTimeoutDefaultsToNever() {
        #expect(AppSettings.requestTimeout(in: makeDefaults()) == nil)
    }

    @Test func requestTimeoutReadsMinutes() {
        let defaults = makeDefaults()
        defaults.set(5, forKey: AppSettingsKey.requestTimeoutMinutes)
        #expect(AppSettings.requestTimeout(in: defaults) == .seconds(300))

        defaults.set(0, forKey: AppSettingsKey.requestTimeoutMinutes)
        #expect(AppSettings.requestTimeout(in: defaults) == nil)
    }
}
