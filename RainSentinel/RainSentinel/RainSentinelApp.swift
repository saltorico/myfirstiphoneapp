import SwiftUI

@main
struct RainSentinelApp: App {
    @StateObject private var agent = WeatherAgent()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(agent)
        }
    }
}
