import Foundation

struct SearchDocument: Sendable {
    enum Scope: Hashable, Sendable { case aircraft, airport, airline }

    let id: String
    let scope: Scope
    let terms: [String]
    let result: ExplorerSearchResult
}

struct RankedSearchResult: Identifiable, Sendable {
    let result: ExplorerSearchResult
    let score: Int
    var id: String { result.id }
}

actor InMemorySearchIndex {
    private var documents: [String: SearchDocument] = [:]
    private var idsByScope: [SearchDocument.Scope: Set<String>] = [:]
    private var exactIndex: [String: Set<String>] = [:]
    private var prefixIndex: [String: Set<String>] = [:]

    func replace(scope: SearchDocument.Scope, with newDocuments: [SearchDocument]) {
        for id in idsByScope[scope] ?? [] { removeDocument(id: id) }
        idsByScope[scope] = []
        for document in newDocuments {
            documents[document.id] = document
            idsByScope[scope, default: []].insert(document.id)
            for term in normalizedTerms(document.terms) {
                exactIndex[term, default: []].insert(document.id)
                for prefix in prefixes(of: term) { prefixIndex[prefix, default: []].insert(document.id) }
            }
        }
    }

    func search(_ query: String, favoriteIDs: Set<FavoriteID> = [], limit: Int = 30) -> [RankedSearchResult] {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty else { return [] }
        var candidates = exactIndex[normalized] ?? []
        candidates.formUnion(prefixIndex[normalized] ?? [])
        let queryTokens = normalized.split(separator: " ").map(String.init)
        for token in queryTokens {
            var tokenCandidates = exactIndex[token] ?? []
            tokenCandidates.formUnion(prefixIndex[token] ?? [])
            if candidates.isEmpty { candidates = tokenCandidates }
            else { candidates.formIntersection(tokenCandidates) }
        }

        if candidates.isEmpty {
            let leading = String(normalized.prefix(1))
            candidates.formUnion(prefixIndex[leading] ?? [])
        }

        return candidates.compactMap { id -> RankedSearchResult? in
            guard let document = documents[id] else { return nil }
            let terms = normalizedTerms(document.terms)
            var score = terms.reduce(0) { max($0, Self.score(query: normalized, against: $1)) }
            guard score > 0 else { return nil }
            if favoriteIDs.contains(document.result.favoriteID) { score += 75 }
            return RankedSearchResult(result: document.result, score: score)
        }
        .sorted {
            if $0.score == $1.score { return $0.result.title.localizedCaseInsensitiveCompare($1.result.title) == .orderedAscending }
            return $0.score > $1.score
        }
        .prefix(limit)
        .map { $0 }
    }

    func suggestions(for query: String, limit: Int = 5) -> [String] {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty else { return [] }
        let ids = prefixIndex[normalized] ?? []
        return ids.compactMap { documents[$0]?.result.title }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .prefix(limit)
            .map { $0 }
    }

    func documentCount() -> Int { documents.count }

    private func removeDocument(id: String) {
        guard let document = documents.removeValue(forKey: id) else { return }
        for term in normalizedTerms(document.terms) {
            exactIndex[term]?.remove(id)
            if exactIndex[term]?.isEmpty == true { exactIndex[term] = nil }
            for prefix in prefixes(of: term) {
                prefixIndex[prefix]?.remove(id)
                if prefixIndex[prefix]?.isEmpty == true { prefixIndex[prefix] = nil }
            }
        }
    }

    private func normalizedTerms(_ terms: [String]) -> [String] {
        Set(terms.flatMap { term in
            let normalized = Self.normalize(term)
            return [normalized] + normalized.split(separator: " ").map(String.init)
        }.filter { !$0.isEmpty }).map { $0 }
    }

    private func prefixes(of term: String) -> [String] {
        guard !term.isEmpty else { return [] }
        return (1...min(term.count, 10)).map { String(term.prefix($0)) }
    }

    private static func score(query: String, against term: String) -> Int {
        if query == term { return 1_000 }
        if term.hasPrefix(query) { return 800 - min(term.count - query.count, 100) }
        if term.contains(query) { return 600 - min(term.count - query.count, 100) }
        let distance = levenshtein(query, term)
        let tolerance = query.count < 5 ? 1 : 2
        return distance <= tolerance ? 450 - distance * 50 : 0
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var current = [i + 1]
            for (j, right) in b.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}

extension SearchDocument {
    static func aircraft(_ aircraft: Aircraft) -> SearchDocument {
        SearchDocument(
            id: "aircraft:\(aircraft.icao24)",
            scope: .aircraft,
            terms: [aircraft.callsign, aircraft.flightNumber, aircraft.icao24, aircraft.registration, aircraft.airline?.name, aircraft.airline?.icao, aircraft.operatorName].compactMap { $0 },
            result: .aircraft(aircraft)
        )
    }

    static func airport(_ airport: Airport) -> SearchDocument {
        SearchDocument(
            id: "airport:\(airport.id)",
            scope: .airport,
            terms: [airport.icao, airport.iata, airport.name].compactMap { $0 },
            result: .airport(airport)
        )
    }

    static func airline(_ airline: Airline) -> SearchDocument {
        SearchDocument(
            id: "airline:\(airline.icao)",
            scope: .airline,
            terms: [airline.icao, airline.iata, airline.name, airline.country, airline.callsign].compactMap { $0 },
            result: .airline(airline)
        )
    }
}
