import CoreLocation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var agent: WeatherAgent
    @State private var showingScheduleSheet = false
    @State private var showingRainDelayGame = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Location")) {
                    TextField("City, State or Address", text: $agent.locationQuery)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .onSubmit {
                            Task { await agent.searchLocationMatches() }
                        }
                    Button("Use Current Location") {
                        Task {
                            await agent.useCurrentLocation()
                        }
                    }
                    .disabled(agent.isResolvingLocation)
                    Button {
                        Task { await agent.searchLocationMatches() }
                    } label: {
                        Label("Find Matches", systemImage: "magnifyingglass")
                    }
                    .disabled(agent.isSearchingLocations || agent.locationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if agent.isResolvingLocation {
                        ProgressView("Resolving…")
                    } else if agent.isSearchingLocations {
                        ProgressView("Searching…")
                    }
                    if !agent.locationSuggestions.isEmpty {
                        ForEach(agent.locationSuggestions) { suggestion in
                            Button {
                                agent.selectSuggestion(suggestion)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(suggestion.title)
                                    if let subtitle = suggestion.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Agent"), footer: Text("Open-Meteo provides worldwide coverage for these hourly rain predictions.")) {
                    Toggle(isOn: $agent.isAgentActive) {
                        Text(agent.isAgentActive ? "Rain agent enabled" : "Enable rain agent")
                    }
                    .onChange(of: agent.isAgentActive) { isOn in
                        Task {
                            await agent.handleToggleChange(isEnabled: isOn)
                        }
                    }

                    Picker("Look ahead", selection: $agent.lookaheadWindow) {
                        ForEach(RainLookahead.allCases) { window in
                            Text(window.description).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button(action: {
                        Task { await agent.performManualCheck() }
                    }) {
                        Label("Check now", systemImage: "cloud.sun.bolt")
                    }
                    .disabled(agent.isPerformingCheck)

                    if let nextCheck = agent.nextScheduledCheck {
                        LabeledContent("Next check") {
                            Text(nextCheck, style: .time)
                        }
                    }
                }

                Section(header: Text("Status")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let lastResult = agent.lastResult {
                            Label(lastResult.summary, systemImage: lastResult.iconName)
                                .foregroundStyle(lastResult.isRainLikely ? Color.blue : Color.secondary)
                            if let details = lastResult.details {
                                Text(details)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No checks have been run yet.")
                                .foregroundStyle(.secondary)
                        }

                        if let lastChecked = agent.lastChecked {
                            Text("Last checked: \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let linkURL = agent.providerLinkURL {
                        Link(destination: linkURL) {
                            Label("Open hourly precipitation API", systemImage: "arrow.up.forward.app")
                        }
                        .font(.footnote)
                    }
                    if let message = agent.statusMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let forecast = agent.lastForecast {
                        VStack(alignment: .leading, spacing: 16) {
                            ForecastMetadataView(timezone: forecast.timezone, coordinate: agent.lastResolvedCoordinate)
                                .padding(.top, 4)

                            if !forecast.points.isEmpty {
                                if forecast.points.count > 24 {
                                    ScrollView(.vertical) {
                                        ForecastTable(points: forecast.points, timezone: forecast.timezone)
                                    }
                                    .frame(maxHeight: 320)
                                    .padding(.top, 8)
                                } else {
                                    ForecastTable(points: forecast.points, timezone: forecast.timezone)
                                        .padding(.top, 8)
                                }
                            }

                            if shouldOfferRainDelay(for: forecast) {
                                RainDelayGameButton {
                                    showingRainDelayGame = true
                                }
                                .accessibilityIdentifier("rainDelayGameButton")
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Rain Sentinel")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingScheduleSheet = true
                    } label: {
                        Label("Schedule", systemImage: "clock")
                    }
                }
            }
            .sheet(isPresented: $showingScheduleSheet) {
                NavigationStack {
                    ScheduleView()
                        .environmentObject(agent)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingRainDelayGame) {
                FlappyBirdGameView()
            }
        }
    }
}

private struct ForecastTable: View {
    let points: [RainForecast.DataPoint]
    let timezone: TimeZone

    private var timeFormatter: Date.FormatStyle {
        Date.FormatStyle(date: .omitted,
                         time: .shortened,
                         locale: Locale.current,
                         calendar: Calendar.current,
                         timeZone: timezone)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Time")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Chance")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .frame(width: 70, alignment: .trailing)
                Text("Rain")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.secondary.opacity(0.1))

            ForEach(points) { point in
                Divider()
                ForecastTableRow(point: point, timeFormatter: timeFormatter)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct ForecastTableRow: View {
    let point: RainForecast.DataPoint
    let timeFormatter: Date.FormatStyle

    var body: some View {
        HStack(spacing: 12) {
            Text(point.date.formatted(timeFormatter))
                .font(.body.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(Int(point.probability.rounded()))%")
                .font(.body.monospacedDigit())
                .fontWeight(.semibold)
                .frame(width: 70, alignment: .trailing)
            Text(String(format: "%.2f", point.rainfallAmount))
                .font(.body.monospacedDigit())
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
    }
}

private struct ForecastMetadataView: View {
    let timezone: TimeZone
    let coordinate: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let coordinate {
                Text("Coordinates: \(String(format: "%.4f", coordinate.latitude)), \(String(format: "%.4f", coordinate.longitude))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Times shown in \(timezone.localizedName(for: .shortGeneric, locale: .current) ?? timezone.identifier)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private func shouldOfferRainDelay(for forecast: RainForecast) -> Bool {
    guard let upcomingPoint = forecast.upcomingRainPoint else { return false }
    let now = Date()
    let immediateThreshold: TimeInterval = 20 * 60 // 20 minutes window for "due immediately"
    return upcomingPoint.date <= now.addingTimeInterval(immediateThreshold)
}

private struct RainDelayGameButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                FlappyBirdAvatar()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Rain delay flappy bird")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Kill a few minutes while the storm rolls in.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play flappy bird to pass the time")
    }
}

private struct FlappyBirdAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.yellow, Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 4)
            WingShape()
                .fill(Color.orange.opacity(0.8))
                .frame(width: 28, height: 20)
                .offset(x: -4, y: 8)
            Triangle()
                .fill(Color.orange)
                .frame(width: 18, height: 12)
                .offset(x: 26)
            Eye()
                .frame(width: 14, height: 14)
                .offset(x: 6, y: -8)
        }
    }

    private struct WingShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.midX * 0.2, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.midX * 0.2, y: rect.maxY))
            return path
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    private struct Eye: View {
        var body: some View {
            ZStack {
                Circle()
                    .fill(Color.white)
                Circle()
                    .fill(Color.black)
                    .frame(width: 6, height: 6)
                    .offset(x: 2, y: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
        }
    }
}

struct ScheduleView: View {
    @EnvironmentObject private var agent: WeatherAgent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(header: Text("Frequency")) {
                Picker("Check every", selection: $agent.checkFrequency) {
                    ForEach(CheckFrequency.allCases) { frequency in
                        Text(frequency.description).tag(frequency)
                    }
                }
                .pickerStyle(.inline)
            }

            Section(footer: Text("You will receive a notification if the service forecasts a significant chance of rain during the next few hours.")) {
                Toggle("Notify on every check", isOn: $agent.notifyOnEveryCheck)
            }
        }
        .navigationTitle("Agent schedule")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    agent.dismissSchedule()
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WeatherAgent.preview)
}
