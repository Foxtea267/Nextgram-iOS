import Foundation

/// Launch-only mode: never persisted or synchronized to another device.
public enum NagramDemoMode {
    public static let isCanvasPreview: Bool = {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        #else
        return false
        #endif
    }()

    public static let isEnabled = isCanvasPreview || CommandLine.arguments.contains("--demo")

    public static let userDefaults: UserDefaults = {
        guard isEnabled else {
            return .standard
        }
        let suite = isCanvasPreview ? "nextgram.canvas-preview" : "nagram.screenshot-demo"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Could not open demo settings")
        }
        return defaults
    }()
}
