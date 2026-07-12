import Foundation
import Observation

@MainActor
@Observable
final class AircraftMapViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let pollingService: AircraftPollingService
    private let configuration: AircraftRequestConfiguration
    private let airportDatabase: AirportDatabase
    private let searchIndex: InMemorySearchIndex
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var pendingAircraftICAO24: String?

    private(set) var aircraft: [Aircraft] = []
    private(set) var displayedAircraft: [Aircraft] = []
    private(set) var airports: [Airport] = []
    @ObservationIgnored private var allAirportsByID: [String: Airport] = [:]
    var selectedAircraft: Aircraft?
    var selectedAirport: Airport?
    var presentedSheet: ExplorerSheet?
    var cameraRequest: MapCameraRequest?
    var filter = AircraftFilter() { didSet { applyFilters() } }
    let favorites = FavoritesStore()
    var searchQuery = ""
    var isSearchExpanded = false
    private(set) var searchResults: [ExplorerSearchResult] = []
    private(set) var searchSuggestions: [String] = []
    private(set) var recentSearches: [String] = []
    private(set) var isSearching = false
    private(set) var airportLoadState: AirportDatabase.State = .unloaded
    private(set) var loadState: LoadState = .idle
    private(set) var lastUpdateTime: Date?
    private(set) var providerStatus: ProviderStatus = .idle
    private(set) var currentViewport: MapBounds?
    private(set) var isShowingStaleData = false
    var isFollowingSelectedAircraft = false
    var showsSelectedTrail = true

    init(
        pollingService: AircraftPollingService,
        configuration: AircraftRequestConfiguration = AircraftRequestConfiguration(),
        airportDatabase: AirportDatabase = AirportDatabase(),
        searchIndex: InMemorySearchIndex = InMemorySearchIndex()
    ) {
        self.pollingService = pollingService
        self.configuration = configuration
        self.airportDatabase = airportDatabase
        self.searchIndex = searchIndex
    }

    var isRefreshing: Bool {
        providerStatus == .loading && !aircraft.isEmpty
    }

    var isViewportTooLarge: Bool {
        providerStatus == .viewportTooLarge
    }

    func start() async {
        guard snapshotTask == nil, statusTask == nil else { return }
        loadState = aircraft.isEmpty ? .loading : .loaded
        let snapshots = await pollingService.snapshots()
        let statuses = await pollingService.statuses()
        snapshotTask = Task { [weak self] in
            for await snapshot in snapshots {
                guard !Task.isCancelled else { return }
                self?.apply(snapshot)
            }
        }
        statusTask = Task { [weak self] in
            for await status in statuses {
                guard !Task.isCancelled else { return }
                self?.apply(status)
            }
        }
        Task { [weak self] in await self?.loadStaticExplorerData() }
        await pollingService.start()
    }

    func stop() async {
        snapshotTask?.cancel()
        statusTask?.cancel()
        snapshotTask = nil
        statusTask = nil
        await pollingService.stop()
    }

    func setViewport(_ bounds: MapBounds) async {
        let previousViewport = currentViewport
        currentViewport = bounds
        await refreshVisibleAirports(in: bounds)
        if let previousViewport, Self.sameViewport(previousViewport, bounds) { return }
        await pollingService.setViewport(bounds)
    }

    func load(bounds: MapBounds = .continentalUnitedStates) async {
        loadState = .loading
        providerStatus = .loading
        do {
            let snapshot = try await pollingService.fetchSnapshot(in: bounds)
            apply(snapshot)
            if snapshot.isPartial {
                providerStatus = .partial(providerName: snapshot.providerName, aircraftCount: snapshot.aircraft.count)
            } else if snapshot.isStale {
                providerStatus = .stale(providerName: snapshot.providerName, updatedAt: snapshot.fetchTimestamp)
            } else {
                providerStatus = .live(
                    providerName: snapshot.providerName,
                    aircraftCount: snapshot.aircraft.count,
                    updatedAt: snapshot.fetchTimestamp
                )
            }
        } catch is CancellationError {
            loadState = .idle
            providerStatus = .idle
        } catch {
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            providerStatus = apiError == .offline ? .offline : .failed(message: apiError.localizedDescription)
            loadState = .failed(apiError.localizedDescription)
        }
    }

    func setApplicationActive(_ active: Bool) async {
        await pollingService.setApplicationActive(active)
    }

    func select(_ aircraft: Aircraft?) {
        selectedAircraft = aircraft
        if aircraft == nil {
            isFollowingSelectedAircraft = false
            if presentedSheet == .aircraft { presentedSheet = nil }
        } else {
            selectedAirport = nil
            presentedSheet = .aircraft
        }
    }

    func selectAirport(_ airport: Airport?) {
        selectedAirport = airport
        if airport == nil {
            if presentedSheet == .airport { presentedSheet = nil }
        } else {
            selectedAircraft = nil
            isFollowingSelectedAircraft = false
            presentedSheet = .airport
        }
    }

    func showFilters() { presentedSheet = .filters }

    func performSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchSuggestions = []
            isSearching = false
            return
        }
        isSearching = true
        do { try await Task.sleep(for: .milliseconds(250)) } catch { isSearching = false; return }
        guard !Task.isCancelled, query == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        let favoriteIDs = favorites.ids
        let exactAirport = await airportDatabase.airport(code: query)
        let exactAircraft: Aircraft?
        if Self.looksLikeICAO24(query) {
            exactAircraft = try? await pollingService.fetchAircraft(icao24: query)
        } else {
            exactAircraft = nil
        }
        let exactResults = [exactAircraft.map(ExplorerSearchResult.aircraft), exactAirport.map(ExplorerSearchResult.airport)].compactMap { $0 }
        if !exactResults.isEmpty { searchResults = exactResults }
        async let hits = searchIndex.search(query, favoriteIDs: favoriteIDs)
        async let suggestions = searchIndex.suggestions(for: query)
        let indexedResults = await hits.map(\.result)
        searchResults = (exactResults + indexedResults)
            .reduce(into: []) { results, result in
                if !results.contains(where: { $0.id == result.id }) { results.append(result) }
            }
        searchSuggestions = await suggestions
        isSearching = false
    }

    func useSuggestion(_ suggestion: String) {
        searchQuery = suggestion
        isSearchExpanded = true
    }

    func selectSearchResult(_ result: ExplorerSearchResult) {
        recordRecentSearch(searchQuery.isEmpty ? result.title : searchQuery)
        isSearchExpanded = false
        switch result {
        case .aircraft(let aircraft):
            select(aircraft)
            cameraRequest = MapCameraRequest(coordinate: aircraft.coordinate, latitudeSpan: currentViewport?.latitudeSpan ?? 2)
        case .airport(let airport):
            selectAirport(airport)
            cameraRequest = MapCameraRequest(coordinate: airport.coordinate, latitudeSpan: 0.5)
        case .airline(let airline):
            filter.airlineICAOs = [airline.icao]
            presentedSheet = .filters
        }
    }

    func toggleFavorite(_ result: ExplorerSearchResult) { favorites.toggle(result.favoriteID) }

    func isFavorite(_ result: ExplorerSearchResult) -> Bool { favorites.contains(result.favoriteID) }

    var favoriteResults: [ExplorerSearchResult] {
        favorites.ids.compactMap { id in
            switch id {
            case .aircraft(let code): aircraft.first(where: { $0.icao24 == code }).map(ExplorerSearchResult.aircraft)
            case .airport(let id): allAirportsByID[id].map(ExplorerSearchResult.airport)
            case .airline(let code): Airline.byICAO[code].map(ExplorerSearchResult.airline)
            }
        }.sorted { $0.title < $1.title }
    }

    func toggleSelectedAircraftFavorite() {
        guard let selectedAircraft else { return }
        favorites.toggle(.aircraft(selectedAircraft.icao24))
    }

    func toggleSelectedAirportFavorite() {
        guard let selectedAirport else { return }
        favorites.toggle(.airport(selectedAirport.id))
    }

    func shareURL(for aircraft: Aircraft) -> URL {
        let bounds = currentViewport
        return ExplorerDeepLink.aircraft(
            icao24: aircraft.icao24,
            latitude: bounds?.center.latitude ?? aircraft.coordinate.latitude,
            longitude: bounds?.center.longitude ?? aircraft.coordinate.longitude,
            span: bounds?.latitudeSpan ?? 2
        ).url
    }

    func shareURL(for airport: Airport) -> URL {
        let bounds = currentViewport
        return ExplorerDeepLink.airport(
            id: airport.id,
            latitude: bounds?.center.latitude ?? airport.latitude,
            longitude: bounds?.center.longitude ?? airport.longitude,
            span: bounds?.latitudeSpan ?? 1
        ).url
    }

    func handle(url: URL) async {
        guard let link = ExplorerDeepLink(url: url) else { return }
        switch link {
        case .aircraft(let icao24, let latitude, let longitude, let span):
            if let aircraft = aircraft.first(where: { $0.icao24.caseInsensitiveCompare(icao24) == .orderedSame }) {
                select(aircraft)
            } else if let aircraft = try? await pollingService.fetchAircraft(icao24: icao24) {
                select(aircraft)
            } else {
                pendingAircraftICAO24 = icao24.lowercased()
            }
            cameraRequest = MapCameraRequest(coordinate: .init(latitude: latitude, longitude: longitude), latitudeSpan: span)
        case .airport(let id, let latitude, let longitude, let span):
            if allAirportsByID.isEmpty { await loadStaticExplorerData() }
            if let airport = allAirportsByID[id.uppercased()] { selectAirport(airport) }
            cameraRequest = MapCameraRequest(coordinate: .init(latitude: latitude, longitude: longitude), latitudeSpan: span)
        }
    }

    func toggleFollow() { isFollowingSelectedAircraft.toggle() }
    func toggleTrail() { showsSelectedTrail.toggle() }
    func cancelFollowForManualCamera() { isFollowingSelectedAircraft = false }

    func updateRenderedSelection(_ aircraft: Aircraft) {
        guard selectedAircraft?.icao24 == aircraft.icao24 else { return }
        selectedAircraft = aircraft
    }

    func retry() async {
        guard let currentViewport else { return }
        await pollingService.setViewport(currentViewport)
    }

    private func apply(_ snapshot: AircraftSnapshot) {
        let now = Date()
        var refreshed: [Aircraft] = snapshot.aircraft.compactMap { aircraft in
            var aircraft = aircraft
            aircraft.freshness = aircraft.freshness(
                at: now,
                staleThreshold: configuration.staleThreshold,
                removalThreshold: configuration.removalThreshold
            )
            if snapshot.isStale, aircraft.freshness == .fresh {
                aircraft.freshness = .stale
            }
            return aircraft.freshness == .expired ? nil : aircraft
        }

        if var selection = selectedAircraft {
            if let updated = refreshed.first(where: { $0.icao24 == selection.icao24 }) {
                selectedAircraft = updated
            } else {
                selection.freshness = selection.freshness(
                    at: now,
                    staleThreshold: configuration.staleThreshold,
                    removalThreshold: configuration.removalThreshold
                )
                if selection.freshness == .expired {
                    selectedAircraft = nil
                } else {
                    selection.freshness = .stale
                    selectedAircraft = selection
                    refreshed.append(selection)
                }
            }
        }

        aircraft = refreshed
        if let pendingAircraftICAO24,
           let linkedAircraft = refreshed.first(where: { $0.icao24.lowercased() == pendingAircraftICAO24 }) {
            self.pendingAircraftICAO24 = nil
            select(linkedAircraft)
        }
        applyFilters()
        Task { [searchIndex] in await searchIndex.replace(scope: .aircraft, with: refreshed.map(SearchDocument.aircraft)) }
        lastUpdateTime = snapshot.fetchTimestamp
        isShowingStaleData = snapshot.isStale
        loadState = .loaded
    }

    private func applyFilters() { displayedAircraft = aircraft.filter(filter.includes) }

    private func loadStaticExplorerData() async {
        guard allAirportsByID.isEmpty else { return }
        airportLoadState = .loading
        do {
            let loaded = try await airportDatabase.load()
            allAirportsByID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            airportLoadState = .loaded(loaded.count)
            if !searchQuery.isEmpty { Task { [weak self] in await self?.performSearch() } }
            try? await Task.sleep(for: .seconds(1))
            await searchIndex.replace(scope: .airline, with: Airline.builtIn.map(SearchDocument.airline))
            await searchIndex.replace(scope: .airport, with: loaded.map(SearchDocument.airport))
            if let currentViewport { await refreshVisibleAirports(in: currentViewport) }
        } catch {
            airportLoadState = .failed(error.localizedDescription)
        }
    }

    private func refreshVisibleAirports(in bounds: MapBounds) async {
        guard bounds.latitudeSpan <= 12, bounds.longitudeSpan <= 18 else {
            airports = []
            return
        }
        airports = await airportDatabase.airports(in: bounds)
    }

    private func recordRecentSearch(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        recentSearches.insert(query, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
    }

    private static func sameViewport(_ lhs: MapBounds, _ rhs: MapBounds) -> Bool {
        abs(lhs.center.latitude - rhs.center.latitude) < 0.001
            && abs(lhs.center.longitude - rhs.center.longitude) < 0.001
            && abs(lhs.latitudeSpan - rhs.latitudeSpan) < 0.001
            && abs(lhs.longitudeSpan - rhs.longitudeSpan) < 0.001
    }

    private static func looksLikeICAO24(_ query: String) -> Bool {
        query.count == 6 && query.allSatisfy { $0.isHexDigit }
    }

    private func apply(_ status: ProviderStatus) {
        providerStatus = status
        switch status {
        case .loading:
            if aircraft.isEmpty { loadState = .loading }
        case .failed(let message):
            if aircraft.isEmpty { loadState = .failed(message) }
        case .offline:
            if aircraft.isEmpty { loadState = .failed("No network connection.") }
        case .rateLimited:
            if aircraft.isEmpty { loadState = .failed("The aircraft provider is rate limited.") }
        case .idle, .live, .stale, .partial, .viewportTooLarge:
            if !aircraft.isEmpty || status == .viewportTooLarge { loadState = .loaded }
        }
    }
}
