import Foundation

// MARK: - Saved places (v1.7)
//
// Jeffery's own places — the hotel, a market, a friend's flat — saved by
// name with coordinates, so the app never has to ask TfL to guess what a
// name means. A place plans from its coordinates (like a pub), so there is
// no fuzzy name lookup and no "did you mean?" for it. `nearestStationId`
// is the station TfL walks to from the door (the Wilde's is Edgware Road
// Bakerloo) — for the ME it is the nearest Tube station a person would
// walk to (Charing Cross), since TfL walks to the Aldwych bus stop first.
// Since v1.9 it is computed from the coordinates when a place is saved
// (Add a place) and backfilled for older places on launch; before v1.9
// it was nil for places added in the app.
//
// The hotel is seeded on first launch. It is a normal saved place after
// that — it can be removed in its sheet, and re-added with Add a place.

struct SavedPlace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var address: String
    var lat: Double
    var lon: Double
    var nearestStationId: String? = nil
    var isBuiltIn: Bool = false
}

enum PlacesData {
    // Wilde Aparthotels London Paddington — Jeffery's hotel for the
    // Dec 15–24, 2026 trip (reservation 596102403, check-in Dec 14).
    // Address verified against wilde.com and booking listings, Nov 2026:
    // 4 North Wharf Road, London W2 1NW — "North Wharf Road", which is
    // what his "I think it's for North" was. Coordinates from wilde.com
    // (51.519587, -0.173325); TfL resolves them to "2 NORTH WHARF ROAD"
    // and walks to Edgware Road (Bakerloo) — a shorter walk than
    // Paddington, so that is the nearest station recorded here.
    // Do NOT use the name for this place: TfL's name lookup for
    // "Wilde Aparthotels London Paddington" silently resolves to the
    // Covent Garden Wilde (checked live, 19 Nov 2026), and shorter
    // wordings ("Wilde", "Wilde Paddington") come back ambiguous.
    static let builtInPlaces: [SavedPlace] = [
        SavedPlace(
            name: "Wilde Aparthotels London Paddington",
            address: "4 North Wharf Road, London W2 1NW",
            lat: 51.519587,
            lon: -0.173325,
            nearestStationId: "940GZZLUERB",
            isBuiltIn: true
        ),
        // ME London — the hotel on the Strand where a friend of Jeffery's
        // is staying for the Dec 2026 trip. Address and coordinates from
        // OpenStreetMap/Nominatim, 19 Nov 2026: "Me London, 336-337,
        // Strand … WC2R 1HH" at 51.5117614, -0.1185737. TfL does not
        // resolve "ME Hotel" to this hotel at all, and "me hotel, london"
        // silently resolves to the Radisson Blu Mercer Street in Seven
        // Dials (checked live, 19 Nov 2026) — so it is saved as a place
        // and plans from coordinates, like the Wilde. Nearest Tube
        // station: Charing Cross (940GZZLUCHX), a 3-minute walk; TfL's
        // own routing from the door walks to the Aldwych bus stop first.
        SavedPlace(
            name: "ME London",
            address: "336-337 Strand, London WC2R 1HH",
            lat: 51.5117614,
            lon: -0.1185737,
            nearestStationId: "940GZZLUCHX",
            isBuiltIn: true
        )
    ]
}

// MARK: - TfL disambiguation (v1.7)
//
// When a place name matches more than one place, TfL answers the Journey
// endpoint with HTTP 300 and a DisambiguationResult instead of journeys:
// "which one did you mean?" Before v1.7 the app only accepted a 200 and
// reported anything else as a connection failure (NSURLErrorDomain -1011),
// which is what Jeffery saw searching for the hotel. The 300 body lists
// the options with a parameterValue — coordinates ("51.51...,-0.17...") or
// a stop-point ICS code ("1000175") — that can be fed straight back into
// the Journey endpoint as the from/to.

struct DisambiguationResponse: Decodable {
    let fromLocationDisambiguation: Disambiguation?
    let toLocationDisambiguation: Disambiguation?
}

struct Disambiguation: Decodable {
    let disambiguationOptions: [DisambiguationOption]?
}

struct DisambiguationOption: Decodable {
    let parameterValue: String
    let place: DisambiguationPlace?
}

struct DisambiguationPlace: Decodable {
    let commonName: String?
}

// One "did you mean…?" choice, for the From or the To side.
struct DisambiguationChoice: Identifiable {
    var id: String { side + "|" + apiId }
    let side: String   // "From" or "To"
    let apiId: String  // parameterValue — coordinates or ICS code
    let name: String   // the place's common name
}

struct DisambiguationOffer: Identifiable {
    var id = UUID()
    var options: [DisambiguationChoice]
}
