import SwiftUI

/// How a pet describes itself in a space too small for the real thing — a widget, a
/// complication, or a watch screen read at a glance on the way past.
extension Pet {
    /// The one thing worth saying about a pet in a space this small.
    var widgetHeadline: String {
        // A pet asleep at its own bedtime isn't waiting on anything, and a lock screen
        // shouldn't imply otherwise at two in the morning. While it's out for the day it
        // still says what it wants, because that's exactly when it's useful to know.
        if isAsleep { return "Fast asleep" }
        guard let neediest else {
            // A pet having a wonderful day should be allowed to say so.
            return mood == .ecstatic ? "Having the best day" : mood.label
        }
        return switch neediest {
        case .fullness: "Getting hungry"
        case .fun: "Bored stiff"
        case .affection: "Wants a cuddle"
        case .rest: "Worn out"
        }
    }

    /// What VoiceOver reads instead of picking through the bars one at a time.
    var widgetSummary: String {
        "\(name), \(mood.label.lowercased()). \(widgetHeadline)."
    }
}

extension NeedKind {
    /// Warm colours for the needs that want something from you, cool for rest.
    var tint: Color {
        switch self {
        case .affection: Color(red: 0.95, green: 0.45, blue: 0.58)
        case .fun: Color(red: 0.98, green: 0.66, blue: 0.25)
        case .fullness: Color(red: 0.42, green: 0.74, blue: 0.40)
        case .rest: Color(red: 0.48, green: 0.55, blue: 0.92)
        }
    }
}
