# Flight Tracker

A native SwiftUI aircraft explorer for iPhone and iPad. The app combines a
live, provider-independent aircraft map with smooth motion, trails, follow
mode, search, filters, aircraft metadata, and a bundled airport database.

## Requirements

- Xcode 26 or newer
- iOS/iPadOS 18 or newer

## Run

1. Open `FlightTracker.xcodeproj`.
2. Select the `FlightTracker` scheme.
3. Choose an iPhone or iPad Simulator.
4. Press **Command-R**.

Normal launches use live OpenSky Network data. Add the `-UseMockProvider`
launch argument for a deterministic offline demo, or set the
`OPENSKY_BEARER_TOKEN` environment variable to authenticate OpenSky requests.
Provider selection is configured in `FlightTracker/App/FlightTrackerApp.swift`.

Run unit and UI tests with **Command-U**.

## Included features

- Provider-independent aircraft networking architecture
- OpenSky and seeded mock providers
- Viewport polling, retry handling, stale-state support, and cancellation
- Display-refresh aircraft interpolation and historical trails
- Selected-aircraft camera follow mode
- Indexed aircraft, airline, and airport search
- 12,000-record local airport database with runway metadata
- Airport pins, clustering, and airport detail sheets
- Aircraft filtering, in-memory favorites, and shareable deep links
- VoiceOver labels, Dynamic Type layouts, and Reduce Motion support

Aircraft and airport information is for informational purposes only and must
not be used for navigation or collision avoidance.
