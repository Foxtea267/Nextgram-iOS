import Foundation

/// How the composer offers text styles: the keyboard-area panel behind the format button, a bar that
/// stays under the input field while typing, or both.
public enum NagramTextStyleToolbarMode: String, CaseIterable {
    case off
    case panel
    case bar
    case both

    public var showsPanel: Bool {
        return self == .panel || self == .both
    }

    public var showsBar: Bool {
        return self == .bar || self == .both
    }
}

private let nagramTextStyleToolbarModeKey = "nagram.textStyleToolbarMode"

public extension NagramSettings {
    /// Until a mode is chosen, the former on/off switch (`nagram.showTextStyleToolbar`) decides,
    /// so an upgrade keeps each user's existing behavior.
    var textStyleToolbarMode: NagramTextStyleToolbarMode {
        get {
            if let stored = NagramDemoMode.userDefaults.string(forKey: nagramTextStyleToolbarModeKey), let mode = NagramTextStyleToolbarMode(rawValue: stored) {
                return mode
            }
            return self.showTextStyleToolbar ? .panel : .off
        }
        set {
            NagramSettingsCloudSync.shared.set(newValue.rawValue, forKey: nagramTextStyleToolbarModeKey)
        }
    }
}
