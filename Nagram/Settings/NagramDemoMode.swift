import Foundation

/// Launch-only mode: never persisted or synchronized to another device.
public enum NagramDemoMode {
    #if DEBUG && targetEnvironment(simulator)
    private static let isCanvasPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || Bundle.main.bundleIdentifier == "app.nextgram.MusicCanvas"
    #else
    private static let isCanvasPreview = false
    #endif

    public static let isEnabled = CommandLine.arguments.contains("--demo") || isCanvasPreview

    public static let userDefaults: UserDefaults = {
        guard isEnabled else {
            return .standard
        }
        guard let defaults = UserDefaults(suiteName: "nagram.screenshot-demo") else {
            preconditionFailure("Could not open demo settings")
        }
        return defaults
    }()
}
