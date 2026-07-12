import SwiftUI

@main
struct FlightTrackerApp: App {
    private let environment: AppEnvironment

    init() {
        let processInfo = ProcessInfo.processInfo
        let arguments = processInfo.arguments
        var configuration = AircraftRequestConfiguration()
        if arguments.contains("-UITestFastPolling") {
            configuration.pollingInterval = .seconds(2)
            configuration.viewportDebounce = .milliseconds(50)
        }
        if arguments.contains("-UITestWideLimits") {
            configuration.maximumLatitudeSpan = 180
            configuration.maximumLongitudeSpan = 360
        }
        let provider = Self.makeProvider(arguments: arguments, environment: processInfo.environment)
        environment = AppEnvironment(
            aircraftProvider: provider,
            requestConfiguration: configuration,
            retryPolicy: arguments.contains("-UITestStaleProvider")
                ? PollingRetryPolicy(maximumRetryCount: 0)
                : PollingRetryPolicy()
        )
    }

    nonisolated static func makeProvider(
        arguments: [String],
        environment: [String: String]
    ) -> any AircraftProvider {
        let usesMockProvider = arguments.contains("-UseMockProvider")
            || arguments.contains("-Performance1500")
            || arguments.contains(where: { $0.hasPrefix("-UITest") })

        if usesMockProvider {
            return MockAircraftProvider(
                aircraftCount: arguments.contains("-Performance1500") ? 1_500 : 500,
                failureAfterRequestCount: arguments.contains("-UITestStaleProvider") ? 10 : nil,
                responseDelay: arguments.contains("-UITestSlowInitialLoad") ? .seconds(10) : nil
            )
        }
        return OpenSkyProvider(bearerToken: environment["OPENSKY_BEARER_TOKEN"])
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
