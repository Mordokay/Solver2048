import ActivityKit

/// Defines the Live Activity data model for showing directions on the Dynamic Island.
/// This file must be included in BOTH the main app and the widget extension targets.
struct SolverActivityAttributes: ActivityAttributes {
    // No static attributes needed (we just show directions)

    public struct ContentState: Codable, Hashable {
        var direction: String   // "UP", "DOWN", "LEFT", "RIGHT"
    }

    static func arrowIcon(for direction: String) -> String {
        switch direction {
        case "UP":    return "arrow.up"
        case "DOWN":  return "arrow.down"
        case "LEFT":  return "arrow.left"
        case "RIGHT": return "arrow.right"
        default:      return "questionmark"
        }
    }

    static func arrowChar(for direction: String) -> String {
        switch direction {
        case "UP":    return "↑"
        case "DOWN":  return "↓"
        case "LEFT":  return "←"
        case "RIGHT": return "→"
        default:      return "?"
        }
    }
}
