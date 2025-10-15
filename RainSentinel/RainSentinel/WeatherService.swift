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
    let timezone: TimeZone
    let lookaheadHours: Int

    var upcomingRainPoint: DataPoint? {
        points.first { $0.probability >= 50 || $0.rainfallAmount > 0.1 }
    }

    var moderateRainPoint: DataPoint? {
        points.first { $0.probability >= 20 || $0.rainfallAmount > 0.05 }
    }

    var highestProbabilityPoint: DataPoint? {
        points.max(by: { $0.probability < $1.probability })
    }
}

struct RainResult {
    let isRainLikely: Bool
    let summary: String
    let details: String?
    let likelyTime: Date
    let iconName: String

    init(forecast: RainForecast) {
        if let rainPoint = forecast.upcomingRainPoint {
            isRainLikely = true
            likelyTime = rainPoint.date
            summary = "Rain likely around \(rainPoint.date.formatted(date: .omitted, time: .shortened)) with a \(Int(rainPoint.probability.rounded()))% chance."
            if let maxPoint = forecast.highestProbabilityPoint {
                details = "Peak chance reaches \(Int(maxPoint.probability.rounded()))% during the forecast window."
            } else {
                details = nil
            }
            iconName = "cloud.rain"
        } else if let moderatePoint = forecast.moderateRainPoint {
            isRainLikely = false
            likelyTime = moderatePoint.date
            summary = "Showers possible around \(moderatePoint.date.formatted(date: .omitted, time: .shortened)) with a \(Int(moderatePoint.probability.rounded()))% chance."
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
}

enum WeatherError: Error {
    case locationNotFound
    case decodingFailed
}

final class WeatherService {
    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func fetchForecast(for coordinate: CLLocationCoordinate2D, lookahead: RainLookahead) async throws -> RainForecast {
        let url = try url(for: coordinate, lookahead: lookahead)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherError.decodingFailed
        }

        let decoded = try decoder.decode(OpenMeteoResponse.self, from: data)
        guard let timezone = TimeZone(identifier: decoded.timezone) ?? TimeZone(secondsFromGMT: decoded.utcOffsetSeconds) else {
            throw WeatherError.decodingFailed
        }

        let timeStrings = decoded.hourly.time
        let probabilities = decoded.hourly.precipitationProbability ?? Array(repeating: 0, count: timeStrings.count)
        let rainAmounts = decoded.hourly.rain ?? Array(repeating: 0, count: timeStrings.count)
        let count = min(timeStrings.count, probabilities.count, rainAmounts.count)

        let allPoints: [RainForecast.DataPoint] = (0..<count).compactMap { index in
            let time = timeStrings[index]
            guard let date = ISO8601DateFormatter.openMeteo.date(from: time) else { return nil }
            let probability = probabilities[index]
            let rainfall = rainAmounts[index]
            return RainForecast.DataPoint(date: date, probability: probability, rainfallAmount: rainfall)
        }

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
                             timezone: timezone,
                             lookaheadHours: lookahead.rawValue)
    }

    func forecastLink(for coordinate: CLLocationCoordinate2D, lookahead: RainLookahead) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "open-meteo.com"
        components.path = "/en/docs"
        let fragment = "latitude=\(String(format: "%.4f", coordinate.latitude))&longitude=\(String(format: "%.4f", coordinate.longitude))&hourly=precipitation_probability,rain&forecast_days=\(lookahead.forecastDays)"
        components.fragment = fragment
        return components.url
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

private extension ISO8601DateFormatter {
    static let openMeteo: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
