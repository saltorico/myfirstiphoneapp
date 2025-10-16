import CoreLocation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var agent: WeatherAgent
    @State private var showingScheduleSheet = false

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
                    if let forecast = agent.lastForecast, !forecast.next24HourPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Next 24 hours precipitation chance")
                                .font(.headline)
                            ForecastTable(points: forecast.next24HourPoints, timezone: forecast.timezone)
                            ForecastMetadataView(timezone: forecast.timezone, coordinate: agent.lastResolvedCoordinate)
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
            HStack {
                Text("Time")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                Spacer()
                Text("Chance")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
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
        HStack {
            Text(point.date.formatted(timeFormatter))
                .font(.body.monospacedDigit())
            Spacer()
            Text("\(Int(point.probability.rounded()))%")
                .font(.body.monospacedDigit())
                .fontWeight(.semibold)
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
