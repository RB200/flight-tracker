import SwiftUI

struct GlobalSearchPanel: View {
    @Binding var query: String
    @Binding var isExpanded: Bool
    let isLoading: Bool
    let results: [ExplorerSearchResult]
    let recentSearches: [String]
    let suggestions: [String]
    let favorites: [ExplorerSearchResult]
    let isFavorite: (ExplorerSearchResult) -> Bool
    let onSelect: (ExplorerSearchResult) -> Void
    let onFavorite: (ExplorerSearchResult) -> Void
    let onSuggestion: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if isExpanded { resultsPanel }
        }
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .accessibilityElement(children: .contain)
        .onChange(of: query) { _, value in
            if !value.isEmpty { isExpanded = true }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Aircraft, flight, airport, or airline", text: $query)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onTapGesture { isExpanded = true }
                .accessibilityLabel("Global aviation search")
                .accessibilityIdentifier("global-search-field")
            if isLoading { ProgressView().controlSize(.small).accessibilityLabel("Searching") }
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clear-search")
            }
            Button(isExpanded ? "Close search" : "Open search", systemImage: isExpanded ? "chevron.up" : "chevron.down") {
                isExpanded.toggle()
            }
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("toggle-search")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }

    private var resultsPanel: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !favorites.isEmpty { section("Favorites", results: favorites) }
                    if !recentSearches.isEmpty {
                        panelTitle("Recent searches")
                        ForEach(recentSearches, id: \.self) { recent in
                            Button { onSuggestion(recent) } label: {
                                Label(recent, systemImage: "clock.arrow.circlepath")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if favorites.isEmpty, recentSearches.isEmpty {
                        ContentUnavailableView("Explore aviation", systemImage: "airplane.circle", description: Text("Search callsigns, flight numbers, ICAO24 codes, registrations, airlines, and airports."))
                            .padding(.vertical, 24)
                    }
                } else if !results.isEmpty {
                    if !suggestions.isEmpty {
                        panelTitle("Suggestions")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button(suggestion) { onSuggestion(suggestion) }.buttonStyle(.bordered)
                                }
                            }.padding(.horizontal, 14)
                        }.padding(.bottom, 8)
                    }
                    section("Results", results: results)
                } else if !isLoading {
                    ContentUnavailableView.search(text: query).padding(.vertical, 24)
                        .accessibilityIdentifier("search-empty-state")
                }
            }
        }
        .frame(maxHeight: 360)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private func section(_ title: String, results: [ExplorerSearchResult]) -> some View {
        panelTitle(title)
        ForEach(results) { result in
            HStack(spacing: 10) {
                Button { onSelect(result) } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(result.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: result.systemImage).frame(width: 28).foregroundStyle(.blue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search-result-\(result.id)")
                Button(isFavorite(result) ? "Remove favorite" : "Favorite", systemImage: isFavorite(result) ? "star.fill" : "star") {
                    onFavorite(result)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(isFavorite(result) ? .yellow : .secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            Divider().padding(.leading, 52)
        }
    }

    private func panelTitle(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
    }
}
