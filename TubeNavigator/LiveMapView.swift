import SwiftUI
import MapKit
import CoreLocation

// MARK: - Elizabeth line live map (v1.11)
//
// The TV's Live Map tab (v1.17), on iPhone/iPad — but on Apple's
// map, not a redrawn diagram. MapKit draws the Elizabeth line
// and its stations natively; only the train dots are ours.
// MapKit has no live vehicle positions (Apple's live-transit
// data isn't exposed to developers), so the dots still come
// from TfL's arrivals feed and the same estimation as the TV:
// the Elizabeth line feed never reports where a train is, so
// each dot is placed between stations from the minutes to its
// next stop. The TV interpolates along diagram points; this
// one interpolates along geographic coordinates (linear between
// adjacent stations' lat/lon, along the polyline through any
// intermediate chain stations). Station coordinates are from
// TfL's StopPoints endpoint, via workspace/research_notes/
// elizabeth-live-map/stations_geo.json (verified 23 Nov 2026).
// Do not re-derive them by guessing.
//
// Placement: a List / Map segmented switch at the top of the
// Boards tab — the map is another way to see the same live
// trains, and a 6th tab would land in iOS's "More" menu.
// Tap a train to select it (tap again to clear); the detail
// strip below shows destination + next stop + time, two lines,
// same format as the TV strip. No pin badge on iOS — the tap
// itself is the selection. No "waiting at" line (not asked for
// on any surface yet).

/// One train positioned on the Elizabeth line, geographically.
/// Positions are ESTIMATED: the Elizabeth line feed never
/// reports where a train is, so the dot sits between its last
/// station and its next one, placed from the minutes to the
/// next stop.
struct PositionedTrain: Identifiable, Equatable {
    var id: String { vehicleId }
    let vehicleId: String
    let destination: String      // cleaned, e.g. "Shenfield"
    let direction: TrainDirection
    let nextStation: String
    let prevStation: String?     // nil when the dot sits at the next station
    let timeToStation: Int       // seconds to the next station
    let coordinate: CLLocationCoordinate2D

    var isEastbound: Bool { direction == .east }

    static func == (lhs: PositionedTrain, rhs: PositionedTrain) -> Bool {
        lhs.vehicleId == rhs.vehicleId
            && lhs.destination == rhs.destination
            && lhs.direction == rhs.direction
            && lhs.nextStation == rhs.nextStation
            && lhs.prevStation == rhs.prevStation
            && lhs.timeToStation == rhs.timeToStation
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    /// "Between Farringdon and Liverpool Street" / "At Liverpool Street".
    var segmentText: String {
        if let prev = prevStation {
            return "Between \(prev) and \(nextStation)"
        }
        return "At \(nextStation)"
    }

    /// "next stop Liverpool Street in ~2 min" / "arriving at Liverpool Street".
    var nextStopText: String {
        if timeToStation <= 60 { return "arriving at \(nextStation)" }
        return "next stop \(nextStation) in ~\(timeToStation / 60) min"
    }
}

enum TrainDirection: Equatable {
    case east, west
}

enum ElizabethLineGeoMap {
    /// Station -> geographic coordinate. From stations_geo.json
    /// in the research notes — TfL StopPoints.
    static let stations: [String: CLLocationCoordinate2D] = [
        "Abbey Wood": CLLocationCoordinate2D(latitude: 51.491284, longitude: 0.121087),
        "Acton Main Line": CLLocationCoordinate2D(latitude: 51.51718, longitude: -0.266756),
        "Bond Street": CLLocationCoordinate2D(latitude: 51.513282, longitude: -0.149317),
        "Brentwood": CLLocationCoordinate2D(latitude: 51.613605, longitude: 0.299586),
        "Burnham": CLLocationCoordinate2D(latitude: 51.523506, longitude: -0.646374),
        "Canary Wharf": CLLocationCoordinate2D(latitude: 51.506203, longitude: -0.018834),
        "Chadwell Heath": CLLocationCoordinate2D(latitude: 51.568039, longitude: 0.128958),
        "Custom House": CLLocationCoordinate2D(latitude: 51.509436, longitude: 0.027681),
        "Ealing Broadway": CLLocationCoordinate2D(latitude: 51.514841, longitude: -0.301752),
        "Farringdon": CLLocationCoordinate2D(latitude: 51.519635, longitude: -0.102892),
        "Forest Gate": CLLocationCoordinate2D(latitude: 51.549432, longitude: 0.024353),
        "Gidea Park": CLLocationCoordinate2D(latitude: 51.581904, longitude: 0.205964),
        "Goodmayes": CLLocationCoordinate2D(latitude: 51.565579, longitude: 0.110807),
        "Hanwell": CLLocationCoordinate2D(latitude: 51.511835, longitude: -0.338583),
        "Harold Wood": CLLocationCoordinate2D(latitude: 51.592766, longitude: 0.233129),
        "Hayes & Harlington": CLLocationCoordinate2D(latitude: 51.503096, longitude: -0.420683),
        "Ilford": CLLocationCoordinate2D(latitude: 51.559118, longitude: 0.06968),
        "Iver": CLLocationCoordinate2D(latitude: 51.508503, longitude: -0.506726),
        "Langley": CLLocationCoordinate2D(latitude: 51.508062, longitude: -0.541756),
        "Liverpool Street": CLLocationCoordinate2D(latitude: 51.517991, longitude: -0.081426),
        "Maidenhead": CLLocationCoordinate2D(latitude: 51.518669, longitude: -0.72266),
        "Manor Park": CLLocationCoordinate2D(latitude: 51.552477, longitude: 0.046342),
        "Maryland": CLLocationCoordinate2D(latitude: 51.546081, longitude: 0.005815),
        "Paddington": CLLocationCoordinate2D(latitude: 51.516449, longitude: -0.177107),
        "Reading": CLLocationCoordinate2D(latitude: 51.458786, longitude: -0.971863),
        "Romford": CLLocationCoordinate2D(latitude: 51.574829, longitude: 0.183237),
        "Seven Kings": CLLocationCoordinate2D(latitude: 51.564026, longitude: 0.0971),
        "Shenfield": CLLocationCoordinate2D(latitude: 51.630877, longitude: 0.329851),
        "Slough": CLLocationCoordinate2D(latitude: 51.51188, longitude: -0.59151),
        "Southall": CLLocationCoordinate2D(latitude: 51.505957, longitude: -0.37861),
        "Stratford": CLLocationCoordinate2D(latitude: 51.541895, longitude: -0.003397),
        "Taplow": CLLocationCoordinate2D(latitude: 51.523562, longitude: -0.68137),
        "Terminal 4": CLLocationCoordinate2D(latitude: 51.458268, longitude: -0.445463),
        "Terminal 5": CLLocationCoordinate2D(latitude: 51.470053, longitude: -0.490589),
        "Terminals 2 & 3": CLLocationCoordinate2D(latitude: 51.471987, longitude: -0.454788),
        "Tottenham Court Road": CLLocationCoordinate2D(latitude: 51.515075, longitude: -0.130263),
        "Twyford": CLLocationCoordinate2D(latitude: 51.475534, longitude: -0.863293),
        "West Drayton": CLLocationCoordinate2D(latitude: 51.510055, longitude: -0.472234),
        "West Ealing": CLLocationCoordinate2D(latitude: 51.513506, longitude: -0.320133),
        "Whitechapel": CLLocationCoordinate2D(latitude: 51.51943, longitude: -0.060191),
        "Woolwich": CLLocationCoordinate2D(latitude: 51.492017, longitude: 0.0705),
    ]

    /// The five chains, west to east / branch order. Stratford
    /// and West Drayton are the junctions; a train's full route
    /// is the main chain plus one branch. Same chains as the
    /// TV's ElizabethLineMap.
    static let chains: [[String]] = [
        ["Reading", "Twyford", "Maidenhead", "Taplow", "Burnham", "Slough", "Langley", "Iver", "West Drayton", "Hayes & Harlington", "Southall", "Hanwell", "West Ealing", "Ealing Broadway", "Acton Main Line", "Paddington", "Bond Street", "Tottenham Court Road", "Farringdon", "Liverpool Street", "Whitechapel", "Stratford"],
        ["Stratford", "Maryland", "Forest Gate", "Manor Park", "Ilford", "Seven Kings", "Goodmayes", "Chadwell Heath", "Romford", "Gidea Park", "Harold Wood", "Brentwood", "Shenfield"],
        ["Stratford", "Canary Wharf", "Custom House", "Woolwich", "Abbey Wood"],
        ["Terminal 5", "Terminals 2 & 3", "West Drayton"],
        ["Terminal 4", "Terminals 2 & 3", "West Drayton"],
    ]

    /// Every station, in chain order (for stable ForEach).
    static let stationNames: [String] = {
        var seen: [String] = []
        for chain in chains {
            for name in chain where !seen.contains(name) {
                seen.append(name)
            }
        }
        return seen
    }()

    /// Neighbours on the full graph, both directions.
    static let neighbours: [String: Set<String>] = {
        var out: [String: Set<String>] = [:]
        for chain in chains {
            for (a, b) in zip(chain, chain.dropFirst()) {
                out[a, default: []].insert(b)
                out[b, default: []].insert(a)
            }
        }
        return out
    }()

    /// The feed's station and destination names, normalised
    /// the same way positions.py does: strip " Rail Station" /
    /// " Underground Station", a leading "London " or
    /// "Heathrow ", and " (Berks)" / " (London)". Returns nil
    /// for a station the map does not know, so an unknown row
    /// is skipped rather than placed wrong.
    static func normaliseName(_ raw: String) -> String? {
        var name = raw
        name = name.replacingOccurrences(of: " Rail Station", with: "")
        name = name.replacingOccurrences(of: " Underground Station", with: "")
        if name.hasPrefix("London ") { name = String(name.dropFirst("London ".count)) }
        if name.hasPrefix("Heathrow ") { name = String(name.dropFirst("Heathrow ".count)) }
        name = name.replacingOccurrences(of: " (Berks)", with: "")
        name = name.replacingOccurrences(of: " (London)", with: "")
        return stations[name] != nil ? name : nil
    }

    /// "Shenfield Rail Station" -> "Shenfield"; "Heathrow
    /// Terminal 4 Rail Station" -> "Terminal 4". Destinations
    /// are not all stations on the map (e.g. a train can
    /// terminate somewhere the map does not name), so there is
    /// no stations check here — direction() decides whether
    /// the destination is one the map can place.
    static func normaliseDestination(_ raw: String) -> String {
        var name = raw
        name = name.replacingOccurrences(of: " Rail Station", with: "")
        name = name.replacingOccurrences(of: " Underground Station", with: "")
        if name.hasPrefix("London ") { name = String(name.dropFirst("London ".count)) }
        if name.hasPrefix("Heathrow ") { name = String(name.dropFirst("Heathrow ".count)) }
        name = name.replacingOccurrences(of: " (Berks)", with: "")
        name = name.replacingOccurrences(of: " (London)", with: "")
        return name
    }

    static func direction(for destination: String) -> TrainDirection? {
        switch destination {
        case "Shenfield", "Abbey Wood", "Gidea Park": return .east
        case "Reading", "Maidenhead", "Terminal 4", "Terminal 5", "Paddington": return .west
        default: return nil
        }
    }

    // MARK: - Positioning

    /// One leg of the graph, keyed unordered — the running time
    /// is the same either way along it.
    private struct Leg: Hashable {
        let a: String
        let b: String
        init(_ x: String, _ y: String) {
            if x < y { a = x; b = y } else { a = y; b = x }
        }
    }

    /// The shortest station list from one station to another
    /// through the chain graph (BFS — 41 stations, trivial).
    /// Used both for the forward neighbour and for the
    /// interpolation polyline (a Heathrow train's leg from
    /// Terminals 2 & 3 to Hayes & Harlington runs through West
    /// Drayton, which the feed never lists).
    static func path(from: String, to: String) -> [String] {
        if from == to { return [from] }
        var visited: Set<String> = [from]
        var queue: [[String]] = [[from]]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            let last = current.last!
            for next in neighbours[last] ?? [] {
                if visited.contains(next) { continue }
                let extended = current + [next]
                if next == to { return extended }
                visited.insert(next)
                queue.append(extended)
            }
        }
        return [from, to]
    }

    /// "2026-11-23T05:48:00Z" -> Date (or nil). A local copy of
    /// TubeService.parseISODate: that one is main-actor-isolated
    /// (TubeService is @MainActor) and this runs in a synchronous
    /// nonisolated context, so it cannot call it.
    private static func parseISODate(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 240 }
        let sorted = values.sorted()
        if sorted.count % 2 == 1 { return sorted[sorted.count / 2] }
        return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    /// Position every in-service train from one whole-line
    /// Arrivals fetch. `previous` is the last fetch's trains by
    /// vehicle, for the two history cases below. Ports the TV's
    /// ElizabethLineMap.positionTrains (v1.17) — same ghost
    /// filter, same in-service rule, same segment-running-time
    /// medians, same edge cases — but the interpolation runs
    /// along geographic coordinates (metres along the polyline)
    /// instead of diagram points.
    static func positionTrains(_ rows: [Arrival], previous: [String: PositionedTrain]) -> [PositionedTrain] {
        // Group by vehicle; dedupe by station (min time to
        // station); ghost filter (same as the Boards tab).
        // The feed lists each train at every station it will
        // call at, each station twice (Tube + rail stop points)
        // — the normalisation collapses the pair.
        var perVehicle: [String: [String: (tts: Int, destination: String)]] = [:]
        for row in rows {
            guard !row.vehicleId.isEmpty, let tts = row.timeToStation else { continue }
            guard let station = normaliseName(row.stationName) else { continue }
            // Ghost filter: a placeholder row under five minutes
            // with no location whose prediction outlives its own
            // arrival by more than two minutes. Never drop on an
            // empty currentLocation alone — Elizabeth line rows
            // NEVER carry one.
            if tts < 300 && row.currentLocation.isEmpty {
                if let ttl = parseISODate(row.timeToLive),
                   let exp = parseISODate(row.expectedArrival) {
                    if ttl > exp.addingTimeInterval(120) { continue }
                } else {
                    continue
                }
            }
            let destination = normaliseDestination(row.destinationName)
            if let existing = perVehicle[row.vehicleId]?[station] {
                if tts < existing.tts {
                    perVehicle[row.vehicleId]?[station] = (tts, destination)
                }
            } else {
                perVehicle[row.vehicleId, default: [:]][station] = (tts, destination)
            }
        }

        // Segment running times, from the fetched data itself:
        // for each train, the time-to-station differences
        // between consecutive stops that are chain neighbours.
        // Median per leg, needing at least two samples (same
        // as positions.py); a leg with no data falls back to
        // 240 s at lookup time.
        var legSamples: [Leg: [Int]] = [:]
        for stops in perVehicle.values {
            let ordered = stops.sorted { $0.value.tts < $1.value.tts }
            for (first, second) in zip(ordered, ordered.dropFirst()) {
                if neighbours[first.key]?.contains(second.key) == true {
                    legSamples[Leg(first.key, second.key), default: []].append(second.value.tts - first.value.tts)
                }
            }
        }
        var legTimes: [Leg: Int] = [:]
        for (leg, samples) in legSamples where samples.count >= 2 {
            legTimes[leg] = median(samples)
        }
        func runningTime(_ a: String, _ b: String) -> Int {
            legTimes[Leg(a, b)] ?? 240
        }

        let mainChain = chains[0]
        let shenfieldBranch = Set(chains[1].dropFirst())
        let abbeyWoodBranch = Set(chains[2].dropFirst())
        let heathrowStations = Set(["Terminal 4", "Terminal 5", "Terminals 2 & 3"])

        var out: [PositionedTrain] = []
        for (vehicleId, stops) in perVehicle {
            let ordered = stops.sorted { $0.value.tts < $1.value.tts }
            guard let (next, first) = ordered.first else { continue }
            // In service only: a train whose next arrival is
            // more than 30 minutes away is a future service
            // sitting at a terminus.
            guard first.tts <= 1800 else { continue }
            guard let direction = direction(for: first.destination) else { continue }

            // The neighbour on the far side of the next station
            // — the side the train is heading toward. Found from
            // the chain graph, not the feed's sparse list: the
            // feed skips stops (an Abbey Wood train's list jumps
            // Canary Wharf -> Whitechapel with no Stratford row).
            let forwardPath = path(from: next, to: first.destination)
            let forwardNeighbour = forwardPath.count >= 2 ? forwardPath[1] : nil
            var prevCandidates = neighbours[next] ?? []
            if let forwardNeighbour { prevCandidates.remove(forwardNeighbour) }

            var prev: String?
            if prevCandidates.count == 1 {
                prev = prevCandidates.first
            } else if prevCandidates.count > 1 {
                // The train came from one side only. Eastbound it
                // came from the west (the main-chain neighbour
                // with the lowest index); westbound from the east
                // (the highest index). A candidate off the main
                // chain (Maryland, Canary Wharf) only counts when
                // it is the only one.
                let onMain = prevCandidates.compactMap { c -> (String, Int)? in
                    guard let i = mainChain.firstIndex(of: c) else { return nil }
                    return (c, i)
                }
                if direction == .east {
                    prev = onMain.min(by: { $0.1 < $1.1 })?.0
                } else {
                    prev = onMain.max(by: { $0.1 < $1.1 })?.0
                }
            }
            // History, for the two genuinely ambiguous cases.
            // Stratford heading west: Maryland or Canary Wharf —
            // the branch the train was last seen on decides.
            // Hayes & Harlington heading east: West Drayton by
            // default, Terminals 2 & 3 when the train came down
            // the Heathrow branch. Terminals 2 & 3 heading east:
            // Terminal 4 or Terminal 5, whichever it came from.
            if prev == nil, let prior = previous[vehicleId] {
                if next == "Stratford" && direction == .west {
                    if let p = prior.prevStation, shenfieldBranch.contains(p) { prev = "Maryland" }
                    else if let p = prior.prevStation, abbeyWoodBranch.contains(p) { prev = "Canary Wharf" }
                    else if shenfieldBranch.contains(prior.nextStation) { prev = "Maryland" }
                    else if abbeyWoodBranch.contains(prior.nextStation) { prev = "Canary Wharf" }
                } else if next == "Hayes & Harlington" && direction == .east {
                    if let p = prior.prevStation, heathrowStations.contains(p) { prev = "Terminals 2 & 3" }
                    else if heathrowStations.contains(prior.nextStation) { prev = "Terminals 2 & 3" }
                } else if next == "Terminals 2 & 3" && direction == .east {
                    if prior.prevStation == "Terminal 5" || prior.nextStation == "Terminal 5" { prev = "Terminal 5" }
                    else if prior.prevStation == "Terminal 4" || prior.nextStation == "Terminal 4" { prev = "Terminal 4" }
                }
            }

            // Where the dot goes: interpolate along the polyline
            // from the previous station to the next one, through
            // any intermediate chain stations. Fraction =
            // clamp(1 - timeToStation / R, 0, 1), where R is the
            // running time for the leg (summed over the polyline
            // legs when the leg is not direct). No previous
            // station: the dot sits at the next station.
            let coordinate: CLLocationCoordinate2D
            if let prev, let prevCoord = stations[prev], let nextCoord = stations[next] {
                let polyline = path(from: prev, to: next)
                var total: Double = 0
                var legs: [(CLLocationCoordinate2D, CLLocationCoordinate2D, Double)] = []
                for (a, b) in zip(polyline, polyline.dropFirst()) {
                    guard let pa = stations[a], let pb = stations[b] else { continue }
                    let len = CLLocation(latitude: pa.latitude, longitude: pa.longitude)
                        .distance(from: CLLocation(latitude: pb.latitude, longitude: pb.longitude))
                    legs.append((pa, pb, len))
                    total += len
                }
                let r = zip(polyline, polyline.dropFirst()).reduce(0) { $0 + runningTime($1.0, $1.1) }
                let frac = total > 0 ? max(0, min(1, 1 - Double(first.tts) / Double(r))) : 1
                var distance = frac * total
                var placed = nextCoord
                for (pa, pb, len) in legs {
                    if distance <= len {
                        let t = len > 0 ? distance / len : 0
                        placed = CLLocationCoordinate2D(
                            latitude: pa.latitude + (pb.latitude - pa.latitude) * t,
                            longitude: pa.longitude + (pb.longitude - pa.longitude) * t
                        )
                        break
                    }
                    distance -= len
                    placed = pb
                }
                _ = prevCoord
                coordinate = placed
            } else if let nextCoord = stations[next] {
                coordinate = nextCoord
            } else {
                continue
            }

            out.append(PositionedTrain(
                vehicleId: vehicleId,
                destination: first.destination,
                direction: direction,
                nextStation: next,
                prevStation: prev,
                timeToStation: first.tts,
                coordinate: coordinate
            ))
        }
        return out.sorted { $0.vehicleId < $1.vehicleId }
    }
}

// MARK: - Live map view

struct LiveMapView: View {
    @EnvironmentObject private var service: TubeService
    @State private var selectedVehicleId: String?

    // The whole line at once: Reading (51.459, -0.972) to
    // Shenfield (51.631, 0.330). The user pans and zooms freely
    // with touch — the camera only sets the first view.
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.545, longitude: -0.321),
        span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 1.55)
    ))

    // Same dot colours as the TV Live Map and the web page.
    private static let eastboundColor = Color(red: 0.95, green: 0.30, blue: 0.25)
    private static let westboundColor = Color(red: 0.25, green: 0.55, blue: 1.0)

    private var selectedTrain: PositionedTrain? {
        guard let id = selectedVehicleId else { return nil }
        return service.positionedTrains.first { $0.vehicleId == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                ForEach(service.positionedTrains) { train in
                    Annotation("", coordinate: train.coordinate) {
                        Button {
                            // Tap to select; tap again to clear;
                            // tap another train to re-select.
                            selectedVehicleId = (selectedVehicleId == train.vehicleId) ? nil : train.vehicleId
                        } label: {
                            Circle()
                                .fill(train.isEastbound ? Self.eastboundColor : Self.westboundColor)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .overlay(
                                    // A selected train gets a second ring.
                                    Circle().stroke(Color.white, lineWidth: 2)
                                        .frame(width: 26, height: 26)
                                        .opacity(selectedVehicleId == train.vehicleId ? 1 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            detailStrip
            footer
        }
        .task {
            await service.fetchElizabethLinePositions()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await service.fetchElizabethLinePositions()
            }
        }
        // A selected train that has left the line (arrived,
        // terminated) drops its selection rather than pointing
        // at a train that is no longer there.
        .onChange(of: service.positionedTrains) { _, trains in
            if let selected = selectedVehicleId, !trains.contains(where: { $0.vehicleId == selected }) {
                selectedVehicleId = nil
            }
        }
    }

    // Two lines when a train is selected: destination + next
    // stop on the first, the stretch it is on underneath —
    // same format as the TV strip.
    private var detailStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let train = selectedTrain {
                HStack(spacing: 8) {
                    Circle()
                        .fill(train.isEastbound ? Self.eastboundColor : Self.westboundColor)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    Text("To \(train.destination)")
                        .font(.headline)
                    Text(train.nextStopText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(train.segmentText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if service.isLoadingPositions && service.positionedTrains.isEmpty {
                Text("Checking trains…")
                    .foregroundStyle(.secondary)
            } else if let error = service.positionsError, service.positionedTrains.isEmpty {
                Text(error)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(service.positionedTrains.count) trains on the line — tap a train to see its details.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let updated = service.lastPositionsUpdate {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened)) · Data: Transport for London")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Train positions are estimated from TfL arrival times — the Elizabeth line doesn't report where its trains are, so each dot is placed between stations from the minutes to its next stop.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
