# Repository Agent Instructions

- Prefer adding runtime assertions to validate code behavior, but ensure they do not impact production performance by gating them behind a debug-mode check.
- Maintain this file by appending notes about attempted fixes or debugging trails so that future work can build on prior knowledge.
- When introducing or referencing a debug/prod mode flag, prefer using a centralized configuration (e.g., `DEBUG` constant or environment variable) that can be toggled easily.
- Follow platform conventions for Swift/iOS code style when editing files under `RainSentinel/`.
- Update this file with any new conventions adopted during your changes.

## Attempt Log
- _[initial]_ Repository instructions file created.
- _[2025-10-18]_ Resolved duplicate debug validation call introduced during merge conflict cleanup in `WeatherService.swift`.
- _[2025-10-18]_ Simplified `WeatherService` timestamp handling to rely on local timezone after removing remote timezone logic per user feedback.
