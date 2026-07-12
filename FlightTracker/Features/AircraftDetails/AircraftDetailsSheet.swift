import SwiftUI
import UIKit

struct AircraftDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let aircraft: Aircraft
    let isFollowing: Bool
    let showsTrail: Bool
    let isFavorite: Bool
    let shareURL: URL
    let onToggleFollow: () -> Void
    let onToggleTrail: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section { header; actions }
                Section("Flight") {
                    row("Callsign", aircraft.callsign ?? "—")
                    row("Flight number", aircraft.flightNumber ?? "—")
                    row("Airline", aircraft.airline?.name ?? "—")
                }
                Section("Aircraft") {
                    row("Registration", aircraft.registration ?? "—")
                    row("Model", aircraft.model ?? "—")
                    row("Manufacturer", aircraft.manufacturer ?? "—")
                    row("ICAO24 / hex", (aircraft.hexCode ?? aircraft.icao24).uppercased())
                    row("Type", aircraft.aircraftType.title)
                    row("Operator", aircraft.operatorName ?? "—")
                    row("Wake category", aircraft.wakeCategory.title)
                    row("Engines", engineDescription)
                }
                Section("Position") {
                    row("Altitude", altitude)
                    row("Ground speed", speed)
                    row("Heading", heading)
                    row("Vertical speed", verticalRate)
                    row("Coordinates", String(format: "%.4f, %.4f", aircraft.coordinate.latitude, aircraft.coordinate.longitude))
                }
                Section("Status") {
                    row("Last update", aircraft.lastContact.formatted(date: .abbreviated, time: .standard))
                    row("Source", aircraft.dataSource)
                    row("Freshness", aircraft.freshness.title)
                    row("Country", aircraft.originCountry ?? "—")
                    row("Squawk", aircraft.squawk ?? "—")
                }
            }
            .navigationTitle("Aircraft details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(isFavorite ? "Remove favorite" : "Favorite", systemImage: isFavorite ? "star.fill" : "star", action: onToggleFavorite)
                        .accessibilityIdentifier("favorite-aircraft")
                    ShareLink(item: shareURL) { Label("Share aircraft", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("share-aircraft")
                    Button {
                        UIPasteboard.general.string = aircraft.icao24.uppercased()
                    } label: { Label("Copy ICAO24", systemImage: "doc.on.doc") }
                    .accessibilityIdentifier("copy-icao24")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("close-details")
                }
            }
        }
        .accessibilityIdentifier("aircraft-details-sheet")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(aircraft.callsign ?? aircraft.registration ?? "Unknown callsign")
                    .font(.largeTitle.bold()).accessibilityIdentifier("details-callsign")
                Text([aircraft.flightNumber, aircraft.registration, aircraft.icao24.uppercased()].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if aircraft.isStale {
                Label("Stale", systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
        }.padding(.vertical, 4)
    }

    private var actions: some View {
        HStack {
            Button(action: onToggleFollow) {
                Label(isFollowing ? "Stop Following" : "Follow", systemImage: isFollowing ? "location.slash" : "location.fill")
            }
            .buttonStyle(.borderedProminent).accessibilityIdentifier("follow-aircraft")
            Button(action: onToggleTrail) {
                Label(showsTrail ? "Hide Trail" : "Show Trail", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .buttonStyle(.bordered).accessibilityIdentifier("toggle-trail")
        }.padding(.vertical, 4)
    }

    private func row(_ title: String, _ value: String) -> some View { LabeledContent(title, value: value) }

    private var altitude: String {
        aircraft.barometricAltitudeMeters.map { "\(Int(($0 * 3.28084).rounded()).formatted()) ft" } ?? "—"
    }

    private var speed: String {
        aircraft.groundSpeedMetersPerSecond.map { "\(Int(($0 * 1.94384).rounded()).formatted()) kt" } ?? "—"
    }

    private var heading: String { aircraft.headingDegrees.map { "\(Int($0.rounded()))°" } ?? "—" }

    private var verticalRate: String {
        aircraft.verticalRateMetersPerSecond.map {
            "\(Int(($0 * 196.85).rounded()).formatted(.number.sign(strategy: .always()))) ft/min"
        } ?? "—"
    }

    private var engineDescription: String {
        let type = aircraft.engineType.title
        return aircraft.engineCount.map { "\($0) × \(type)" } ?? type
    }
}

private extension AircraftFreshness {
    var title: String {
        switch self { case .fresh: "Fresh"; case .stale: "Stale"; case .expired: "Expired" }
    }
}
