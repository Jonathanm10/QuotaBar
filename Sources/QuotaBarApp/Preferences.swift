import Foundation
import Observation

@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let showWeeklyInStatusBar = "showWeeklyInStatusBar"
        static let showPercentRemaining = "showPercentRemaining"
    }

    var showWeeklyInStatusBar: Bool {
        didSet { UserDefaults.standard.set(showWeeklyInStatusBar, forKey: Key.showWeeklyInStatusBar) }
    }

    var showPercentRemaining: Bool {
        didSet { UserDefaults.standard.set(showPercentRemaining, forKey: Key.showPercentRemaining) }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.showWeeklyInStatusBar = (defaults.object(forKey: Key.showWeeklyInStatusBar) as? Bool) ?? true
        self.showPercentRemaining = (defaults.object(forKey: Key.showPercentRemaining) as? Bool) ?? false
    }
}
