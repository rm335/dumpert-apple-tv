import Foundation
import Sentry
import os

enum SentryMonitoring {
    @MainActor
    static func start() {
#if !DEBUG
        guard let dsn = configurationValue(for: "SentryDSN") else {
            Logger.monitoring.info("Sentry disabled: no DSN configured")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = configurationValue(for: "SentryEnvironment") ?? "production"
            options.sendDefaultPii = false

            // Begin with error monitoring only. Tracing can be sampled later if it proves useful.
            options.tracesSampleRate = 0
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false

            // App Hangs surface as a pure SwiftUI/UIKit layout stack whose only
            // in-app frame is `$main` — Sentry cannot name the offending view
            // without the captured hierarchy. Attaching it (plus a screenshot)
            // is what makes the next hang report actually actionable. Both are
            // captured only at crash/hang time, so there is no steady-state cost.
            options.attachScreenshot = true
            options.attachViewHierarchy = true
        }

        if ProcessInfo.processInfo.arguments.contains("--sentry-test-event") {
            SentrySDK.capture(message: "DumpertTV Sentry integration test")
        }
#endif
    }

    private static func configurationValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, !trimmedValue.contains("$(") else {
            return nil
        }
        return trimmedValue
    }
}
