import Combine
import CoreLocation
import SwiftUI
import UserNotifications

@MainActor
final class WeatherAgent: ObservableObject {
    @Published var locationQuery: String {
        didSet { saveSettings() }
    }
    @Published var checkFrequency: CheckFrequency {
        didSet { scheduleTimerIfNeeded(); saveSettings() }
    }
    @Published var notifyOnEveryCheck: Bool {
        didSet { saveSettings() }
    }
    @Published private(set) var isPerformingCheck = false
    @Published private(set) var isResolvingLocation = false
    @Published var isAgentActive: Bool {
        didSet { saveSettings() }
    }
    @Published private(set) var nextScheduledCheck: Date?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastResult: RainResult?
    @Published private(set) var statusMessage: String?

    private var timerCancellable: AnyCancellable?
    private var shouldIgnoreToggleEvent = false
    private let settingsStore = UserDefaults.standard
    private let notificationManager = NotificationManager()
    private let weatherService = WeatherService()
    private let locationFetcher = LocationFetcher()

    init() {
        locationQuery = settingsStore.string(forKey: SettingsKey.locationQuery.rawValue) ?? ""
        checkFrequency = CheckFrequency(rawValue: settingsStore.integer(forKey: SettingsKey.frequency.rawValue)) ?? .everyHour
        notifyOnEveryCheck = settingsStore.bool(forKey: SettingsKey.notifyEveryCheck.rawValue)
        isAgentActive = settingsStore.bool(forKey: SettingsKey.agentActive.rawValue)

        if isAgentActive {
            scheduleTimerIfNeeded()
        }
    }

    func handleToggleChange(isEnabled: Bool) async {
        if shouldIgnoreToggleEvent {
            shouldIgnoreToggleEvent = false
            return
        }

        if isEnabled {
            guard !locationQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
                revertToggle()
                statusMessage = "Enter a location before enabling the agent."
                return
            }
            let granted = await notificationManager.requestAuthorization()
            if !granted {
                statusMessage = "Notification permission denied. Enable it in Settings to receive alerts."
            }
            scheduleTimerIfNeeded()
            statusMessage = "The agent will check every \(checkFrequency.description)."
            await performScheduledCheck()
        } else {
            timerCancellable?.cancel()
            nextScheduledCheck = nil
            statusMessage = "Agent disabled."
        }
    }

    func performManualCheck() async {
        await runCheck(reason: .manual)
    }

    func performScheduledCheck() async {
        await runCheck(reason: .scheduled)
    }

    func useCurrentLocation() async {
        isResolvingLocation = true
        defer { isResolvingLocation = false }

        do {
            let location = try await locationFetcher.currentLocation()
            let placemarks = try await geocode(location: location)
            if let placemark = placemarks.first {
                locationQuery = placemark.compactAddress ?? ""
                statusMessage = "Using \(locationQuery)"
            }
        } catch WeatherError.locationNotFound {
            statusMessage = "Unable to determine your current location."
        } catch {
            statusMessage = "Could not resolve current location: \(error.localizedDescription)"
        }
    }

    func dismissSchedule() {
        scheduleTimerIfNeeded()
    }

    private func geocode(location: CLLocation) async throws -> [CLPlacemark] {
        try await withCheckedThrowingContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: placemarks ?? [])
                }
            }
        }
    }

    private func coordinates(for query: String) async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            CLGeocoder().geocodeAddressString(query) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let coordinate = placemarks?.first?.location?.coordinate {
                    continuation.resume(returning: coordinate)
                } else {
                    continuation.resume(throwing: WeatherError.locationNotFound)
                }
            }
        }
    }

    private func runCheck(reason: CheckReason) async {
        guard !locationQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            statusMessage = "Please enter a location first."
            return
        }

        if isPerformingCheck { return }

        isPerformingCheck = true
        statusMessage = reason == .manual ? "Checking now…" : "Scheduled check running…"
        do {
            let coordinate = try await coordinates(for: locationQuery)
            let forecast = try await weatherService.fetchForecast(for: coordinate)
            handleForecast(forecast, reason: reason)
        } catch WeatherError.locationNotFound {
            statusMessage = "Could not resolve that location. Please refine your search."
        } catch {
            statusMessage = "Weather check failed: \(error.localizedDescription)"
        }
        isPerformingCheck = false
        lastChecked = Date()
        scheduleTimerIfNeeded()
    }

    private func handleForecast(_ forecast: RainForecast, reason: CheckReason) {
        let result = RainResult(forecast: forecast)
        lastResult = result

        if result.isRainLikely {
            let body = "Rain is expected around \(result.likelyTime.formatted(date: .omitted, time: .shortened))."
            notificationManager.sendNotification(title: "Rain likely today", body: body)
        } else if notifyOnEveryCheck {
            notificationManager.sendNotification(title: "No rain detected", body: "The latest check for \(locationQuery) looks dry.")
        }

        statusMessage = result.summary
    }

    private func scheduleTimerIfNeeded() {
        timerCancellable?.cancel()
        guard isAgentActive else { return }

        let interval = checkFrequency.timeInterval
        let next = Date().addingTimeInterval(interval)
        nextScheduledCheck = next

        timerCancellable = Timer.publish(every: interval, tolerance: interval * 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    guard let self else { return }
                    await self.performScheduledCheck()
                }
            }
    }

    private func saveSettings() {
        settingsStore.set(locationQuery, forKey: SettingsKey.locationQuery.rawValue)
        settingsStore.set(checkFrequency.rawValue, forKey: SettingsKey.frequency.rawValue)
        settingsStore.set(isAgentActive, forKey: SettingsKey.agentActive.rawValue)
        settingsStore.set(notifyOnEveryCheck, forKey: SettingsKey.notifyEveryCheck.rawValue)
    }

    private func revertToggle() {
        shouldIgnoreToggleEvent = true
        isAgentActive = false
    }

    enum CheckReason {
        case manual
        case scheduled
    }

    enum SettingsKey: String {
        case locationQuery
        case frequency
        case agentActive
        case notifyEveryCheck
    }

}

extension WeatherAgent {
    static var preview: WeatherAgent {
        let agent = WeatherAgent()
        agent.locationQuery = "Seattle, WA"
        agent.lastChecked = Date()
        agent.lastResult = RainResult.mock
        agent.statusMessage = "Preview data"
        return agent
    }
}

extension CLPlacemark {
    var compactAddress: String? {
        var components: [String] = []
        if let locality { components.append(locality) }
        if let administrativeArea { components.append(administrativeArea) }
        if let country, components.isEmpty { components.append(country) }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
}

private final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func currentLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw WeatherError.locationNotFound
        }

        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestWhenInUseAuthorization()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation else { return }
        self.continuation = nil
        if let location = locations.last {
            continuation.resume(returning: location)
        } else {
            continuation.resume(throwing: WeatherError.locationNotFound)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}
