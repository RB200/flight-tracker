import SwiftUI

struct AirportDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let airport: Airport
    let isFavorite: Bool
    let shareURL: URL
    let onToggleFavorite: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(airport.name).font(.title2.bold())
                        Text([airport.iata, airport.icao].compactMap { $0 }.joined(separator: " · "))
                            .font(.body.monospaced()).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
                Section("Airport") {
                    row("Country", airport.country)
                    row("City", airport.city ?? "—")
                    row("Elevation", airport.elevationFeet.map { "\($0.formatted()) ft" } ?? "—")
                    row("Coordinates", String(format: "%.4f, %.4f", airport.latitude, airport.longitude))
                    row("Timezone", airport.timezone)
                }
                Section("Runways") {
                    row("Runway count", airport.runways.count.formatted())
                    ForEach(airport.runways, id: \.self) { runway in
                        row(runway.name, "\(runway.lengthFeet.formatted()) ft\(runway.surface.map { " · \($0)" } ?? "")")
                    }
                }
                Section("Coming later") {
                    Label("Arrivals", systemImage: "airplane.arrival").foregroundStyle(.secondary)
                    Label("Departures", systemImage: "airplane.departure").foregroundStyle(.secondary)
                    Label("Weather", systemImage: "cloud.sun").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(airport.displayCode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(isFavorite ? "Remove favorite" : "Favorite", systemImage: isFavorite ? "star.fill" : "star", action: onToggleFavorite)
                    ShareLink(item: shareURL) { Label("Share airport", systemImage: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("close-airport-details") }
            }
        }
        .accessibilityIdentifier("airport-details-sheet")
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }
}
