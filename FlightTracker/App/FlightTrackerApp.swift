import SwiftUI

@main
struct FlightTrackerApp: App {
    private let environment: AppEnvironment

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        var configuration = AircraftRequestConfiguration()
        if arguments.contains("-UITestFastPolling") {
            configuration.pollingInterval = .seconds(2)
            configuration.viewportDebounce = .milliseconds(50)
        }
        if arguments.contains("-UITestWideLimits") {
            configuration.maximumLatitudeSpan = 180
            configuration.maximumLongitudeSpan = 360
        }
        let provider = MockAircraftProvider(
            aircraftCount: arguments.contains("-Performance1500") ? 1_500 : 500,
            failureAfterRequestCount: arguments.contains("-UITestStaleProvider") ? 10 : nil,
            responseDelay: arguments.contains("-UITestSlowInitialLoad") ? .seconds(10) : nil
        )
        environment = AppEnvironment(
            aircraftProvider: provider,
            requestConfiguration: configuration,
            retryPolicy: arguments.contains("-UITestStaleProvider")
                ? PollingRetryPolicy(maximumRetryCount: 0)
                : PollingRetryPolicy()
        )
    }

    var body: some Scene {
        WindowGroup {
            MapScreen(
                pollingService: environment.aircraftPollingService,
                requestConfiguration: environment.requestConfiguration,
                airportDatabase: environment.airportDatabase,
                searchIndex: environment.searchIndex
            )
        }
    }
}
