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
                    Button("Use Current Location") {
                        Task {
                            await agent.useCurrentLocation()
                        }
                    }
                    .disabled(agent.isResolvingLocation)
                    if agent.isResolvingLocation {
                        ProgressView("Resolving…")
                    }
                }

                Section(header: Text("Agent")) {
                    Toggle(isOn: $agent.isAgentActive) {
                        Text(agent.isAgentActive ? "Rain agent enabled" : "Enable rain agent")
                    }
                    .onChange(of: agent.isAgentActive) { isOn in
                        Task {
                            await agent.handleToggleChange(isEnabled: isOn)
                        }
                    }

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
                    if let message = agent.statusMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
