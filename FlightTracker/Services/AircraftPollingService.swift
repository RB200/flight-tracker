import Foundation
import OSLog

struct PollingRetryPolicy: Sendable, Equatable {
    var maximumRetryCount: Int = 4
    var baseDelay: TimeInterval = 2
    var maximumDelay: TimeInterval = 30

    func delay(forRetry retry: Int) -> TimeInterval {
        min(baseDelay * pow(2, Double(retry)), maximumDelay)
    }
}

actor AircraftPollingService {
    private enum FetchOutcome: Sendable {
        case success(AircraftSnapshot)
        case failure(APIError)
    }

    private let provider: any AircraftProvider
    private let configuration: AircraftRequestConfiguration
    private let retryPolicy: PollingRetryPolicy
    private let sleeper: RetrySleeper
    private let logger = Logger(subsystem: "com.example.FlightTracker", category: "Polling")

    private var loopTask: Task<Void, Never>?
    private var activeFetch: Task<AircraftSnapshot, Error>?
    private var currentRequest: ViewportRequest?
    private var isStarted = false
    private var isApplicationActive = true
    private(set) var latestSnapshot: AircraftSnapshot?
    private var snapshotContinuations: [UUID: AsyncStream<AircraftSnapshot>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<ProviderStatus>.Continuation] = [:]

    init(
        provider: any AircraftProvider,
        configuration: AircraftRequestConfiguration = AircraftRequestConfiguration(),
        retryPolicy: PollingRetryPolicy = PollingRetryPolicy(),
        sleeper: RetrySleeper = .continuousClock
    ) {
        self.provider = provider
        self.configuration = configuration
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
    }

    func start() {
        isStarted = true
        restartLoop()
    }

    func stop() {
        isStarted = false
        cancelTasks()
        publishStatus(.idle)
    }

    func setViewport(_ bounds: MapBounds?) {
        guard let bounds else {
            currentRequest = nil
            cancelTasks()
            publishStatus(.idle)
            return
        }
        guard configuration.accepts(bounds) else {
            currentRequest = nil
            cancelTasks()
            publishStatus(.viewportTooLarge)
            return
        }
        let request = ViewportRequest(bounds: bounds)
        currentRequest = request
        logger.info("Viewport changed: \(request.id.uuidString, privacy: .public), span \(bounds.latitudeSpan)x\(bounds.longitudeSpan)")
        restartLoop()
    }

    func setApplicationActive(_ active: Bool) {
        guard isApplicationActive != active else { return }
        isApplicationActive = active
        if active {
            logger.info("Application active; resuming polling")
            restartLoop()
        } else {
            logger.info("Application inactive; pausing polling")
            cancelTasks()
        }
    }

    func snapshots() -> AsyncStream<AircraftSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            snapshotContinuations[id] = continuation
            if let latestSnapshot { continuation.yield(latestSnapshot) }
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeSnapshotContinuation(id) }
            }
        }
    }

    func statuses() -> AsyncStream<ProviderStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            statusContinuations[id] = continuation
            continuation.yield(.idle)
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeStatusContinuation(id) }
            }
        }
    }

    func fetchSnapshot(in bounds: MapBounds) async throws -> AircraftSnapshot {
        activeFetch?.cancel()
        let task = makeFetchTask(bounds: bounds)
        activeFetch = task
        do {
            let snapshot = try await task.value
            activeFetch = nil
            latestSnapshot = snapshot
            return snapshot
        } catch is CancellationError {
            activeFetch = nil
            throw CancellationError()
        } catch {
            activeFetch = nil
            if let latestSnapshot { return latestSnapshot.markedStale() }
            throw error
        }
    }

    func fetchAircraft(icao24: String) async throws -> Aircraft? {
        try Task.checkCancellation()
        return try await provider.fetchAircraft(icao24: icao24.lowercased())
    }

    func cancel() {
        activeFetch?.cancel()
        activeFetch = nil
    }

    static func merge(_ snapshots: [AircraftSnapshot], partial: Bool) -> AircraftSnapshot? {
        guard let first = snapshots.first else { return nil }
        var aircraftByICAO24: [String: Aircraft] = [:]
        for aircraft in snapshots.flatMap(\.aircraft) {
            if let existing = aircraftByICAO24[aircraft.icao24], existing.lastContact >= aircraft.lastContact {
                continue
            }
            aircraftByICAO24[aircraft.icao24] = aircraft
        }
        return AircraftSnapshot(
            aircraft: aircraftByICAO24.values.sorted { $0.icao24 < $1.icao24 },
            fetchTimestamp: snapshots.map(\.fetchTimestamp).max() ?? first.fetchTimestamp,
            providerName: first.providerName,
            isStale: snapshots.allSatisfy(\.isStale),
            isPartial: partial || snapshots.contains(where: \.isPartial)
        )
    }

    private func restartLoop() {
        cancelTasks()
        guard isStarted, isApplicationActive, let request = currentRequest else { return }
        loopTask = Task { await poll(requestID: request.id) }
    }

    private func cancelTasks() {
        loopTask?.cancel()
        activeFetch?.cancel()
        loopTask = nil
        activeFetch = nil
        logger.debug("Cancelled obsolete polling tasks")
    }

    private func poll(requestID: UUID) async {
        while !Task.isCancelled {
            await fetchAndPublish(requestID: requestID)
            do {
                try await Task.sleep(for: configuration.pollingInterval)
            } catch {
                return
            }
        }
    }

    private func fetchAndPublish(requestID: UUID) async {
        guard let request = currentRequest, request.id == requestID else { return }
        publishStatus(.loading)
        logger.info("Fetch started: \(requestID.uuidString, privacy: .public)")
        let task = makeFetchTask(bounds: request.bounds)
        activeFetch = task

        do {
            let snapshot = try await task.value
            guard !Task.isCancelled,
                  let currentRequest,
                  currentRequest.id == requestID else {
                logger.debug("Ignored obsolete fetch: \(requestID.uuidString, privacy: .public)")
                return
            }
            activeFetch = nil
            latestSnapshot = snapshot
            publishSnapshot(snapshot)
            if snapshot.isPartial {
                publishStatus(.partial(providerName: snapshot.providerName, aircraftCount: snapshot.aircraft.count))
            } else if snapshot.isStale {
                publishStatus(.stale(providerName: snapshot.providerName, updatedAt: snapshot.fetchTimestamp))
            } else {
                publishStatus(.live(
                    providerName: snapshot.providerName,
                    aircraftCount: snapshot.aircraft.count,
                    updatedAt: snapshot.fetchTimestamp
                ))
            }
            logger.info("Fetch completed: \(snapshot.aircraft.count) aircraft")
        } catch is CancellationError {
            logger.debug("Fetch cancelled: \(requestID.uuidString, privacy: .public)")
        } catch {
            activeFetch = nil
            let apiError = (error as? APIError) ?? .unknown(error.localizedDescription)
            if let cached = latestSnapshot?.markedStale() {
                logger.info("Publishing cached snapshot after provider error")
                publishSnapshot(cached)
            }
            publishStatus(Self.status(for: apiError))
            logger.error("Provider error: \(apiError.localizedDescription, privacy: .public)")
        }
    }

    private func makeFetchTask(bounds: MapBounds) -> Task<AircraftSnapshot, Error> {
        let provider = provider
        let retryPolicy = retryPolicy
        let sleeper = sleeper
        return Task {
            let requestBounds = bounds.splitAtAntimeridian()
            let outcomes = await withTaskGroup(of: FetchOutcome.self, returning: [FetchOutcome].self) { group in
                for requestBounds in requestBounds {
                    group.addTask {
                        do {
                            return .success(try await Self.fetch(
                                provider: provider,
                                bounds: requestBounds,
                                retryPolicy: retryPolicy,
                                sleeper: sleeper
                            ))
                        } catch is CancellationError {
                            return .failure(.cancelled)
                        } catch {
                            return .failure((error as? APIError) ?? .unknown(error.localizedDescription))
                        }
                    }
                }
                var results: [FetchOutcome] = []
                for await outcome in group { results.append(outcome) }
                return results
            }
            try Task.checkCancellation()
            let successes = outcomes.compactMap { outcome -> AircraftSnapshot? in
                guard case .success(let snapshot) = outcome else { return nil }
                return snapshot
            }
            guard let merged = Self.merge(successes, partial: successes.count < requestBounds.count) else {
                let failure = outcomes.compactMap { outcome -> APIError? in
                    guard case .failure(let error) = outcome else { return nil }
                    return error
                }.first ?? .unknown("Aircraft request failed.")
                if failure == .cancelled { throw CancellationError() }
                throw failure
            }
            return merged
        }
    }

    private static func fetch(
        provider: any AircraftProvider,
        bounds: MapBounds,
        retryPolicy: PollingRetryPolicy,
        sleeper: RetrySleeper
    ) async throws -> AircraftSnapshot {
        var retry = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await provider.fetchAircraft(in: bounds)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as APIError where error == .cancelled {
                throw CancellationError()
            } catch {
                guard retry < retryPolicy.maximumRetryCount,
                      (error as? APIError)?.isTransient == true else { throw error }
                let apiError = error as? APIError
                let retryAfter: TimeInterval?
                if case .rateLimited(let value) = apiError { retryAfter = value } else { retryAfter = nil }
                let delay = retryAfter ?? retryPolicy.delay(forRetry: retry)
                retry += 1
                try await sleeper.sleep(delay)
            }
        }
    }

    private static func status(for error: APIError) -> ProviderStatus {
        switch error {
        case .offline, .timeout, .transport:
            .offline
        case .rateLimited(let retryAfter):
            .rateLimited(retryAfter: retryAfter)
        default:
            .failed(message: error.localizedDescription)
        }
    }

    private func publishSnapshot(_ snapshot: AircraftSnapshot) {
        for continuation in snapshotContinuations.values { continuation.yield(snapshot) }
    }

    private func publishStatus(_ status: ProviderStatus) {
        for continuation in statusContinuations.values { continuation.yield(status) }
    }

    private func removeSnapshotContinuation(_ id: UUID) {
        snapshotContinuations[id] = nil
    }

    private func removeStatusContinuation(_ id: UUID) {
        statusContinuations[id] = nil
    }
}
