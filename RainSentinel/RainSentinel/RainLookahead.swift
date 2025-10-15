import Foundation

enum RainLookahead: Int, CaseIterable, Identifiable {
    case sixHours = 6
    case twelveHours = 12
    case twentyFourHours = 24
    case fortyEightHours = 48

    var id: Int { rawValue }

    var description: String {
        switch self {
        case .sixHours:
            return "6 hours"
        case .twelveHours:
            return "12 hours"
        case .twentyFourHours:
            return "24 hours"
        case .fortyEightHours:
            return "48 hours"
        }
    }

    var forecastDays: Int {
        max(1, Int(ceil(Double(rawValue) / 24.0)))
    }
}
