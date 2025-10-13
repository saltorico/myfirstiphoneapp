import Foundation

enum CheckFrequency: Int, CaseIterable, Identifiable {
    case every30Minutes = 1800
    case everyHour = 3600
    case every3Hours = 10800
    case every6Hours = 21600

    var id: Int { rawValue }

    var timeInterval: TimeInterval { TimeInterval(rawValue) }

    var description: String {
        switch self {
        case .every30Minutes:
            return "30 minutes"
        case .everyHour:
            return "1 hour"
        case .every3Hours:
            return "3 hours"
        case .every6Hours:
            return "6 hours"
        }
    }
}
