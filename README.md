# Rain Sentinel

Rain Sentinel is a SwiftUI iOS application that helps you monitor the chance of rain for a custom location. It can run an automated "agent" on your device that checks the Open-Meteo service on a schedule and raises a local notification whenever rain is likely.

## Features

- Search for any city, address, or use your current location to configure the watch area.
- Choose how often the agent checks for rain (30 minutes to 6 hours).
- Optional notifications when it stays dry, in addition to rain alerts.
- Manual "Check now" button for an on-demand forecast.

## Requirements

- Xcode 15 or later.
- An iPhone running iOS 16 or later.
- Network connectivity for weather lookups.

## Installation

1. Download or clone this repository.
2. Open `RainSentinel/RainSentinel.xcodeproj` in Xcode.
3. Update the bundle identifier under *Signing & Capabilities* to something unique to your Apple developer account.
4. Select your iPhone as the run destination, build, and run.

> **Note:** Background execution is limited by iOS. The agent relies on timers that work while the app remains in the foreground or recently backgrounded. For truly persistent background checks, consider integrating Background App Refresh or push notifications.

## Notifications & Privacy

The app requests notification permissions so it can alert you when rain is likely. If you use the "Current Location" shortcut, the app will ask for location access to resolve your position.

## Weather Data

Forecasts are retrieved from the free [Open-Meteo](https://open-meteo.com/) API. No API key is required.
