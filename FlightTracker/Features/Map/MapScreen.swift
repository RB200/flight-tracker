import SwiftUI

struct MapScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: AircraftMapViewModel
    private let requestConfiguration: AircraftRequestConfiguration
    private let motionEnabled: Bool

    init(
        pollingService: AircraftPollingService,
        requestConfiguration: AircraftRequestConfiguration = AircraftRequestConfiguration(),
        airportDatabase: AirportDatabase = AirportDatabase(),
        searchIndex: InMemorySearchIndex = InMemorySearchIndex()
    ) {
        self.requestConfiguration = requestConfiguration
        motionEnabled = !ProcessInfo.processInfo.arguments.contains("-UITestDisableMotion")
        _viewModel = State(initialValue: AircraftMapViewModel(
            pollingService: pollingService,
            configuration: requestConfiguration,
            airportDatabase: airportDatabase,
            searchIndex: searchIndex
        ))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AircraftMapRepresentable(
                aircraft: viewModel.displayedAircraft,
                airports: viewModel.airports,
                selectedAircraft: viewModel.selectedAircraft,
                selectedAirport: viewModel.selectedAirport,
                cameraRequest: viewModel.cameraRequest,
                onSelection: viewModel.select,
                onAirportSelection: viewModel.selectAirport,
                onViewport: { bounds in
                    Task { await viewModel.setViewport(bounds) }
                },
                requestConfiguration: requestConfiguration,
                followsSelectedAircraft: viewModel.isFollowingSelectedAircraft,
                showsSelectedTrail: viewModel.showsSelectedTrail,
                onRenderedSelection: viewModel.updateRenderedSelection,
                onFollowCancelled: viewModel.cancelFollowForManualCamera,
                motionEnabled: motionEnabled && !reduceMotion
            )
            .ignoresSafeArea()
            .accessibilityIdentifier("aircraft-map")

            VStack(alignment: .leading, spacing: 10) {
                GlobalSearchPanel(
                    query: $viewModel.searchQuery,
                    isExpanded: $viewModel.isSearchExpanded,
                    isLoading: viewModel.isSearching,
                    results: viewModel.searchResults,
                    recentSearches: viewModel.recentSearches,
                    suggestions: viewModel.searchSuggestions,
                    favorites: viewModel.favoriteResults,
                    isFavorite: viewModel.isFavorite,
                    onSelect: viewModel.selectSearchResult,
                    onFavorite: viewModel.toggleFavorite,
                    onSuggestion: viewModel.useSuggestion
                )
                HStack(alignment: .top) {
                    statusOverlay
                    Spacer()
                    Button { viewModel.showFilters() } label: {
                        Label("Filters", systemImage: viewModel.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(width: 46, height: 46)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .accessibilityLabel(viewModel.filter.isActive ? "Aircraft filters, active" : "Aircraft filters")
                    .accessibilityIdentifier("open-filters")
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { disclaimer }
        .task {
            await viewModel.start()
            await viewModel.setApplicationActive(scenePhase == .active)
        }
        .onDisappear {
            Task { await viewModel.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            Task { await viewModel.setApplicationActive(phase == .active) }
        }
        .task(id: viewModel.searchQuery) { await viewModel.performSearch() }
        .onOpenURL { url in Task { await viewModel.handle(url: url) } }
        .sheet(item: $viewModel.presentedSheet) { destination in
            sheetContent(destination)
                .presentationDetents(destination == .filters ? [.medium, .large] : [.height(440), .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var statusOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.aircraft.isEmpty, viewModel.loadState == .loading {
                Label("Loading aircraft…", systemImage: "antenna.radiowaves.left.and.right")
                    .statusCapsule()
                    .accessibilityIdentifier("loading-indicator")
            } else if !viewModel.isViewportTooLarge {
                HStack(spacing: 8) {
                    Label(aircraftCountText, systemImage: "airplane.circle.fill")
                    if viewModel.isRefreshing { ProgressView().controlSize(.small) }
                }
                .statusCapsule()
                .accessibilityIdentifier("aircraft-count")
            }

            if let message = providerMessage {
                Label(message.text, systemImage: message.icon)
                    .statusCapsule()
                    .accessibilityIdentifier(message.identifier)
            }
            if viewModel.isShowingStaleData, providerMessage?.identifier != "stale-warning" {
                Label("Showing last known aircraft positions.", systemImage: "clock.badge.exclamationmark")
                    .statusCapsule()
                    .accessibilityIdentifier("stale-warning")
            }
        }
    }

    @ViewBuilder private func sheetContent(_ destination: ExplorerSheet) -> some View {
        switch destination {
        case .aircraft:
            if let aircraft = viewModel.selectedAircraft {
                AircraftDetailsSheet(
                    aircraft: aircraft,
                    isFollowing: viewModel.isFollowingSelectedAircraft,
                    showsTrail: viewModel.showsSelectedTrail,
                    isFavorite: viewModel.favorites.contains(.aircraft(aircraft.icao24)),
                    shareURL: viewModel.shareURL(for: aircraft),
                    onToggleFollow: viewModel.toggleFollow,
                    onToggleTrail: viewModel.toggleTrail,
                    onToggleFavorite: viewModel.toggleSelectedAircraftFavorite
                )
            }
        case .airport:
            if let airport = viewModel.selectedAirport {
                AirportDetailsSheet(
                    airport: airport,
                    isFavorite: viewModel.favorites.contains(.airport(airport.id)),
                    shareURL: viewModel.shareURL(for: airport),
                    onToggleFavorite: viewModel.toggleSelectedAirportFavorite
                )
            }
        case .filters:
            AircraftFilterSheet(filter: $viewModel.filter, aircraft: viewModel.aircraft)
        }
    }

    private var aircraftCountText: String {
        if viewModel.filter.isActive { "\(viewModel.displayedAircraft.count) of \(viewModel.aircraft.count) aircraft" }
        else { "\(viewModel.aircraft.count) aircraft" }
    }

    private var providerMessage: (text: String, icon: String, identifier: String)? {
        switch viewModel.providerStatus {
        case .stale:
            ("Showing last known aircraft positions.", "clock.badge.exclamationmark", "stale-warning")
        case .offline:
            ("No network connection.", "wifi.slash", "offline-warning")
        case .rateLimited(let retryAfter):
            (retryAfter.map { "Rate limited. Retry in \(Int($0.rounded(.up))) seconds." } ?? "Provider rate limited.", "hourglass", "rate-limit-warning")
        case .partial:
            ("Some aircraft data could not be loaded.", "circle.lefthalf.filled", "partial-warning")
        case .viewportTooLarge:
            ("Zoom in to view aircraft.", "plus.magnifyingglass", "viewport-too-large-warning")
        case .failed(let message):
            (message, "exclamationmark.triangle", "provider-error")
        case .idle, .loading, .live:
            nil
        }
    }

    private var disclaimer: some View {
        Text("For informational purposes only — not for navigation or collision avoidance.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .accessibilityIdentifier("safety-disclaimer")
    }

}

private extension View {
    func statusCapsule() -> some View {
        font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}
