import SwiftUI

struct AircraftFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: AircraftFilter
    let aircraft: [Aircraft]

    var body: some View {
        NavigationStack {
            Form {
                numericSection("Altitude", unit: "ft", lower: $filter.minimumAltitudeFeet, upper: $filter.maximumAltitudeFeet, range: 0...60_000, step: 1_000)
                numericSection("Speed", unit: "kt", lower: $filter.minimumSpeedKnots, upper: $filter.maximumSpeedKnots, range: 0...800, step: 25)
                Section("Status") {
                    Picker("Ground or airborne", selection: $filter.airborne) {
                        Text("All").tag(Bool?.none)
                        Text("Airborne").tag(Bool?.some(true))
                        Text("On ground").tag(Bool?.some(false))
                    }
                    Picker("Freshness", selection: $filter.freshness) {
                        Text("All").tag(AircraftFreshness?.none)
                        Text("Fresh").tag(AircraftFreshness?.some(.fresh))
                        Text("Stale").tag(AircraftFreshness?.some(.stale))
                    }
                }
                selectionSection("Aircraft type", values: AircraftType.allCases.filter { $0 != .unknown }, selected: $filter.aircraftTypes, title: \.title)
                selectionSection("Wake category", values: WakeCategory.allCases.filter { $0 != .unknown }, selected: $filter.wakeCategories, title: \.title)
                selectionSection("Engine type", values: EngineType.allCases.filter { $0 != .unknown }, selected: $filter.engineTypes, title: \.title)
                stringSelectionSection("Airline", values: Set(aircraft.compactMap { $0.airline?.icao }).sorted(), selected: $filter.airlineICAOs)
                stringSelectionSection("Country", values: Set(aircraft.compactMap(\.originCountry)).sorted(), selected: $filter.countries)
                stringSelectionSection("Operator", values: Set(aircraft.compactMap(\.operatorName)).sorted(), selected: $filter.operators)
            }
            .navigationTitle("Aircraft filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Reset") { filter = AircraftFilter() }.accessibilityIdentifier("reset-filters") }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("close-filters") }
            }
        }
        .accessibilityIdentifier("aircraft-filter-sheet")
    }

    private func numericSection(_ title: String, unit: String, lower: Binding<Double?>, upper: Binding<Double?>, range: ClosedRange<Double>, step: Double) -> some View {
        Section(title) {
            Toggle("Set minimum", isOn: optionalEnabled(lower, defaultValue: range.lowerBound))
            if let value = lower.wrappedValue {
                Slider(value: Binding(get: { value }, set: { lower.wrappedValue = $0 }), in: range, step: step)
                Text("Minimum: \(Int(value)) \(unit)").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Set maximum", isOn: optionalEnabled(upper, defaultValue: range.upperBound))
            if let value = upper.wrappedValue {
                Slider(value: Binding(get: { value }, set: { upper.wrappedValue = $0 }), in: range, step: step)
                Text("Maximum: \(Int(value)) \(unit)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func optionalEnabled(_ value: Binding<Double?>, defaultValue: Double) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { value.wrappedValue = $0 ? defaultValue : nil })
    }

    private func selectionSection<Value: Hashable>(_ title: String, values: [Value], selected: Binding<Set<Value>>, title titleKeyPath: KeyPath<Value, String>) -> some View {
        Section(title) {
            ForEach(values, id: \.self) { value in
                Toggle(value[keyPath: titleKeyPath], isOn: membership(value, in: selected))
            }
        }
    }

    private func stringSelectionSection(_ title: String, values: [String], selected: Binding<Set<String>>) -> some View {
        Section(title) {
            if values.isEmpty { Text("No metadata available").foregroundStyle(.secondary) }
            ForEach(values, id: \.self) { value in Toggle(value, isOn: membership(value, in: selected)) }
        }
    }

    private func membership<Value: Hashable>(_ value: Value, in selected: Binding<Set<Value>>) -> Binding<Bool> {
        Binding(get: { selected.wrappedValue.contains(value) }, set: { enabled in
            if enabled { selected.wrappedValue.insert(value) } else { selected.wrappedValue.remove(value) }
        })
    }
}
