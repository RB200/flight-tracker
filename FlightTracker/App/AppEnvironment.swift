import Foundation

struct AppEnvironment: Sendable {
    let aircraftProvider: any AircraftProvider
    let aircraftPollingService: AircraftPollingService
    let requestConfiguration: AircraftRequestConfiguration
    let airportDatabase: AirportDatabase
    let searchIndex: InMemorySearchIndex

    init(
        aircraftProvider: any AircraftProvider,
        requestConfiguration: AircraftRequestConfiguration = AircraftRequestConfiguration(),
        retryPolicy: PollingRetryPolicy = PollingRetryPolicy()
    ) {
        self.aircraftProvider = aircraftProvider
        self.requestConfiguration = requestConfiguration
        aircraftPollingService = AircraftPollingService(
            provider: aircraftProvider,
            configuration: requestConfiguration,
            retryPolicy: retryPolicy
        )
        airportDatabase = AirportDatabase()
        searchIndex = InMemorySearchIndex()
    }
}
