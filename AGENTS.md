# Repository Agent Instructions

- Prefer adding runtime assertions to validate code behavior, but ensure they do not impact production performance by gating them behind a debug-mode check.
- Maintain this file by appending notes about attempted fixes or debugging trails so that future work can build on prior knowledge.
- When introducing or referencing a debug/prod mode flag, prefer using a centralized configuration (e.g., `DEBUG` constant or environment variable) that can be toggled easily.
- Follow platform conventions for Swift/iOS code style when editing files under `RainSentinel/`.
- Update this file with any new conventions adopted during your changes.

## Code Map
- `RainSentinel/RainSentinel/WeatherService.swift`: Builds `RainForecast` models, formats human-readable rain summaries, and houses debug-only integrity assertions for remote data.
- `RainSentinel/RainSentinel/WeatherAgent.swift`: Orchestrates forecast fetching, persistence, and scheduling logic for the rain sentinel.
- `RainSentinel/RainSentinel/ContentView.swift`: SwiftUI presentation for forecast summaries, charts, and agent controls.
- `RainSentinel/RainSentinel/FlappyBirdGame.swift`: SpriteKit-powered easter-egg mini game launched when imminent rain is detected.
- `RainSentinel/RainSentinel/BuildConfiguration.swift`: Centralizes build-mode detection and debug-only assertion helper.

## Attempt Log
- _[initial]_ Repository instructions file created.
- _[2025-10-18]_ Resolved duplicate debug validation call introduced during merge conflict cleanup in `WeatherService.swift`.
- _[2025-10-18]_ Simplified `WeatherService` timestamp handling to rely on local timezone after removing remote timezone logic per user feedback.
- _[2025-10-18]_ Corrected Open-Meteo timezone selection and strengthened forecast window debug assertions to keep lookahead and next 24-hour tables aligned.
- _[2025-02-14]_ Adjusted summary phrasing to call out when forecasted rain falls on the next day so "tomorrow" timing is explicit.
- _[2025-02-15]_ Removed debug-only forecast tables/raw JSON, introduced flappy bird easter egg gate keyed to imminent rain, and added SpriteKit scene for gameplay.
- _[2025-02-16]_ Expanded imminent rain window to 60 minutes so the rain-delay mini game appears when next-hour rain is detected and added a debug assertion for stale forecasts.
- _[2025-02-16]_ Hardened Flappy Bird scene initialization to rebuild missing nodes and added centralized debug assertions after nil bird crash reproduced when tapping before SpriteKit finished configuring.
