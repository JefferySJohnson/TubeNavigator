import Foundation
import SwiftUI

// TfL Unified API — https://api.tfl.gov.uk
// Free, no key required for personal use (about 50 requests/minute).
// A free app_key from https://api-portal.tfl.gov.uk/ lifts that to 500/min.
// The key is optional and is never committed anywhere; it lives in
// UserDefaults on the phone only, entered in the app's Plan tab.
//
// Planned disruptions use the dated status endpoint:
//   GET /Line/{ids}/Status/{startDate}/to/{endDate}
// which returns future line statuses (strikes, planned closures,
// engineering works) with validity periods. Note: it only works with
// explicit line IDs — the /Line/Mode/... form of that path 404s.

struct JourneyResponse: Decodable {
    let journeys: [Journey]
}

struct Journey: Decodable, Identifiable {
    var id: String { startDateTime + "-" + arrivalDateTime + "-\(duration)" }
    let duration: Int
    let startDateTime: String
    let arrivalDateTime: String
    let legs: [Leg]
}

struct Leg: Decodable, Identifiable {
    var id: String { (departureTime ?? "") + "-" + instruction.summary }
    let duration: Int
    let instruction: Instruction
    let departureTime: String?
    let arrivalTime: String?
    let departurePoint: StopPointRef
    let arrivalPoint: StopPointRef
    let mode: ModeRef
    let routeOptions: [RouteOption]?
}

struct Instruction: Decodable {
    let summary: String
    let detailed: String
}

struct StopPointRef: Decodable {
    let commonName: String
    let lat: Double?
    let lon: Double?
}

struct ModeRef: Decodable {
    let id: String
    let name: String
}

struct RouteOption: Decodable {
    let name: String
    let lineIdentifier: LineIdentifier?
}

struct LineIdentifier: Decodable {
    let id: String
    let name: String
}

struct TfLLine: Decodable, Identifiable {
    let id: String
    let name: String
    let modeName: String?
    let lineStatuses: [LineStatusItem]
}

struct ValidityPeriod: Decodable {
    let fromDate: String
    let toDate: String
    let isNow: Bool
}

struct LineStatusItem: Decodable {
    let statusSeverityDescription: String
    let reason: String?
    let validityPeriods: [ValidityPeriod]?
}

// MARK: - Planned disruptions

enum PlannedRange: String, CaseIterable, Identifiable {
    case next7Days = "Next 7 days"
    case trip = "Trip · Dec 15–24"
    var id: String { rawValue }
}

struct PlannedDisruption: Identifiable {
    // Identical notices (e.g. a network-wide strike) appear on every line,
    // so items are grouped by reason + start date, with all affected lines.
    var id: String { reason + "|" + (fromDate ?? "") }
    let lineNames: [String]
    let severity: String
    let reason: String
    let fromDate: String?
    let toDate: String?

    var displayLines: String {
        if lineNames.count == 1 { return lineNames[0] }
        if lineNames.count >= 10 { return "All Tube lines" }
        return lineNames.joined(separator: ", ")
    }
}

// MARK: - Departure boards (v1.10 — ported from TubeNavigatorTV)

// One prediction from the Arrivals feed. Decoded defensively —
// the feed always carries these fields, but a missing one must not
// kill the whole board. Ported from the TV app (v1.11–v1.16),
// including the v1.16 identity fix: see Arrival.id.
struct Arrival: Decodable, Identifiable {
    let predictionId: String
    let lineId: String
    let lineName: String
    let platformName: String
    let direction: String
    let destinationName: String
    let towards: String
    let stationName: String
    let expectedArrival: String?
    let timeToStation: Int?
    let currentLocation: String
    let modeName: String
    let vehicleId: String
    let timeToLive: String?

    // The ForEach identity — NOT the raw prediction id. The DLR
    // feed gives EVERY row the same prediction id ("-937089209"),
    // so predictionId alone is not a unique identity: SwiftUI's
    // ForEach with duplicate ids repeated each platform section's
    // first train (found on the TV, 23 Nov 2026). The identity is
    // the prediction id plus platform, destination and arrival
    // time, which together name one train on every line. The
    // dedupe in fetchArrivals still keys on predictionId, not on
    // this composite, so its clock-based merging is unchanged.
    var id: String { "\(predictionId)|\(platformName)|\(destinationName)|\(expectedArrival ?? "")" }

    enum CodingKeys: String, CodingKey {
        case predictionId = "id"
        case lineId, lineName, platformName, direction, destinationName, towards, stationName, expectedArrival, timeToStation, currentLocation, modeName, vehicleId, timeToLive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        predictionId = (try? c.decode(String.self, forKey: .predictionId)) ?? UUID().uuidString
        lineId = (try? c.decode(String.self, forKey: .lineId)) ?? ""
        lineName = (try? c.decode(String.self, forKey: .lineName)) ?? ""
        platformName = (try? c.decode(String.self, forKey: .platformName)) ?? "Platform Unknown"
        direction = (try? c.decode(String.self, forKey: .direction)) ?? ""
        destinationName = (try? c.decode(String.self, forKey: .destinationName)) ?? ""
        towards = (try? c.decode(String.self, forKey: .towards)) ?? ""
        stationName = (try? c.decode(String.self, forKey: .stationName)) ?? ""
        expectedArrival = try? c.decode(String.self, forKey: .expectedArrival)
        timeToStation = try? c.decode(Int.self, forKey: .timeToStation)
        currentLocation = (try? c.decode(String.self, forKey: .currentLocation)) ?? ""
        modeName = (try? c.decode(String.self, forKey: .modeName)) ?? ""
        vehicleId = (try? c.decode(String.self, forKey: .vehicleId)) ?? ""
        timeToLive = try? c.decode(String.self, forKey: .timeToLive)
    }
}

// A station on the Boards tab: the TfL stop point id and the lines
// that serve it, in picker order. Most stations answer to one stop
// point; Paddington and Liverpool Street need two (their Tube lines
// answer to the 940GZZLU… id, their Elizabeth line platforms to the
// 910G… rail id), and Canary Wharf needs three (Elizabeth
// 910GCANWHRF, Jubilee 940GZZLUCYF, DLR 940GZZDLCAN). All verified
// live on the TV, 23 Nov 2026.
struct BoardStation: Identifiable, Hashable {
    var id: String { arrivalsId }
    let name: String
    let lines: [String]
    let arrivalsId: String
    let extraArrivalsIds: [String: String]

    func arrivalsId(for lineId: String) -> String {
        extraArrivalsIds[lineId] ?? arrivalsId
    }
}

extension TubeService {
    // The stations Jeffery uses — the main termini, Paddington
    // first, then alphabetical. King's Cross and St Pancras share
    // one Tube station (King's Cross St. Pancras), so they are one
    // entry. Same seven as the TV.
    static let boardStations: [BoardStation] = [
        BoardStation(name: "Paddington", lines: ["elizabeth", "bakerloo", "circle", "district", "hammersmith-city"], arrivalsId: "940GZZLUPAC", extraArrivalsIds: ["elizabeth": "910GPADTON"]),
        BoardStation(name: "Canary Wharf", lines: ["elizabeth", "jubilee", "dlr"], arrivalsId: "940GZZLUCYF", extraArrivalsIds: ["elizabeth": "910GCANWHRF", "dlr": "940GZZDLCAN"]),
        BoardStation(name: "King's Cross St. Pancras", lines: ["circle", "hammersmith-city", "metropolitan", "northern", "piccadilly", "victoria"], arrivalsId: "940GZZLUKSX", extraArrivalsIds: [:]),
        BoardStation(name: "Liverpool Street", lines: ["elizabeth", "central", "circle", "hammersmith-city", "metropolitan"], arrivalsId: "940GZZLULVT", extraArrivalsIds: ["elizabeth": "910GLIVST"]),
        BoardStation(name: "London Bridge", lines: ["jubilee", "northern"], arrivalsId: "940GZZLULNB", extraArrivalsIds: [:]),
        BoardStation(name: "Victoria", lines: ["circle", "district", "victoria"], arrivalsId: "940GZZLUVIC", extraArrivalsIds: [:]),
        BoardStation(name: "Waterloo", lines: ["bakerloo", "jubilee", "northern", "waterloo-city"], arrivalsId: "940GZZLUWLO", extraArrivalsIds: [:]),
    ]
}

// MARK: - Journey endpoint (v1.6, v1.8)

// A journey endpoint: a station, a pub, a saved place, a place found by
// the on-phone lookup, a place picked from TfL's "did you mean…?" list,
// or raw text typed in (postcode / address / place name). `apiId` is what
// goes into the TfL Journey URL — a NaPTAN id, "lat,lon", or the raw text.
// `stationId` is the station the endpoint stands for (itself for a
// station, the nearest station for a pub or a saved place, nil for a raw
// location, a looked-up place or a TfL match), so saved routes and recent
// journeys — which are station pairs — keep working. `kind` is what the
// confirmation line under the From/To field reads: a found place shows
// its address, typed text says it was never looked up.
enum EndpointKind { case station, pub, place, found, resolved, location }

struct Endpoint: Equatable {
    var apiId: String
    var name: String
    var detail: String
    var stationId: String?
    var kind: EndpointKind

    static func station(_ s: Station) -> Endpoint {
        Endpoint(
            apiId: s.id,
            name: s.name,
            detail: s.lineIds.map { TubeLines.name(for: $0) }.joined(separator: " · ") + " — Zone \(s.zone)",
            stationId: s.id,
            kind: .station
        )
    }

    static func pub(_ p: Pub) -> Endpoint {
        Endpoint(
            apiId: "\(p.lat),\(p.lon)",
            name: p.name,
            detail: "Pub · \(p.area)" + (p.distanceText.map { " — \(p.stationName) (\($0))" } ?? ""),
            stationId: p.stationId,
            kind: .pub
        )
    }

    static func location(_ text: String) -> Endpoint {
        Endpoint(apiId: text, name: text, detail: "Not looked up — TfL will guess this place", stationId: nil, kind: .location)
    }

    // v1.7: a saved place — plans from its coordinates, so TfL never has
    // to guess the name. The stationId is the place's recorded nearest
    // station (the hotel's is Edgware Road Bakerloo), if it has one.
    static func place(_ p: SavedPlace) -> Endpoint {
        Endpoint(
            apiId: "\(p.lat),\(p.lon)",
            name: p.name,
            detail: "Your place · \(p.address)",
            stationId: p.nearestStationId,
            kind: .place
        )
    }

    // v1.8: a place found by the on-phone lookup (CLGeocoder) from typed
    // text — plans from its coordinates, so TfL never guesses the name.
    // It is not saved anywhere; a place Jeffery wants to keep goes in
    // with Add a place. No stationId: the nearest station is unknown.
    static func foundPlace(name: String, address: String, lat: Double, lon: Double) -> Endpoint {
        Endpoint(
            apiId: "\(lat),\(lon)",
            name: name,
            detail: "Found place · \(address)",
            stationId: nil,
            kind: .found
        )
    }

    // v1.7: a place picked from TfL's "did you mean…?" list — the apiId is
    // the option's parameterValue (coordinates or an ICS code), the name is
    // the place TfL offered. No stationId: the nearest station is unknown.
    static func resolved(apiId: String, name: String) -> Endpoint {
        Endpoint(apiId: apiId, name: name, detail: "TfL match", stationId: nil, kind: .resolved)
    }
}

// MARK: - Saved routes

struct SavedRoute: Codable, Identifiable {
    var id = UUID()
    var name: String
    var fromId: String
    var toId: String
    var stepFree: Bool = false
    var date: Date? = nil       // nil = plan for right now
    var arriveBy: Bool = false

    var fromStation: Station? { StationData.station(id: fromId) }
    var toStation: Station? { StationData.station(id: toId) }

    var subtitle: String {
        let stations = "\(fromStation?.name ?? "?") → \(toStation?.name ?? "?")"
        guard let date else { return stations }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d MMM HH:mm"
        fmt.locale = Locale(identifier: "en_GB")
        return stations + " · " + (arriveBy ? "Arrive by " : "Leave ") + fmt.string(from: date)
    }
}

// Automatic history of planned journeys (v1.5). Unlike a named saved route,
// a recent journey is recorded on every successful plan and expires by age:
// only the 10 most recent are kept. Tapping one re-plans it live.
struct RecentJourney: Codable, Identifiable {
    var id = UUID()
    var fromId: String
    var toId: String
    var stepFree: Bool = false
    var date: Date? = nil       // nil = planned for right now
    var arriveBy: Bool = false
    var plannedAt: Date = Date()

    var fromStation: Station? { StationData.station(id: fromId) }
    var toStation: Station? { StationData.station(id: toId) }

    var title: String { "\(fromStation?.name ?? "?") → \(toStation?.name ?? "?")" }

    // "Leave Thu 17 Dec 10:00" for a future plan, "Planned Tue 17 Nov 17:47" for now.
    var subtitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d MMM HH:mm"
        fmt.locale = Locale(identifier: "en_GB")
        if let date {
            return (arriveBy ? "Arrive by " : "Leave ") + fmt.string(from: date)
        }
        return "Planned " + fmt.string(from: plannedAt)
    }
}

@MainActor
final class TubeService: ObservableObject {
    // v1.9: changing either endpoint clears the shown journeys — the
    // "Journeys — now" list belongs to the pair that was planned, and
    // leaving it up after From/To changes shows the old pair's results
    // as if they were the new one's. planJourney() repopulates it.
    // (didSet does not fire during init, so the defaults are safe.)
    @Published var fromEndpoint: Endpoint? = StationData.station(id: "940GZZLUPAC").map(Endpoint.station) {
        didSet { journeys = [] }
    } // Paddington
    @Published var toEndpoint: Endpoint? = StationData.station(id: "940GZZLULNB").map(Endpoint.station) {
        didSet { journeys = [] }
    } // London Bridge
    @Published var stepFree = false

    // Plan for a later time (Leave at / Arrive by). Off = right now.
    @Published var useFutureTime = false
    @Published var futureDate = TubeService.defaultFutureDate()
    @Published var arriveBy = false

    static func defaultFutureDate() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    @Published var journeys: [Journey] = []
    @Published var isPlanning = false
    @Published var planError: String?

    // v1.7: TfL's "did you mean…?" answer (HTTP 300) — options for the
    // From and/or To side, shown in the Plan tab until one is picked.
    @Published var disambiguation: DisambiguationOffer?

    @Published var lineStatuses: [TfLLine] = []
    @Published var isLoadingStatus = false
    @Published var statusError: String?
    @Published var lastStatusUpdate: Date?

    @Published var plannedItems: [PlannedDisruption] = []
    @Published var isLoadingPlanned = false
    @Published var plannedError: String?
    @Published var plannedRange: PlannedRange = .trip
    @Published var lastPlannedUpdate: Date?

    @Published var favouriteIds: [String] {
        didSet { UserDefaults.standard.set(favouriteIds, forKey: "TubeNavigator.favourites") }
    }

    @Published var savedRoutes: [SavedRoute] {
        didSet { saveRoutesToDefaults() }
    }

    @Published var recentJourneys: [RecentJourney] {
        didSet { saveRecentToDefaults() }
    }

    // v1.7: Jeffery's saved places (the hotel is seeded on first launch)
    // and his favourite pubs (by catalogue sourceId).
    @Published var savedPlaces: [SavedPlace] {
        didSet { savePlacesToDefaults() }
    }

    @Published var favouritePubIds: [String] {
        didSet { UserDefaults.standard.set(favouritePubIds, forKey: "TubeNavigator.favouritePubs") }
    }

    // App accent colour (hex). Default Tube red; pick a line colour or Crimson.
    @AppStorage("TubeNavigator.accentHex") var accentHex = "DC241F"

    var accentColor: Color { Color(hex: accentHex) }

    static let accentOptions: [(name: String, hex: String)] = [
        ("Tube red", "DC241F"),
        ("Bakerloo", "894E24"),
        ("Circle", "FFCE00"),
        ("District", "007229"),
        ("Hammersmith & City", "D799AF"),
        ("Jubilee", "868F98"),
        ("Metropolitan", "751056"),
        ("Northern", "000000"),
        ("Piccadilly", "0019A8"),
        ("Victoria", "00A0E2"),
        ("Waterloo & City", "76D0BD"),
        ("DLR", "00AFAD"),
        ("Elizabeth line", "9364CD"),
        ("Crimson (Roll Tide)", "9E1B32"),
    ]

    @AppStorage("TubeNavigator.tflAppKey") var tflAppKey = ""

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "TubeNavigator.favourites")
        if let saved, !saved.isEmpty {
            favouriteIds = saved
        } else {
            favouriteIds = StationData.defaultFavouriteIds
        }
        if let data = UserDefaults.standard.data(forKey: "TubeNavigator.savedRoutes"),
           let decoded = try? JSONDecoder().decode([SavedRoute].self, from: data) {
            savedRoutes = decoded
        } else {
            savedRoutes = []
        }
        if let data = UserDefaults.standard.data(forKey: "TubeNavigator.recentJourneys"),
           let decoded = try? JSONDecoder().decode([RecentJourney].self, from: data) {
            recentJourneys = decoded
        } else {
            recentJourneys = []
        }
        if let data = UserDefaults.standard.data(forKey: "TubeNavigator.savedPlaces"),
           let decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            savedPlaces = decoded
        } else {
            // First launch: seed with the built-in places (the hotel).
            savedPlaces = PlacesData.builtInPlaces
        }
        favouritePubIds = UserDefaults.standard.stringArray(forKey: "TubeNavigator.favouritePubs") ?? []
        // v1.8: a new built-in place (ME London) has to reach installs
        // that already seeded, too — the first-launch path above only
        // runs once. This runs at the end of init, once every stored
        // property is set, because it touches `self`. Track seeded
        // built-ins by name, so a place Jeffery deliberately removed
        // stays removed: its name is already in the seeded set, so it
        // is not re-added. (On the v1.8 upgrade launch the set is
        // empty, so a place removed under v1.7 is re-added once —
        // after that, removal sticks.)
        var seededBuiltIns = Set(UserDefaults.standard.stringArray(forKey: "TubeNavigator.seededBuiltInPlaces") ?? [])
        for builtIn in PlacesData.builtInPlaces where !seededBuiltIns.contains(builtIn.name) {
            if !savedPlaces.contains(where: { $0.name == builtIn.name }) {
                savedPlaces.append(builtIn)
            }
            seededBuiltIns.insert(builtIn.name)
        }
        UserDefaults.standard.set(Array(seededBuiltIns), forKey: "TubeNavigator.seededBuiltInPlaces")
        // v1.9: places saved before v1.9 (e.g. Dishoom, added 19 Nov 2026)
        // have no nearest station — Add a place never recorded one. Fill
        // it in from the saved coordinates, so they record in Recent and
        // can be saved as routes like the built-ins.
        for i in savedPlaces.indices where savedPlaces[i].nearestStationId == nil {
            savedPlaces[i].nearestStationId = StationData.nearestStation(lat: savedPlaces[i].lat, lon: savedPlaces[i].lon)?.id
        }
        savePlacesToDefaults()
    }

    private func savePlacesToDefaults() {
        if let data = try? JSONEncoder().encode(savedPlaces) {
            UserDefaults.standard.set(data, forKey: "TubeNavigator.savedPlaces")
        }
    }

    func addPlace(_ place: SavedPlace) {
        savedPlaces.append(place)
    }

    func removePlace(_ place: SavedPlace) {
        savedPlaces.removeAll { $0.id == place.id }
    }

    func isFavouritePub(_ pub: Pub) -> Bool {
        favouritePubIds.contains(pub.sourceId)
    }

    func toggleFavouritePub(_ pub: Pub) {
        if favouritePubIds.contains(pub.sourceId) {
            favouritePubIds.removeAll { $0 == pub.sourceId }
        } else {
            favouritePubIds.append(pub.sourceId)
        }
    }

    var favouritePubs: [Pub] {
        favouritePubIds.compactMap { id in PubData.all.first { $0.sourceId == id } }
            .sorted { $0.name < $1.name }
    }

    // Use a "did you mean…?" choice as the From or To endpoint. The caller
    // re-plans after this returns.
    func applyDisambiguation(_ choice: DisambiguationChoice) {
        let endpoint = Endpoint.resolved(apiId: choice.apiId, name: choice.name)
        if choice.side == "From" {
            fromEndpoint = endpoint
        } else {
            toEndpoint = endpoint
        }
        disambiguation = nil
    }

    private func saveRoutesToDefaults() {
        if let data = try? JSONEncoder().encode(savedRoutes) {
            UserDefaults.standard.set(data, forKey: "TubeNavigator.savedRoutes")
        }
    }

    private func saveRecentToDefaults() {
        if let data = try? JSONEncoder().encode(recentJourneys) {
            UserDefaults.standard.set(data, forKey: "TubeNavigator.recentJourneys")
        }
    }

    // Record the just-planned journey at the top of Recent. An identical trip
    // already in the list is moved up (dropped, then re-inserted) rather than
    // duplicated — re-planning a recent journey just refreshes its time.
    // A pub records as its nearest station; a raw location has no station
    // to record, so it is not added to Recent.
    func recordRecentJourney() {
        guard let fromId = fromEndpoint?.stationId, let toId = toEndpoint?.stationId else { return }
        let entry = RecentJourney(
            fromId: fromId, toId: toId, stepFree: stepFree,
            date: useFutureTime ? futureDate : nil, arriveBy: arriveBy
        )
        recentJourneys.removeAll {
            $0.fromId == entry.fromId && $0.toId == entry.toId &&
            $0.stepFree == entry.stepFree && $0.date == entry.date &&
            $0.arriveBy == entry.arriveBy
        }
        recentJourneys.insert(entry, at: 0)
        if recentJourneys.count > 10 {
            recentJourneys = Array(recentJourneys.prefix(10))
        }
    }

    func deleteRecentJourney(at offsets: IndexSet) {
        recentJourneys.remove(atOffsets: offsets)
    }

    func loadRecentJourney(_ recent: RecentJourney) {
        fromEndpoint = recent.fromStation.map(Endpoint.station)
        toEndpoint = recent.toStation.map(Endpoint.station)
        stepFree = recent.stepFree
        if let date = recent.date {
            useFutureTime = true
            futureDate = date
            arriveBy = recent.arriveBy
        } else {
            useFutureTime = false
        }
    }

    // A pub saves as its nearest station; a raw location has no station
    // pair to save, so the button is disabled for it.
    func saveCurrentRoute(name: String) {
        guard let from = fromEndpoint, let to = toEndpoint,
              let fromId = from.stationId, let toId = to.stationId else { return }
        let route = SavedRoute(
            name: name.isEmpty ? "\(from.name) → \(to.name)" : name,
            fromId: fromId, toId: toId, stepFree: stepFree,
            date: useFutureTime ? futureDate : nil, arriveBy: arriveBy
        )
        savedRoutes.append(route)
    }

    func deleteRoute(at offsets: IndexSet) {
        savedRoutes.remove(atOffsets: offsets)
    }

    func renameRoute(_ route: SavedRoute, to name: String) {
        guard let idx = savedRoutes.firstIndex(where: { $0.id == route.id }) else { return }
        savedRoutes[idx].name = name
    }

    func loadRoute(_ route: SavedRoute) {
        fromEndpoint = route.fromStation.map(Endpoint.station)
        toEndpoint = route.toStation.map(Endpoint.station)
        stepFree = route.stepFree
        if let date = route.date {
            useFutureTime = true
            futureDate = date
            arriveBy = route.arriveBy
        } else {
            useFutureTime = false
        }
    }

    func isFavourite(_ station: Station) -> Bool {
        favouriteIds.contains(station.id)
    }

    func toggleFavourite(_ station: Station) {
        if favouriteIds.contains(station.id) {
            favouriteIds.removeAll { $0 == station.id }
        } else {
            favouriteIds.append(station.id)
        }
    }

    var favouriteStations: [Station] {
        favouriteIds.compactMap { StationData.station(id: $0) }
            .sorted { $0.name < $1.name }
    }

    func swapEndpoints() {
        let tmp = fromEndpoint
        fromEndpoint = toEndpoint
        toEndpoint = tmp
    }

    private func urlWithKey(_ base: String) -> URL? {
        guard !tflAppKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            return URL(string: base)
        }
        let sep = base.contains("?") ? "&" : "?"
        return URL(string: base + sep + "app_key=" + tflAppKey.trimmingCharacters(in: .whitespaces))
    }

    func planJourney() async {
        guard let from = fromEndpoint, let to = toEndpoint else {
            planError = "Pick a From and a To first."
            return
        }
        guard from.apiId != to.apiId else {
            planError = "From and To are the same place."
            return
        }
        isPlanning = true
        defer { isPlanning = false }
        planError = nil
        disambiguation = nil
        journeys = []
        let access = stepFree ? "stepFreeToPlatform" : "noRequirements"
        // apiId can be a NaPTAN id, "lat,lon", or raw text (postcode, place
        // name) — percent-encode it for the URL path: spaces in a postcode
        // or place name must become %20, while commas and NaPTAN ids pass
        // through untouched.
        let fromId = from.apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? from.apiId
        let toId = to.apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? to.apiId
        var urlString = "https://api.tfl.gov.uk/Journey/JourneyResults/\(fromId)/to/\(toId)?accessibilityPreference=\(access)"
        if useFutureTime {
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd"
            df.locale = Locale(identifier: "en_GB")
            let tf = DateFormatter()
            tf.dateFormat = "HHmm"
            tf.locale = Locale(identifier: "en_GB")
            urlString += "&date=\(df.string(from: futureDate))&time=\(tf.string(from: futureDate))&timeIs=\(arriveBy ? "arriving" : "departing")"
        }
        do {
            guard let url = urlWithKey(urlString) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            // v1.7: TfL answers an ambiguous place name with HTTP 300 and a
            // list of matches ("did you mean…?") instead of journeys. That
            // is not a connection failure — offer the choices in the Plan
            // tab. Before v1.7 every non-200 became URLError -1011 and the
            // app blamed the connection.
            if http.statusCode == 300 {
                let decoded = try JSONDecoder().decode(DisambiguationResponse.self, from: data)
                var choices: [DisambiguationChoice] = []
                if let options = decoded.fromLocationDisambiguation?.disambiguationOptions {
                    choices += options.map {
                        DisambiguationChoice(side: "From", apiId: $0.parameterValue, name: $0.place?.commonName ?? $0.parameterValue)
                    }
                }
                if let options = decoded.toLocationDisambiguation?.disambiguationOptions {
                    choices += options.map {
                        DisambiguationChoice(side: "To", apiId: $0.parameterValue, name: $0.place?.commonName ?? $0.parameterValue)
                    }
                }
                guard !choices.isEmpty else { throw URLError(.badServerResponse) }
                disambiguation = DisambiguationOffer(options: choices)
                return
            }
            guard http.statusCode == 200 else {
                // A 400 means TfL could not resolve the name at all — say
                // so, instead of blaming the connection.
                if http.statusCode == 400 {
                    planError = "TfL couldn't find that place — try a postcode, the full address, or pick a suggestion."
                    return
                }
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(JourneyResponse.self, from: data)
            journeys = decoded.journeys
            if !journeys.isEmpty {
                recordRecentJourney()
            }
            if journeys.isEmpty {
                planError = "TfL returned no journeys for that pair right now. Try again in a minute, or check line status."
            }
        } catch {
            planError = "Could not reach TfL just now. Check your connection — the station list still works offline. (\(error.localizedDescription))"
        }
    }

    func fetchLineStatus() async {
        isLoadingStatus = true
        statusError = nil
        let urlString = "https://api.tfl.gov.uk/Line/Mode/tube,dlr,elizabeth-line/Status"
        do {
            guard let url = urlWithKey(urlString) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            var lines = try JSONDecoder().decode([TfLLine].self, from: data)
            lines.sort { $0.name < $1.name }
            lineStatuses = lines
            lastStatusUpdate = Date()
        } catch {
            statusError = "Could not fetch line status. Showing the last status if there is one. (\(error.localizedDescription))"
        }
        isLoadingStatus = false
    }

    func fetchPlanned() async {
        isLoadingPlanned = true
        plannedError = nil
        let ids = "bakerloo,central,circle,district,hammersmith-city,jubilee,metropolitan,northern,piccadilly,victoria,waterloo-city,dlr,elizabeth"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_GB")
        let start: Date
        let end: Date
        switch plannedRange {
        case .next7Days:
            start = Date()
            end = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        case .trip:
            start = fmt.date(from: "2026-12-15") ?? Date()
            end = fmt.date(from: "2026-12-24") ?? Date()
        }
        let urlString = "https://api.tfl.gov.uk/Line/\(ids)/Status/\(fmt.string(from: start))/to/\(fmt.string(from: end))"
        do {
            guard let url = urlWithKey(urlString) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let lines = try JSONDecoder().decode([TfLLine].self, from: data)
            // Group identical notices across lines (network-wide strikes).
            var grouped: [String: PlannedDisruption] = [:]
            for line in lines {
                for status in line.lineStatuses {
                    guard status.statusSeverityDescription != "Good Service" else { continue }
                    guard let reason = status.reason, !reason.isEmpty else { continue }
                    let vp = status.validityPeriods?.first
                    let key = reason + "|" + (vp?.fromDate ?? "")
                    if var existing = grouped[key] {
                        if !existing.lineNames.contains(line.name) {
                            existing = PlannedDisruption(
                                lineNames: existing.lineNames + [line.name],
                                severity: existing.severity,
                                reason: existing.reason,
                                fromDate: existing.fromDate,
                                toDate: existing.toDate
                            )
                            grouped[key] = existing
                        }
                    } else {
                        grouped[key] = PlannedDisruption(
                            lineNames: [line.name],
                            severity: status.statusSeverityDescription,
                            reason: reason,
                            fromDate: vp?.fromDate,
                            toDate: vp?.toDate
                        )
                    }
                }
            }
            plannedItems = grouped.values.sorted { ($0.fromDate ?? "") < ($1.fromDate ?? "") }
            lastPlannedUpdate = Date()
        } catch {
            plannedError = "Could not fetch planned disruptions. (\(error.localizedDescription))"
        }
        isLoadingPlanned = false
    }

    // MARK: - Departure boards (v1.10 — ported from TubeNavigatorTV)

    // Live arrivals — the same countdown feed as the TV station
    // boards. GET /Line/{lineId}/Arrivals/{stopPointId} returns one
    // line's trains at one station, each with its destination,
    // platform, direction, seconds to arrival and where it is right
    // now. The board fetches per line: Paddington's Elizabeth line
    // platforms answer to a different stop point (910GPADTON, the
    // rail station) than its Tube platforms (940GZZLUPAC), so each
    // station carries the stop point to query per line (see
    // BoardStation.arrivalsId(for:)).
    @Published var arrivals: [Arrival] = []
    @Published var isLoadingArrivals = false
    @Published var arrivalsError: String?
    @Published var lastArrivalsUpdate: Date?

    func fetchArrivals(station: BoardStation, lineId: String) async {
        // Only show the spinner on the first load — the 30-second
        // refresh must not flash the board.
        if arrivals.isEmpty { isLoadingArrivals = true }
        arrivalsError = nil
        let urlString = "https://api.tfl.gov.uk/Line/\(lineId)/Arrivals/\(station.arrivalsId(for: lineId))"
        do {
            guard let url = urlWithKey(urlString) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            var rows = try JSONDecoder().decode([Arrival].self, from: data)
            // Paddington's Elizabeth line feed covers the whole
            // station complex (910GPADTON's children include both
            // the underground station and the mainline station), so
            // it also returns the mainline platforms 11 and 12 —
            // late-night trains terminating at Paddington mainline.
            // Jeffery wants only the underground platforms A and B
            // on the board, so drop the mainline-platform rows here,
            // before dedupe and the ghost filter. Scoped to
            // Paddington's Elizabeth line only: outer Elizabeth
            // line stations use numbered platforms, and a future
            // board out there must not go blank. (v1.12, 23 Nov 2026.)
            if lineId == "elizabeth" && station.arrivalsId(for: lineId) == "910GPADTON" {
                rows.removeAll { row in
                    row.platformName == "Platform 11" || row.platformName == "Platform 12"
                        || row.platformName == "11" || row.platformName == "12"
                }
            }
            // The feed returns some predictions more than once, and
            // the copies differ in the raw seconds (timeToStation)
            // by a few seconds — same platform, same destination,
            // same displayed minutes, same clock time. So the key
            // is what the board shows (platform + destination +
            // clock time, HH:mm), not the raw seconds. The
            // prediction id stays in the key: on lines where ids
            // are real (Elizabeth, Tube) it keeps two different
            // trains apart, and on the DLR every row shares one id
            // ("-937089209") so it adds nothing there. Two real
            // trains to the same place due in the same minute would
            // also merge — that needs a sub-minute headway, which
            // these lines don't run. The dedupe is still needed for
            // the Elizabeth line, whose feed really does return each
            // prediction three times; the DLR "triplication" was a
            // SwiftUI duplicate-id rendering bug, fixed by
            // Arrival.id (TV v1.16).
            var seenKeys = Set<String>()
            rows.removeAll { row in
                let clock = TubeService.arrivalTimeText(row.expectedArrival)
                let when = clock.isEmpty ? "\(row.timeToStation ?? -1)s" : clock
                let key = "\(row.predictionId)|\(row.platformName)|\(row.destinationName)|\(when)"
                return !seenKeys.insert(key).inserted
            }
            // Drop the early-morning placeholder rows. Before the
            // first trains run, the feed lists trains "due in 41
            // seconds" that do not exist. The signal that holds: a
            // placeholder's prediction outlives its own arrival by
            // minutes (timeToLive far past expectedArrival — 9 to
            // 45 minutes in the live rows), while a real train's
            // prediction expires around its arrival (timeToLive from
            // ~45 seconds before to a few seconds after
            // expectedArrival). So: drop a row under five minutes
            // with no location only when its prediction also
            // outlives its arrival by more than two minutes (or
            // when the dates are missing, the old cautious rule).
            // Note the location is NOT the signal on its own:
            // Elizabeth line rows NEVER carry a location, so that
            // rule would drop every Elizabeth train within five
            // minutes. (TV v1.11–v1.16, verified live 23 Nov 2026.)
            rows.removeAll { row in
                guard let tts = row.timeToStation, tts < 300 else { return false }
                guard row.currentLocation.isEmpty else { return false }
                guard let ttl = TubeService.parseISODate(row.timeToLive),
                      let exp = TubeService.parseISODate(row.expectedArrival) else { return true }
                return ttl > exp.addingTimeInterval(120)
            }
            rows.removeAll { $0.timeToStation == nil }
            rows.sort { ($0.timeToStation ?? 0) < ($1.timeToStation ?? 0) }
            arrivals = rows
            lastArrivalsUpdate = Date()
        } catch {
            // A cancelled fetch (the line changed under it) is not
            // an error — the new line's fetch replaces it. Without
            // this, switching lines flashes an error.
            if !(error is CancellationError) {
                arrivalsError = "Could not fetch arrivals. (\(error.localizedDescription))"
            }
        }
        isLoadingArrivals = false
    }

    // MARK: - Elizabeth line live map (v1.11 — ported from TV v1.17, geographic)

    // One whole-line fetch, ~2,000 rows / ~140 trains. The old
    // trains stay on screen until a fresh fetch lands — a failed
    // refresh keeps the last positions and their Updated time
    // (same as the TV). A cancelled fetch (the tab closed under
    // it) is not an error.
    @Published var positionedTrains: [PositionedTrain] = []
    @Published var isLoadingPositions = false
    @Published var positionsError: String?
    @Published var lastPositionsUpdate: Date?
    // The last fetch's trains, by vehicle, for the two history
    // cases in the positioning (see ElizabethLineGeoMap).
    private var previousPositions: [String: PositionedTrain] = [:]

    func fetchElizabethLinePositions() async {
        if positionedTrains.isEmpty { isLoadingPositions = true }
        positionsError = nil
        let urlString = "https://api.tfl.gov.uk/Line/elizabeth/Arrivals"
        do {
            guard let url = urlWithKey(urlString) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let rows = try JSONDecoder().decode([Arrival].self, from: data)
            let trains = ElizabethLineGeoMap.positionTrains(rows, previous: previousPositions)
            positionedTrains = trains
            previousPositions = Dictionary(uniqueKeysWithValues: trains.map { ($0.vehicleId, $0) })
            lastPositionsUpdate = Date()
        } catch {
            if !(error is CancellationError) {
                positionsError = "Could not fetch trains. (\(error.localizedDescription))"
            }
        }
        isLoadingPositions = false
    }

    // "Heathrow Terminal 4 Rail Station" -> "Heathrow Terminal 4";
    // "Elephant & Castle Underground Station" -> "Elephant & Castle".
    static func cleanDestination(_ name: String) -> String {
        name.replacingOccurrences(of: " Rail Station", with: "")
            .replacingOccurrences(of: " Underground Station", with: "")
    }

    // The station boards show "Shenfield via Stratford" — the feed
    // only gives the destination, so the "via" comes from the route.
    // Fixed per Elizabeth line destination; Tube destinations stand
    // alone (the destination says enough).
    static func viaText(for destination: String, lineId: String, stationName: String = "") -> String {
        guard lineId == "elizabeth" else { return "" }
        let via: String
        switch cleanDestination(destination) {
        case "Shenfield": via = "Stratford"
        case "Abbey Wood": via = "Canary Wharf"
        case "Reading", "Heathrow Terminal 4", "Heathrow Terminal 5", "Maidenhead": via = "Ealing Broadway"
        default: return ""
        }
        // "Abbey Wood via Canary Wharf" reads wrong on the Canary
        // Wharf board itself — drop the via when it names the
        // station you are already at.
        guard via != stationName else { return "" }
        return "via \(via)"
    }

    // Seconds to station -> "arriving" (a minute or less),
    // "1 min", "12 mins" (station-board style — the board never
    // shows seconds).
    static func minutesText(_ seconds: Int) -> String {
        if seconds <= 60 { return "arriving" }
        if seconds < 105 { return "1 min" }
        return "\(seconds / 60) mins"
    }

    // "2026-11-23T05:48:00Z" -> "05:48" (London time, 24-hour).
    static func arrivalTimeText(_ iso: String?) -> String {
        guard let date = parseISODate(iso) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.locale = Locale(identifier: "en_GB")
        fmt.timeZone = londonTimeZone
        return fmt.string(from: date)
    }

    // "now", or "Leave Thu 17 Dec 10:00" / "Arrive by Thu 17 Dec 10:00".
    var planSummary: String {
        guard useFutureTime else { return "now" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d MMM HH:mm"
        fmt.locale = Locale(identifier: "en_GB")
        return (arriveBy ? "Arrive by " : "Leave ") + fmt.string(from: futureDate)
    }

    // "12 days to London" — counts down to the Dec 15, 2026 trip.
    static func londonCountdownText() -> String {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2026, month: 12, day: 15)) ?? Date()
        let end = cal.date(from: DateComponents(year: 2026, month: 12, day: 24)) ?? Date()
        let today = cal.startOfDay(for: Date())
        if today < start {
            let days = cal.dateComponents([.day], from: today, to: start).day ?? 0
            return days == 1 ? "1 day to London" : "\(days) days to London"
        }
        if today <= end {
            let day = (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1
            return "Day \(day) of the London trip"
        }
        return "London trip done — home for Christmas"
    }

    // "2026-11-17T12:00:00" -> "12:00"
    static func shortTime(_ iso: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        inFmt.locale = Locale(identifier: "en_GB")
        guard let date = inFmt.date(from: iso) else { return iso }
        let outFmt = DateFormatter()
        outFmt.dateFormat = "HH:mm"
        outFmt.locale = Locale(identifier: "en_GB")
        return outFmt.string(from: date)
    }

    // "2026-12-19T12:00:00Z" -> Date (or nil)
    static func parseISODate(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    // TfL times are London wall-clock time. These formatters must use the
    // Europe/London timezone, not the device timezone: on a US phone the
    // device zone (EST, UTC-5) shifts early-morning London times back to the
    // previous evening — e.g. the Waterloo & City item starting 04:15 Sat 19
    // Dec London time renders as "Fri 18 Dec", and it sorts first in the
    // 19 Dec group, so the whole section (including the All Tube lines
    // strike) was headed Friday instead of Saturday. Fixed 17 Nov 2026.
    static var londonTimeZone: TimeZone { TimeZone(identifier: "Europe/London") ?? .gmt }

    // "2026-12-19T12:00:00Z" -> "Sat 19 Dec" (London time)
    static func dayTitle(_ iso: String?) -> String {
        guard let date = parseISODate(iso) else { return "Planned" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d MMM"
        fmt.locale = Locale(identifier: "en_GB")
        fmt.timeZone = londonTimeZone
        return fmt.string(from: date)
    }

    // "12:00 Sat 19 Dec – 11:59 Sun 20 Dec" (London time)
    static func timeRange(from: String?, to: String?) -> String {
        guard let fromDate = parseISODate(from) else { return "" }
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        tf.locale = Locale(identifier: "en_GB")
        tf.timeZone = londonTimeZone
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM"
        df.locale = Locale(identifier: "en_GB")
        df.timeZone = londonTimeZone
        var text = tf.string(from: fromDate) + " " + df.string(from: fromDate)
        if let toDate = parseISODate(to) {
            text += " – " + tf.string(from: toDate) + " " + df.string(from: toDate)
        }
        return text
    }
}
