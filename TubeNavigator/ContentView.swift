import SwiftUI
import MapKit
import PDFKit
import CoreLocation

struct ContentView: View {
    @StateObject private var service = TubeService()

    var body: some View {
        TabView {
            PlanView()
                .tabItem { Label("Plan", systemImage: "map") }
            StatusView()
                .tabItem { Label("Status", systemImage: "info.circle") }
            BoardsView()
                .tabItem { Label("Boards", systemImage: "list.bullet") }
            PlannedView()
                .tabItem { Label("Planned", systemImage: "calendar") }
            PlacesView()
                .tabItem { Label("Places", systemImage: "mappin.circle") }
        }
        .tint(service.accentColor)
        .environmentObject(service)
    }
}

// MARK: - Line colours

func lineColor(for lineId: String) -> Color {
    guard let hex = TubeLines.all[lineId]?.hex else {
        switch lineId {
        case "walking": return .gray
        case "bus": return .red
        default: return .gray
        }
    }
    return Color(hex: hex)
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

func legLineId(_ leg: Leg) -> String {
    if let id = leg.routeOptions?.first?.lineIdentifier?.id {
        return id
    }
    return leg.mode.id
}

// MARK: - Plan

struct PlanView: View {
    @EnvironmentObject private var service: TubeService
    @State private var showKeyField = false
    @State private var showSaveAlert = false
    @State private var saveName = ""
    @State private var showRenameAlert = false
    @State private var routeToRename: SavedRoute?
    @State private var renameText = ""
    // v1.6: autocomplete From/To — type a station, a pub or a place and
    // suggestions appear as you type. The text mirrors the endpoint name;
    // editing it clears the endpoint until a suggestion is picked.
    @State private var fromText = ""
    @State private var toText = ""
    @FocusState private var focusedField: EndpointField?

    enum EndpointField: Hashable { case from, to }

    // v1.8: on-phone lookup for typed place names — the "Look up" row in
    // Suggestions runs MapKit's local search (MKLocalSearch) on the typed
    // text and offers the found place with its address, so TfL never has
    // to guess a name. (The first cut used CLGeocoder; it only geocodes
    // addresses, so "me hotel" came back empty — a place name needs a
    // place search, not an address lookup.) Keyed by field+query, so
    // editing the text drops a stale result.
    struct PlaceLookup {
        var field: EndpointField
        var query: String
        var isLookingUp: Bool
        var found: (name: String, address: String, lat: Double, lon: Double)?
        var error: String?
    }
    @State private var placeLookup: PlaceLookup?

    var body: some View {
        NavigationStack {
            List {
                Section("Route") {
                    endpointField(label: "From", text: $fromText, field: .from)
                    endpointField(label: "To", text: $toText, field: .to)
                    Button {
                        service.swapEndpoints()
                        let tmp = fromText
                        fromText = toText
                        toText = tmp
                    } label: {
                        Label("Swap From and To", systemImage: "arrow.up.arrow.down")
                    }
                    Toggle("Step-free route", isOn: $service.stepFree)
                    Button {
                        saveName = "\(service.fromEndpoint?.name ?? "") → \(service.toEndpoint?.name ?? "")"
                        showSaveAlert = true
                    } label: {
                        Label("Save this route", systemImage: "bookmark")
                    }
                    .disabled(service.fromEndpoint?.stationId == nil || service.toEndpoint?.stationId == nil)
                    Text("Type a station, a pub or a place — suggestions appear as you type. Your places and favourites come first. A pub plans from the pub itself, with the walk to its station included. The line under each field shows what was actually found — typed text alone is never confirmed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                suggestionsSection

                Section("When") {
                    Toggle("Plan for a later time", isOn: $service.useFutureTime)
                    if service.useFutureTime {
                        DatePicker("Date and time", selection: $service.futureDate)
                        Picker("Timing", selection: $service.arriveBy) {
                            Text("Leave at").tag(false)
                            Text("Arrive by").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Text("TfL plans from the published timetable, so a strike or closure can still shift the route — cross-check on the Planned tab closer to the day.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !service.savedRoutes.isEmpty {
                    Section("Saved routes") {
                        ForEach(service.savedRoutes) { route in
                            Button {
                                service.loadRoute(route)
                                Task { await service.planJourney() }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.name)
                                    Text(route.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Rename") {
                                    routeToRename = route
                                    renameText = route.name
                                    showRenameAlert = true
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete { service.deleteRoute(at: $0) }
                        Text("Saved routes are station pairs. Times are recalculated live — needs signal.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !service.recentJourneys.isEmpty {
                    Section("Recent") {
                        ForEach(service.recentJourneys) { recent in
                            Button {
                                service.loadRecentJourney(recent)
                                Task { await service.planJourney() }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recent.title)
                                    Text(recent.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { service.deleteRecentJourney(at: $0) }
                        Text("Your last few journeys, most recent first. Tap to re-plan live — times are recalculated.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        Task { await service.planJourney() }
                    } label: {
                        HStack {
                            Spacer()
                            if service.isPlanning {
                                ProgressView()
                            } else {
                                Text("Plan journey").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(service.isPlanning || service.fromEndpoint == nil || service.toEndpoint == nil)
                }

                // v1.7: TfL answered "which one did you mean?" (HTTP 300)
                // instead of journeys — offer the matches, don't blame the
                // connection. Picking one re-plans with that place.
                if let offer = service.disambiguation {
                    Section("Did you mean…?") {
                        Text("TfL found more than one place for that name — pick the right one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(offer.options) { choice in
                            Button {
                                service.applyDisambiguation(choice)
                                Task { await service.planJourney() }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.name)
                                    Text("Use this as \(choice.side)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let error = service.planError {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                    }
                }

                if !service.journeys.isEmpty {
                    Section("Journeys — \(service.planSummary)") {
                        ForEach(service.journeys) { journey in
                            NavigationLink {
                                JourneyDetailView(journey: journey)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("\(journey.duration) min").bold()
                                        Spacer()
                                        Text("\(TubeService.shortTime(journey.startDateTime)) – \(TubeService.shortTime(journey.arrivalDateTime))")
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(journey.legs.map { $0.instruction.summary }.joined(separator: " → "))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }

                Section("Pub crawl") {
                    NavigationLink {
                        PubCrawlView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Plan a pub crawl")
                            Text("First-day route plus \(PubData.all.count) pubs, each matched to its nearest station.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("TfL key (optional)") {
                    DisclosureGroup("Free TfL app key — only if you hit rate limits", isExpanded: $showKeyField) {
                        Text("No key is needed for personal use. If TfL ever rate-limits you, register free at api-portal.tfl.gov.uk and paste the app_key here. It stays on this phone only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("app_key (optional)", text: $service.tflAppKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    Text("Journey times are live from Transport for London. Underground stations have no signal, so plan before you go down — the station list works offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Plan a journey")
            .onAppear {
                // First appearance: show the current endpoints in the fields.
                // Only fill empty fields, so typing in progress is never wiped
                // when coming back from a detail view.
                if fromText.isEmpty, let name = service.fromEndpoint?.name { fromText = name }
                if toText.isEmpty, let name = service.toEndpoint?.name { toText = name }
            }
            .onChange(of: service.fromEndpoint) { _, endpoint in
                // Endpoints set elsewhere (Stations tab, pub detail, a saved
                // or recent route) show up in the field. Only sync a real
                // endpoint — typing clears the endpoint to nil, and that
                // must not wipe the text being typed.
                if let endpoint { fromText = endpoint.name }
            }
            .onChange(of: service.toEndpoint) { _, endpoint in
                if let endpoint { toText = endpoint.name }
            }
            .alert("Save route", isPresented: $showSaveAlert) {
                TextField("Route name", text: $saveName)
                Button("Save") { service.saveCurrentRoute(name: saveName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved routes are station pairs. Times are recalculated live — needs signal.")
            }
            .alert("Rename route", isPresented: $showRenameAlert) {
                TextField("Route name", text: $renameText)
                Button("Save") {
                    if let route = routeToRename { service.renameRoute(route, to: renameText) }
                    routeToRename = nil
                }
                Button("Cancel", role: .cancel) { routeToRename = nil }
            }
            .task {
                // Pre-load status in the background so the Status tab is ready.
                if service.lineStatuses.isEmpty {
                    await service.fetchLineStatus()
                }
            }
        }
    }

    private func endpointField(label: String, text: Binding<String>, field: EndpointField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                TextField("Station, pub or place", text: text)
                    .focused($focusedField, equals: field)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        // Editing the text drops the current endpoint until a
                        // suggestion is picked; picking one sets the text to the
                        // endpoint name, so this does not fire then. A new
                        // query also drops any "did you mean…?" offer.
                        let current = field == .from ? service.fromEndpoint : service.toEndpoint
                        if current?.name != newValue {
                            if field == .from { service.fromEndpoint = nil } else { service.toEndpoint = nil }
                            service.disambiguation = nil
                        }
                    }
                if focusedField == field, !text.wrappedValue.isEmpty {
                    Button {
                        text.wrappedValue = ""
                        if field == .from { service.fromEndpoint = nil } else { service.toEndpoint = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            confirmationCaption(for: field, text: text.wrappedValue)
        }
    }

    // v1.8: the confirmation line — what the app actually found, under
    // the field, before Plan journey is tapped. A picked place shows its
    // address or lines; typed text that was never picked says so, in
    // orange, instead of looking confirmed.
    @ViewBuilder
    private func confirmationCaption(for field: EndpointField, text: String) -> some View {
        let endpoint = field == .from ? service.fromEndpoint : service.toEndpoint
        if let endpoint {
            if endpoint.kind == .location {
                Text("“\(endpoint.name)” not looked up — TfL will guess the place.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("✓ \(endpoint.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if !text.isEmpty {
            Text("Nothing picked yet — tap a suggestion below.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // Live suggestions for whichever field is being typed in. v1.7 order:
    // your saved places first (the hotel comes up on "wilde", "hotel",
    // "paddington" — no TfL name lookup, it plans from its coordinates),
    // then favourite stations and pubs, then the rest of the stations and
    // pubs, then the raw text itself as a location (postcode, address,
    // place name — TfL resolves it, and may answer "did you mean…?").
    // v1.8: a "Look up" row runs an on-phone place search on the typed
    // text and offers the found place with its address.
    // The search runs over the bundled lists, so suggestions work offline;
    // only the plan itself needs signal.
    @ViewBuilder
    private var suggestionsSection: some View {
        if let field = focusedField {
            let query = field == .from ? fromText : toText
            if !query.isEmpty {
                Section("Suggestions") {
                    ForEach(matchingPlaces(for: query)) { place in
                        Button {
                            selectEndpoint(.place(place), for: field)
                        } label: {
                            suggestionLabel(name: place.name, detail: "Your place · \(place.address)")
                        }
                    }
                    ForEach(matchingFavouriteStations(for: query)) { station in
                        Button {
                            selectEndpoint(.station(station), for: field)
                        } label: {
                            suggestionLabel(name: station.name, detail: "Favourite · " + lineNames(for: station))
                        }
                    }
                    ForEach(matchingFavouritePubs(for: query)) { pub in
                        Button {
                            selectEndpoint(.pub(pub), for: field)
                        } label: {
                            suggestionLabel(
                                name: pub.name,
                                detail: "Favourite pub · \(pub.area) — \(pub.stationName)\(pub.distanceText.map { " (\($0))" } ?? "")"
                            )
                        }
                    }
                    ForEach(matchingStations(for: query)) { station in
                        Button {
                            selectEndpoint(.station(station), for: field)
                        } label: {
                            suggestionLabel(name: station.name, detail: lineNames(for: station))
                        }
                    }
                    ForEach(matchingPubs(for: query)) { pub in
                        Button {
                            selectEndpoint(.pub(pub), for: field)
                        } label: {
                            suggestionLabel(
                                name: pub.name,
                                detail: "Pub · \(pub.area) — \(pub.stationName)\(pub.distanceText.map { " (\($0))" } ?? "")"
                            )
                        }
                    }
                    Button {
                        selectEndpoint(.location(query), for: field)
                    } label: {
                        suggestionLabel(name: "Use “\(query)”", detail: "Postcode, address or place — TfL will work it out.")
                    }
                    // v1.8: look the typed name up on this phone — the
                    // found place comes back with its address and plans
                    // from coordinates, so TfL never guesses. The result
                    // is keyed by field+query, so editing the text drops
                    // a stale one; the Look up row stays, so a failed
                    // lookup can be retried.
                    if let lookup = placeLookup, lookup.field == field, lookup.query == query {
                        if lookup.isLookingUp {
                            HStack {
                                ProgressView()
                                Text("Looking up “\(query)”…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let found = lookup.found {
                            Button {
                                selectEndpoint(.foundPlace(name: found.name, address: found.address, lat: found.lat, lon: found.lon), for: field)
                            } label: {
                                suggestionLabel(name: found.name, detail: "Found place · \(found.address)")
                            }
                        } else if let error = lookup.error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task { await lookupPlace(query, for: field) }
                    } label: {
                        suggestionLabel(name: "Look up “\(query)”", detail: "Find the place on this phone — with its address.")
                    }
                }
            }
        }
    }

    private func suggestionLabel(name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).foregroundStyle(.primary)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    // Where the query first occurs in the text (lowercased), or nil.
    private func matchPosition(_ needle: String, in text: String) -> Int? {
        let lower = text.lowercased()
        guard let range = lower.range(of: needle) else { return nil }
        return lower.distance(from: lower.startIndex, to: range.lowerBound)
    }

    private func matchingStations(for query: String) -> [Station] {
        let needle = query.lowercased()
        // Favourites are shown in their own group above, so they are
        // left out here rather than listed twice.
        return Array(StationData.all
            .filter { !service.isFavourite($0) }
            .compactMap { station -> (Station, Int)? in
                matchPosition(needle, in: station.name).map { (station, $0) }
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            .prefix(5))
    }

    private func matchingPubs(for query: String) -> [Pub] {
        let needle = query.lowercased()
        // Name matches first, earliest match first — so "Gra" finds
        // The Grapes before Belgravia-area pubs whose area happens to
        // contain "gra". Area matches follow. Favourite pubs are shown
        // in their own group above, so they are left out here.
        let nameMatches = PubData.all
            .filter { !service.isFavouritePub($0) }
            .compactMap { pub -> (Pub, Int)? in
                matchPosition(needle, in: pub.name).map { (pub, $0) }
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        let areaMatches = PubData.all.filter { pub in
            !service.isFavouritePub(pub) &&
            matchPosition(needle, in: pub.name) == nil && pub.area.lowercased().contains(needle)
        }
        return Array((nameMatches + areaMatches).prefix(5))
    }

    private func selectEndpoint(_ endpoint: Endpoint, for field: EndpointField) {
        service.disambiguation = nil
        if field == .from {
            service.fromEndpoint = endpoint
            fromText = endpoint.name
        } else {
            service.toEndpoint = endpoint
            toText = endpoint.name
        }
        focusedField = nil
    }

    // v1.8: MapKit's local search (MKLocalSearch) on the typed text —
    // the place search for names, where Add a place's CLGeocoder lookup
    // is the address lookup. The search is biased to central London by
    // region, so the query needs no ", London" appended. The result is
    // only shown for the field and query that were looked up — editing
    // the text drops a stale one.
    private func lookupPlace(_ query: String, for field: EndpointField) async {
        placeLookup = PlaceLookup(field: field, query: query, isLookingUp: true, found: nil, error: nil)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                placeLookup = PlaceLookup(field: field, query: query, isLookingUp: false, found: nil, error: "Couldn't find “\(query)” — try the postcode.")
                return
            }
            let name = item.name ?? query
            let mark = item.placemark
            let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
            let address = [street, mark.locality, mark.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            placeLookup = PlaceLookup(
                field: field, query: query, isLookingUp: false,
                found: (name: name, address: address.isEmpty ? (mark.title ?? query) : address, lat: mark.coordinate.latitude, lon: mark.coordinate.longitude),
                error: nil
            )
        } catch {
            placeLookup = PlaceLookup(field: field, query: query, isLookingUp: false, found: nil, error: "Couldn't find “\(query)” — try the postcode.")
        }
    }

    // Saved places match on name or address — "hotel" finds the Wilde
    // (its name is "Wilde Aparthotels…"), "north wharf" finds it too.
    private func matchingPlaces(for query: String) -> [SavedPlace] {
        let needle = query.lowercased()
        return Array(service.savedPlaces.filter { place in
            place.name.lowercased().contains(needle) || place.address.lowercased().contains(needle)
        }.prefix(3))
    }

    private func matchingFavouriteStations(for query: String) -> [Station] {
        let needle = query.lowercased()
        return Array(service.favouriteStations.filter { station in
            matchPosition(needle, in: station.name) != nil
        }.prefix(3))
    }

    private func matchingFavouritePubs(for query: String) -> [Pub] {
        let needle = query.lowercased()
        return Array(service.favouritePubs.filter { pub in
            matchPosition(needle, in: pub.name) != nil || pub.area.lowercased().contains(needle)
        }.prefix(3))
    }

    private func lineNames(for station: Station) -> String {
        station.lineIds.map { TubeLines.name(for: $0) }.joined(separator: " · ") + " — Zone \(station.zone)"
    }
}

struct JourneyDetailView: View {
    let journey: Journey
    @EnvironmentObject private var service: TubeService

    var body: some View {
        List {
            Section {
                HStack {
                    Text("\(journey.duration) min").font(.title2).bold()
                    Spacer()
                    Text("\(TubeService.shortTime(journey.startDateTime)) – \(TubeService.shortTime(journey.arrivalDateTime))")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Route map") {
                JourneyMapView(journey: journey)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
            Section("Legs") {
                ForEach(journey.legs) { leg in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(lineColor(for: legLineId(leg)))
                                .frame(width: 10, height: 10)
                            Text(leg.instruction.summary).bold()
                            Spacer()
                            Text("\(leg.duration) min").foregroundStyle(.secondary)
                        }
                        Text(leg.instruction.detailed)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(leg.departurePoint.commonName) → \(leg.arrivalPoint.commonName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let dep = leg.departureTime, let arr = leg.arrivalTime {
                            Text("\(TubeService.shortTime(dep)) – \(TubeService.shortTime(arr))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section("Open in Maps") {
                Button {
                    openInAppleMaps()
                } label: {
                    Label("Open in Apple Maps", systemImage: "map")
                }
                Button {
                    openInGoogleMaps()
                } label: {
                    Label("Open in Google Maps", systemImage: "map.fill")
                }
                Text("Hands the same From and To to Maps for full door-to-door routing, walking included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button {
                    service.saveCurrentRoute(name: "")
                } label: {
                    Label("Save this route", systemImage: "bookmark")
                }
                // A raw location (postcode, place name) has no station pair
                // to save; a pub saves as its nearest station.
                .disabled(service.fromEndpoint?.stationId == nil || service.toEndpoint?.stationId == nil)
            }
            Section {
                Text("Mind the gap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Times are live from TfL and can change with disruptions. Check the Status tab before you travel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Journey")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func endpointStrings() -> (from: String, to: String)? {
        guard let first = journey.legs.first, let last = journey.legs.last else { return nil }
        let from = coordinateString(first.departurePoint) ?? "\(first.departurePoint.commonName), London"
        let to = coordinateString(last.arrivalPoint) ?? "\(last.arrivalPoint.commonName), London"
        return (from, to)
    }

    private func coordinateString(_ point: StopPointRef) -> String? {
        guard let lat = point.lat, let lon = point.lon else { return nil }
        return "\(lat),\(lon)"
    }

    private func openInAppleMaps() {
        guard let endpoints = endpointStrings() else { return }
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "saddr", value: endpoints.from),
            URLQueryItem(name: "daddr", value: endpoints.to),
            URLQueryItem(name: "dirflg", value: "r")
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }

    private func openInGoogleMaps() {
        guard let endpoints = endpointStrings() else { return }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: endpoints.from),
            URLQueryItem(name: "destination", value: endpoints.to),
            URLQueryItem(name: "travelmode", value: "transit")
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Route map (MapKit)

struct JourneyMapView: View {
    let journey: Journey
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(journey.legs) { leg in
                let coords = legCoordinates(leg)
                if coords.count > 1 {
                    MapPolyline(coordinates: coords)
                        .stroke(lineColor(for: legLineId(leg)), lineWidth: 4)
                }
            }
            if let start = allCoordinates.first {
                Marker("Start", coordinate: start).tint(.green)
            }
            if let end = allCoordinates.last, allCoordinates.count > 1 {
                Marker("End", coordinate: end).tint(.red)
            }
        }
        .onAppear {
            if let region = mapRegion {
                position = .region(region)
            }
        }
    }

    private func legCoordinates(_ leg: Leg) -> [CLLocationCoordinate2D] {
        [leg.departurePoint, leg.arrivalPoint].compactMap { point in
            guard let lat = point.lat, let lon = point.lon else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    private var allCoordinates: [CLLocationCoordinate2D] {
        journey.legs.flatMap { legCoordinates($0) }
    }

    private var mapRegion: MKCoordinateRegion? {
        let coords = allCoordinates
        guard !coords.isEmpty else { return nil }
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Status

struct StatusView: View {
    @EnvironmentObject private var service: TubeService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "airplane.departure")
                            .foregroundStyle(.secondary)
                        Text(TubeService.londonCountdownText()).bold()
                        Spacer()
                        Text("Dec 15–24").foregroundStyle(.secondary)
                    }
                }
                Section {
                    WeatherStripView()
                }
                if let error = service.statusError, service.lineStatuses.isEmpty {
                    Section { Text(error).foregroundStyle(.secondary) }
                }
                ForEach(service.lineStatuses) { line in
                    let status = line.lineStatuses.first
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(lineColor(for: line.id))
                                .frame(width: 12, height: 12)
                            Text(line.name).bold()
                            Spacer()
                            Text(status?.statusSeverityDescription ?? "—")
                                .font(.subheadline)
                                .foregroundStyle(statusColor(for: status?.statusSeverityDescription ?? ""))
                        }
                        if let reason = status?.reason, !reason.isEmpty {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if let updated = service.lastStatusUpdate {
                    Section {
                        Text("Updated \(updated.formatted(date: .omitted, time: .shortened)) · Data: Transport for London")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Line status")
            .refreshable { await service.fetchLineStatus() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await service.fetchLineStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(service.isLoadingStatus)
                }
            }
            .task {
                if service.lineStatuses.isEmpty {
                    await service.fetchLineStatus()
                }
            }
        }
    }

    private func statusColor(for description: String) -> Color {
        switch description {
        case "Good Service": return .green
        case "Service Closed": return .gray
        default: return .orange
        }
    }
}

// MARK: - Weather strip (WeatherKit)

struct WeatherStripView: View {
    @StateObject private var model = WeatherViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isLoading && model.current == nil {
                HStack {
                    ProgressView()
                    Text("Loading London weather…").foregroundStyle(.secondary)
                }
            } else if let current = model.current {
                HStack(spacing: 10) {
                    Image(systemName: current.symbolName).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(model.tempF(current.temperature)) · \(model.conditionText(current.condition))")
                            .bold()
                        Text("\(model.placeName) · High \(model.tempF(model.todayHigh)) / Low \(model.tempF(model.todayLow)) · Wind \(Int(current.wind.speed.converted(to: .milesPerHour).value.rounded())) mph")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if !model.restOfDay.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(model.restOfDay, id: \.date) { hour in
                                VStack(spacing: 3) {
                                    Text(hour.date.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .bold()
                                    Image(systemName: hour.symbolName)
                                        .font(.subheadline)
                                    Text(model.tempF(hour.temperature))
                                        .font(.caption)
                                    Text("\(Int((hour.precipitationChance * 100).rounded()))% rain")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Text("Data from Apple Weather")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { model.load() }
    }
}

// MARK: - Planned disruptions

struct PlannedView: View {
    @EnvironmentObject private var service: TubeService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $service.plannedRange) {
                        ForEach(PlannedRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: service.plannedRange) {
                        Task { await service.fetchPlanned() }
                    }
                }
                if service.isLoadingPlanned && service.plannedItems.isEmpty {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Checking TfL…").foregroundStyle(.secondary)
                        }
                    }
                } else if let error = service.plannedError, service.plannedItems.isEmpty {
                    Section { Text(error).foregroundStyle(.secondary) }
                } else if service.plannedItems.isEmpty {
                    Section {
                        Text("No planned disruptions in this period. Strikes and engineering works show here once TfL publishes them — check again closer to the date.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(groupedItems, id: \.key) { group in
                        Section(group.day) {
                            ForEach(group.items) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.displayLines).bold()
                                        Spacer()
                                        Text(item.severity)
                                            .font(.subheadline)
                                            .foregroundStyle(.orange)
                                    }
                                    Text(item.reason)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(TubeService.timeRange(from: item.fromDate, to: item.toDate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                if let updated = service.lastPlannedUpdate {
                    Section {
                        Text("Updated \(updated.formatted(date: .omitted, time: .shortened)) · Data: Transport for London")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Planned disruptions")
            .refreshable { await service.fetchPlanned() }
            .task {
                if service.plannedItems.isEmpty {
                    await service.fetchPlanned()
                }
            }
        }
    }

    private var groupedItems: [(key: String, day: String, items: [PlannedDisruption])] {
        let grouped = Dictionary(grouping: service.plannedItems) { item in
            String((item.fromDate ?? "").prefix(10))
        }
        return grouped.keys.sorted().map { key in
            let items = (grouped[key] ?? []).sorted { ($0.fromDate ?? "") < ($1.fromDate ?? "") }
            return (key: key, day: TubeService.dayTitle(items.first?.fromDate), items: items)
        }
    }
}

// MARK: - Stations

enum GuidePDF: String, Identifiable {
    case tubeMap, stepFree
    var id: String { rawValue }
    var fileName: String {
        switch self {
        case .tubeMap: return "standard-tube-map"
        case .stepFree: return "step-free-tube-guide-map"
        }
    }
    var title: String {
        switch self {
        case .tubeMap: return "Tube map"
        case .stepFree: return "Step-free Tube guide"
        }
    }
}

// v1.7: the Stations tab is now Places — stations, pubs and Jeffery's
// own saved places in one tab, with a Favourites section at the top for
// the starred stations, starred pubs and saved places (the hotel lives
// there, seeded on first launch).
struct PlacesView: View {
    @EnvironmentObject private var service: TubeService
    @State private var query = ""
    @State private var sheetStation: Station?
    @State private var sheetPub: Pub?
    @State private var sheetPlace: SavedPlace?
    @State private var guidePDF: GuidePDF?
    @State private var showJeffSign = false
    @State private var showAddPlace = false

    var filtered: [Station] {
        guard !query.isEmpty else { return StationData.all }
        return StationData.all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Settings") {
                    Picker("App colour", selection: $service.accentHex) {
                        ForEach(TubeService.accentOptions, id: \.hex) { option in
                            HStack {
                                Circle()
                                    .fill(Color(hex: option.hex))
                                    .frame(width: 12, height: 12)
                                Text(option.name)
                            }
                            .tag(option.hex)
                        }
                    }
                    // v1.6: the version sits at the top of the tab now, so
                    // it is visible the moment the tab opens — the footer
                    // under all 97 stations was too easy to miss.
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersionText())
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Favourites") {
                    // Saved places first — the hotel is the one he will
                    // reach for most. Then favourite pubs, then stations.
                    ForEach(service.savedPlaces) { place in
                        Button {
                            sheetPlace = place
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name)
                                    Text(place.address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "mappin.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(service.favouritePubs) { pub in
                        Button {
                            sheetPub = pub
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pub.name)
                                    Text("Pub · \(pub.area) — \(pub.stationName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                            }
                        }
                    }
                    ForEach(service.favouriteStations) { station in
                        stationRow(station)
                    }
                    Button {
                        showAddPlace = true
                    } label: {
                        Label("Add a place", systemImage: "plus.circle")
                    }
                    Text("Your places, favourite pubs and favourite stations. Tap one to set it as From or To. A place plans from its own coordinates, so TfL never has to guess the name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Pubs") {
                    NavigationLink {
                        PubCrawlView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All pubs (\(PubData.all.count))")
                            Text("Search the full list, star your favourites.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Guides") {
                    Button("Tube map (PDF)") {
                        guidePDF = .tubeMap
                    }
                    Button("Step-free Tube guide (PDF)") {
                        guidePDF = .stepFree
                    }
                    Text("Bundled in the app — opens offline, even underground.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Emergency numbers") {
                    Link(destination: URL(string: "tel:999")!) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("999 — Emergency")
                                Text("Police, fire, ambulance. Works from any phone in the UK.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "phone.fill")
                        }
                    }
                    Link(destination: URL(string: "sms:61016")!) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Text 61016 — British Transport Police")
                                Text("Non-emergency, on trains and at stations. Text only.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "message.fill")
                        }
                    }
                    Link(destination: URL(string: "tel:+44800405040")!) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("British Transport Police — +44 800 40 50 40")
                                Text("Call from a US phone.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "phone.fill")
                        }
                    }
                    Text("In an emergency, always call 999. The 61016 text line may not work from a US number.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section(query.isEmpty ? "All stations (\(StationData.all.count))" : "Results") {
                    ForEach(filtered) { station in
                        stationRow(station)
                    }
                }
                Section {
                    Text("Tap a station to set it as your From or To, or to star it as a favourite. The list is bundled in the app, so search works underground with no signal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        showJeffSign = true
                    } label: {
                        Text(appVersionText())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search stations")
            .navigationTitle("Places")
            .sheet(item: $sheetStation) { station in
                StationSheet(station: station)
            }
            .sheet(item: $sheetPub) { pub in
                PubDetailView(pub: pub)
            }
            .sheet(item: $sheetPlace) { place in
                PlaceSheet(place: place)
            }
            .sheet(item: $guidePDF) { guide in
                PDFViewerView(resource: guide.fileName, title: guide.title)
            }
            .sheet(isPresented: $showAddPlace) {
                AddPlaceView()
            }
            .sheet(isPresented: $showJeffSign) {
                JeffRoundelSheet()
            }
        }
    }

    private func appVersionText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "TubeNavigator v\(version) (\(build))"
    }

    private func stationRow(_ station: Station) -> some View {
        Button {
            sheetStation = station
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                    Text(station.lineIds.map { TubeLines.name(for: $0) }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if service.isFavourite(station) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                Text("Zone \(station.zone)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PDFViewerView: View {
    let resource: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(resource: resource)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let resource: String

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        if let url = Bundle.main.url(forResource: resource, withExtension: "pdf"),
           let document = PDFDocument(url: url) {
            view.document = document
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

struct StationSheet: View {
    @EnvironmentObject private var service: TubeService
    @Environment(\.dismiss) private var dismiss
    let station: Station

    var body: some View {
        NavigationStack {
            List {
                Section(station.name) {
                    Text(station.lineIds.map { TubeLines.name(for: $0) }.joined(separator: " · "))
                    Text("Zone \(station.zone)")
                }
                Section {
                    Button("Set as From") {
                        service.fromEndpoint = .station(station)
                        dismiss()
                    }
                    Button("Set as To") {
                        service.toEndpoint = .station(station)
                        dismiss()
                    }
                    Button(service.isFavourite(station) ? "Remove from favourites" : "Add to favourites") {
                        service.toggleFavourite(station)
                    }
                }
                Section {
                    Button("Plan a journey from here") {
                        service.fromEndpoint = .station(station)
                        dismiss()
                    }
                }
            }
            .navigationTitle(station.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Saved place sheet + add a place (v1.7)

struct PlaceSheet: View {
    @EnvironmentObject private var service: TubeService
    @Environment(\.dismiss) private var dismiss
    let place: SavedPlace

    var body: some View {
        NavigationStack {
            List {
                Section(place.name) {
                    Text(place.address)
                    Text("Nearest station: \(nearestStationName)")
                }
                Section {
                    Button("Set as From") {
                        service.fromEndpoint = .place(place)
                        dismiss()
                    }
                    Button("Set as To") {
                        service.toEndpoint = .place(place)
                        dismiss()
                    }
                    Button("Plan a journey from here") {
                        service.fromEndpoint = .place(place)
                        dismiss()
                    }
                }
                Section {
                    Button("Remove this place", role: .destructive) {
                        service.removePlace(place)
                        dismiss()
                    }
                }
                Section {
                    Text("This place plans from its own coordinates, so TfL never has to guess the name — the hotel's name lookup used to resolve to the wrong Wilde.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var nearestStationName: String {
        guard let id = place.nearestStationId else { return "not recorded" }
        return StationData.station(id: id)?.name ?? "not recorded"
    }
}

struct AddPlaceView: View {
    @EnvironmentObject private var service: TubeService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var found: (display: String, lat: Double, lon: Double)?
    @State private var lookupError: String?
    @State private var isLookingUp = false

    var body: some View {
        NavigationStack {
            List {
                Section("A place of yours") {
                    TextField("Name — e.g. Borough Market", text: $name)
                        .autocorrectionDisabled()
                    TextField("Address or postcode", text: $address)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        Task { await lookup() }
                    } label: {
                        if isLookingUp {
                            ProgressView()
                        } else {
                            Text("Find this place")
                        }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isLookingUp)
                    Text("The address is looked up once, on this phone, and the coordinates are saved with the place. Journeys then plan from those coordinates — no name guessing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let found {
                    Section("Found") {
                        Text(found.display)
                        Text(String(format: "%.6f, %.6f", found.lat, found.lon))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Save this place") {
                            service.addPlace(SavedPlace(
                                name: name.trimmingCharacters(in: .whitespaces).isEmpty ? address : name.trimmingCharacters(in: .whitespaces),
                                address: address.trimmingCharacters(in: .whitespaces),
                                lat: found.lat,
                                lon: found.lon,
                                // v1.9: record the nearest station now, so
                                // the place records in Recent and can be
                                // saved as a route like the built-ins.
                                nearestStationId: StationData.nearestStation(lat: found.lat, lon: found.lon)?.id
                            ))
                            dismiss()
                        }
                    }
                }
                if let lookupError {
                    Section {
                        Text(lookupError).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func lookup() async {
        isLookingUp = true
        lookupError = nil
        found = nil
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(address)
            guard let mark = placemarks.first, let loc = mark.location else {
                lookupError = "Couldn't find that address — try the postcode."
                isLookingUp = false
                return
            }
            let display = [mark.name, mark.locality].compactMap { $0 }.joined(separator: ", ")
            found = (display.isEmpty ? address : display, loc.coordinate.latitude, loc.coordinate.longitude)
        } catch {
            lookupError = "Couldn't find that address — try the postcode. (\(error.localizedDescription))"
        }
        isLookingUp = false
    }
}

// MARK: - Jeff station easter egg

struct JeffRoundelSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // The Jeff roundel, drawn in SwiftUI — same as the app icon.
                ZStack {
                    Circle()
                        .stroke(Color(hex: "DC241F"), lineWidth: 14)
                        .frame(width: 200, height: 200)
                    Rectangle()
                        .fill(Color(hex: "0019A8"))
                        .frame(width: 190, height: 52)
                    Text("JEFF")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 40)
                Text("Jeff station")
                    .font(.title2).bold()
                Text("Mind the gap. And mind the Jeff.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .navigationTitle("Jeff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
