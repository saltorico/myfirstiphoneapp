import Foundation
import CoreLocation

struct RainForecast {
    struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let probability: Double
        let rainfallAmount: Double
    }

    let points: [DataPoint]
    let next24HourPoints: [DataPoint]
    let allPoints: [DataPoint]
    let timezone: TimeZone
    let lookaheadHours: Int
    let rawResponseJSON: String?

    enum DetectionWindow {
        case lookahead
        case next24Hours
        case extended
    }

    private func firstDataPoint(where predicate: (DataPoint) -> Bool) -> DataPoint? {
        for series in [points, next24HourPoints, allPoints] {
            if let match = series.first(where: predicate) {
                return match
            }
        }
        return nil
    }

    var upcomingRainPoint: DataPoint? {
        firstDataPoint { $0.probability >= 50 || $0.rainfallAmount > 0.1 }
    }

    var moderateRainPoint: DataPoint? {
        firstDataPoint { $0.probability >= 20 || $0.rainfallAmount > 0.05 }
    }

    var highestProbabilityPoint: DataPoint? {
        (allPoints.isEmpty ? (next24HourPoints.isEmpty ? points : next24HourPoints) : allPoints)
            .max(by: { $0.probability < $1.probability })
    }

    func detectionWindow(for point: DataPoint) -> DetectionWindow {
        if points.contains(where: { $0.id == point.id }) {
            return .lookahead
        }
        if next24HourPoints.contains(where: { $0.id == point.id }) {
            return .next24Hours
        }
        return .extended
    }
}

struct RainResult {
    let isRainLikely: Bool
    let summary: String
    let details: String?
    let likelyTime: Date
    let iconName: String

    init(forecast: RainForecast) {
        let shortTimeFormatter = Date.FormatStyle(date: .omitted,
                                                  time: .shortened,
                                                  locale: Locale.current,
                                                  calendar: Calendar.current,
                                                  timeZone: forecast.timezone)
        let dayTimeFormatter = Date.FormatStyle(date: .abbreviated,
                                                time: .shortened,
                                                locale: Locale.current,
                                                calendar: Calendar.current,
                                                timeZone: forecast.timezone)

        if let rainPoint = forecast.upcomingRainPoint {
            isRainLikely = true
            likelyTime = rainPoint.date
            summary = "Rain likely around \(rainPoint.date.formatted(shortTimeFormatter)) with a \(Int(rainPoint.probability.rounded()))% chance."
            if let maxPoint = forecast.highestProbabilityPoint {
                details = "Peak chance reaches \(Int(maxPoint.probability.rounded()))% during the forecast window."
            } else {
                details = nil
            }
            iconName = "cloud.rain"
        } else if let moderatePoint = forecast.moderateRainPoint {
            isRainLikely = false
            likelyTime = moderatePoint.date
            summary = "Showers possible around \(moderatePoint.date.formatted(shortTimeFormatter)) with a \(Int(moderatePoint.probability.rounded()))% chance."
            if let maxPoint = forecast.highestProbabilityPoint {
                details = "Peak chance reaches \(Int(maxPoint.probability.rounded()))% within the next \(forecast.lookaheadHours) hours."
            } else {
                details = nil
            }
            iconName = "cloud.drizzle"
        } else {
            isRainLikely = false
            likelyTime = Date()
            summary = "No rain expected in the next \(forecast.lookaheadHours) hours."
            if let maxPoint = forecast.highestProbabilityPoint {
                details = "Highest chance stays around \(Int(maxPoint.probability.rounded()))% with minimal rainfall expected."
            } else {
                details = nil
            }
            iconName = "sun.max"

#if DEBUG
            let pointCount = forecast.allPoints.count
            guard pointCount > 0 else {
                preconditionFailure("No-rain conclusion drawn with zero hourly data points – hourly parsing failed.")
            }

            if forecast.lookaheadHours >= 24 && !(pointCount == 24 || pointCount == 48) {
                preconditionFailure("No-rain conclusion drawn without expected 24/48 data points (actual: \(pointCount))")
            }

            let timezones = forecast.allPoints.map { forecast.timezone.secondsFromGMT(for: $0.date) }
            if let firstOffset = timezones.first {
                let inconsistentOffsets = timezones.filter { abs($0 - firstOffset) > 3600 }
                if !inconsistentOffsets.isEmpty {
                    preconditionFailure("Timezone offsets vary unexpectedly across forecast points: \(inconsistentOffsets)")
                }
            } else {
                preconditionFailure("Unable to derive timezone offsets because forecast points are missing timestamps.")
            }

            let nonZeroPoints = forecast.allPoints.filter { $0.probability > 0 || $0.rainfallAmount > 0 }
            if !nonZeroPoints.isEmpty {
                preconditionFailure("No-rain conclusion contradicted by \(nonZeroPoints.count) data points with precipitation signals.")
            }

            if let maxPoint = forecast.highestProbabilityPoint,
               maxPoint.probability >= 50 || maxPoint.rainfallAmount > 0.1 {
                preconditionFailure("Highest probability point (\(Int(maxPoint.probability.rounded()))%, \(maxPoint.rainfallAmount) mm) conflicts with no-rain outcome.")
            }
#endif
        }
    }

    static let mock = RainResult(isRainLikely: true,
                                 summary: "Rain likely around 4:00 PM with a 70% chance.",
                                 details: "Peak chance reaches 80% during the forecast window.",
                                 likelyTime: Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date()) ?? Date(),
                                 iconName: "cloud.rain")

    private init(isRainLikely: Bool, summary: String, details: String?, likelyTime: Date, iconName: String) {
        self.isRainLikely = isRainLikely
        self.summary = summary
        self.details = details
        self.likelyTime = likelyTime
        self.iconName = iconName
    }

    private static func summaryText(leadIn: String,
                                    point: RainForecast.DataPoint,
                                    probability: Double,
                                    detectionWindow: RainForecast.DetectionWindow,
                                    lookaheadHours: Int,
                                    shortTimeFormatter: Date.FormatStyle,
                                    dayTimeFormatter: Date.FormatStyle) -> String {
        let probabilityValue = Int(probability.rounded())
        switch detectionWindow {
        case .lookahead:
            return "\(leadIn) around \(point.date.formatted(shortTimeFormatter)) with a \(probabilityValue)% chance."
        case .next24Hours:
            return "\(leadIn) later around \(point.date.formatted(shortTimeFormatter)) with a \(probabilityValue)% chance (outside the next \(lookaheadHours) hours)."
        case .extended:
            return "\(leadIn) on \(point.date.formatted(dayTimeFormatter)) with a \(probabilityValue)% chance."
        }
    }

    private static func detailText(for forecast: RainForecast,
                                   shortTimeFormatter: Date.FormatStyle,
                                   dayTimeFormatter: Date.FormatStyle) -> String? {
        guard let maxPoint = forecast.highestProbabilityPoint else { return nil }
        let detectionWindow = forecast.detectionWindow(for: maxPoint)
        let formatter = detectionWindow == .extended ? dayTimeFormatter : shortTimeFormatter
        let prefix = detectionWindow == .extended ? "on" : "around"
        let windowDescription = windowDescription(for: detectionWindow, lookaheadHours: forecast.lookaheadHours)
        return "Peak chance reaches \(Int(maxPoint.probability.rounded()))% \(prefix) \(maxPoint.date.formatted(formatter)) \(windowDescription)."
    }

    private static func windowDescription(for detectionWindow: RainForecast.DetectionWindow,
                                          lookaheadHours: Int) -> String {
        switch detectionWindow {
        case .lookahead:
            return "within the next \(lookaheadHours) hours"
        case .next24Hours:
            return "within the next 24 hours"
        case .extended:
            return "later in the forecast"
        }
    }
}

enum WeatherError: Error {
    case locationNotFound
    case decodingFailed
}

final class WeatherService {
    private let decoder: JSONDecoder
    private(set) var lastRequestURL: URL?

    init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func fetchForecast(for coordinate: CLLocationCoordinate2D, lookahead: RainLookahead) async throws -> RainForecast {
        let url = try url(for: coordinate, lookahead: lookahead)
        lastRequestURL = url
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherError.decodingFailed
        }

        let decoded = try decoder.decode(OpenMeteoResponse.self, from: data)
        let rawJSON = String(data: data, encoding: .utf8)
        guard let timezone = TimeZone(identifier: decoded.timezone) ?? TimeZone(secondsFromGMT: decoded.utcOffsetSeconds) else {
            throw WeatherError.decodingFailed
        }

        let timeStrings = decoded.hourly.time
        let probabilities = decoded.hourly.precipitationProbability ?? Array(repeating: 0, count: timeStrings.count)
        let rainAmounts = decoded.hourly.rain ?? Array(repeating: 0, count: timeStrings.count)
        let count = min(timeStrings.count, probabilities.count, rainAmounts.count)
        let parser = OpenMeteoDateParser(timezone: timezone)

#if DEBUG
        debugValidate(decoded: decoded,
                       timeStrings: timeStrings,
                       probabilities: probabilities,
                       rainAmounts: rainAmounts,
                       count: count,
                       lookahead: lookahead,
                       timezone: timezone,
                       parser: parser)
#endif

#if DEBUG
        debugValidate(decoded: decoded,
                       timeStrings: timeStrings,
                       probabilities: probabilities,
                       rainAmounts: rainAmounts,
                       count: count,
                       lookahead: lookahead,
                       timezone: timezone)
#endif

        let allPoints: [RainForecast.DataPoint] = (0..<count).compactMap { index in
            let time = timeStrings[index]
            guard let date = parser.date(from: time) else {
#if DEBUG
                assertionFailure("Failed to parse hourly timestamp \(time) for timezone \(timezone.identifier ?? \"offset:\(timezone.secondsFromGMT())\").")
#endif
                return nil
            }
            let probability = probabilities[index]
            let rainfall = rainAmounts[index]
            return RainForecast.DataPoint(date: date, probability: probability, rainfallAmount: rainfall)
        }

#if DEBUG
        if allPoints.count != count {
            assertionFailure("Parsed only \(allPoints.count) of \(count) hourly timestamps – forecast integrity compromised.")
        }
#endif

        let now = Date()
        let horizon = now.addingTimeInterval(TimeInterval(lookahead.rawValue * 3600))
        let filteredPoints = allPoints.filter { dataPoint in
            dataPoint.date >= now && dataPoint.date <= horizon
        }

        let consideredPoints: [RainForecast.DataPoint]
        if filteredPoints.isEmpty {
            consideredPoints = Array(allPoints.prefix(lookahead.rawValue))
        } else {
            consideredPoints = filteredPoints
        }

        let dayAhead = now.addingTimeInterval(24 * 3600)
        let next24Candidates = allPoints.filter { dataPoint in
            dataPoint.date >= now && dataPoint.date <= dayAhead
        }

        let next24Points: [RainForecast.DataPoint]
        if next24Candidates.isEmpty {
            next24Points = Array(allPoints.prefix(24))
        } else {
            next24Points = Array(next24Candidates.prefix(24))
        }

        return RainForecast(points: consideredPoints,
                             next24HourPoints: next24Points,
                             allPoints: allPoints,
                             timezone: timezone,
                             lookaheadHours: lookahead.rawValue,
                             rawResponseJSON: rawJSON)
    }

    func forecastLink(for coordinate: CLLocationCoordinate2D, lookahead: RainLookahead) -> URL? {
        return try? url(for: coordinate, lookahead: lookahead)
    }

    private func url(for coordinate: CLLocationCoordinate2D, lookahead: RainLookahead) throws -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(name: "hourly", value: "precipitation_probability,rain"),
            URLQueryItem(name: "forecast_days", value: String(lookahead.forecastDays)),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { throw WeatherError.decodingFailed }
        return url
    }
}

#if DEBUG
extension WeatherService {
    private func debugValidate(decoded: OpenMeteoResponse,
                               timeStrings: [String],
                               probabilities: [Double],
                               rainAmounts: [Double],
                               count: Int,
                               lookahead: RainLookahead,
                               timezone: TimeZone,
                               parser: OpenMeteoDateParser) {
        assert(!timeStrings.isEmpty, "Expected hourly time stamps from weather service response")

        if let probabilityCount = decoded.hourly.precipitationProbability?.count {
            assert(probabilityCount == timeStrings.count,
                   "Mismatched precipitation probability count (\(probabilityCount)) for timestamps (\(timeStrings.count))")
        }

        if let rainCount = decoded.hourly.rain?.count {
            assert(rainCount == timeStrings.count,
                   "Mismatched rain amount count (\(rainCount)) for timestamps (\(timeStrings.count))")
        }

        let minimumExpectedPoints = min(timeStrings.count, max(lookahead.rawValue, 1))
        assert(count >= minimumExpectedPoints,
               "Unexpected truncation while preparing rain data points (have: \(count), expected at least: \(minimumExpectedPoints))")

        let referenceDate = Date()
        let timezoneOffset = timezone.secondsFromGMT(for: referenceDate)
        let offsetDifference = abs(timezoneOffset - decoded.utcOffsetSeconds)
        assert(offsetDifference <= 3600,
               "Timezone offset mismatch detected (service: \(decoded.utcOffsetSeconds), system: \(timezoneOffset))")

        let lookaheadHorizon = referenceDate.addingTimeInterval(TimeInterval(lookahead.rawValue * 3600))
        if let firstTime = timeStrings.first,
           let firstDate = parser.date(from: firstTime) {
            assert(firstDate <= lookaheadHorizon.addingTimeInterval(48 * 3600),
                   "First data point is unexpectedly far in the future: \(firstDate)")
        } else if let firstTime = timeStrings.first {
            assertionFailure("Unable to parse first hourly timestamp: \(firstTime)")
        }
    }
}
#endif

private struct OpenMeteoDateParser {
    private let formatter: DateFormatter

    init(timezone: TimeZone) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = timezone
        self.formatter = formatter
    }

    func date(from timeString: String) -> Date? {
        formatter.date(from: timeString)
    }
}

private struct OpenMeteoResponse: Decodable {
    let timezone: String
    let utcOffsetSeconds: Int
    let hourly: Hourly

    struct Hourly: Decodable {
        let time: [String]
        let precipitationProbability: [Double]?
        let rain: [Double]?

        private enum CodingKeys: String, CodingKey {
            case time
            case precipitationProbability = "precipitation_probability"
            case rain
        }
    }

    private enum CodingKeys: String, CodingKey {
        case timezone
        case utcOffsetSeconds = "utc_offset_seconds"
        case hourly
    }
}

