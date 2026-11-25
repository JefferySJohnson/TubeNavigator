import Foundation

// Bundled station list for TubeNavigator.
// Station IDs are TfL NaPTAN IDs, verified against the TfL Unified API
// (StopPoint/Mode/tube,dlr,elizabeth-line) on 16 Nov 2026.
// v1.2 (16 Nov 2026): Elizabeth line, DLR and Hammersmith & City line
// labels added, verified against the TfL line stop-point lists
// (/Line/elizabeth, /Line/dlr, /Line/hammersmith-city/StopPoints).
// Limehouse, Shadwell and Hampstead added for the pub crawl
// (IDs verified via TfL StopPoint search the same day).
// Zones and lines are as published by TfL. No step-free flags are bundled
// here — step-free routing uses TfL's live accessibility data at plan time.

struct Station: Identifiable, Hashable {
    let id: String        // NaPTAN ID, e.g. 940GZZLUPAC
    let name: String
    let lineIds: [String] // e.g. ["bakerloo", "circle"]
    let zone: String
    // v1.9: coordinates from TfL StopPoint/Mode/tube,dlr,elizabeth-line
    // (fetched 19 Nov 2026; all 97 stations present). Used only to find
    // the nearest station when a place is saved — never displayed.
    let lat: Double
    let lon: Double
}

struct TubeLineInfo {
    let id: String
    let name: String
    let hex: String
}

enum TubeLines {
    static let all: [String: TubeLineInfo] = [
        "bakerloo": TubeLineInfo(id: "bakerloo", name: "Bakerloo", hex: "894E24"),
        "central": TubeLineInfo(id: "central", name: "Central", hex: "DC241F"),
        "circle": TubeLineInfo(id: "circle", name: "Circle", hex: "FFCE00"),
        "district": TubeLineInfo(id: "district", name: "District", hex: "007229"),
        "hammersmith-city": TubeLineInfo(id: "hammersmith-city", name: "Hammersmith & City", hex: "D799AF"),
        "jubilee": TubeLineInfo(id: "jubilee", name: "Jubilee", hex: "868F98"),
        "metropolitan": TubeLineInfo(id: "metropolitan", name: "Metropolitan", hex: "751056"),
        "northern": TubeLineInfo(id: "northern", name: "Northern", hex: "000000"),
        "piccadilly": TubeLineInfo(id: "piccadilly", name: "Piccadilly", hex: "0019A8"),
        "victoria": TubeLineInfo(id: "victoria", name: "Victoria", hex: "00A0E2"),
        "waterloo-city": TubeLineInfo(id: "waterloo-city", name: "Waterloo & City", hex: "76D0BD"),
        "dlr": TubeLineInfo(id: "dlr", name: "DLR", hex: "00AFAD"),
        "elizabeth": TubeLineInfo(id: "elizabeth", name: "Elizabeth line", hex: "9364CD"),
    ]

    static func name(for id: String) -> String {
        all[id]?.name ?? id.capitalized
    }
}

enum StationData {
    static let all: [Station] = [
        Station(id: "940GZZLUALD", name: "Aldgate", lineIds: ["circle", "metropolitan"], zone: "1", lat: 51.514246, lon: -0.075689),
        Station(id: "940GZZLUADE", name: "Aldgate East", lineIds: ["district", "hammersmith-city"], zone: "1", lat: 51.515037, lon: -0.072384),
        Station(id: "940GZZLUAGL", name: "Angel", lineIds: ["northern"], zone: "1", lat: 51.531788, lon: -0.105919),
        Station(id: "940GZZLUBST", name: "Baker Street", lineIds: ["bakerloo", "circle", "hammersmith-city", "jubilee", "metropolitan"], zone: "1", lat: 51.522883, lon: -0.157130),
        Station(id: "940GZZLUBNK", name: "Bank", lineIds: ["central", "dlr", "northern", "waterloo-city"], zone: "1", lat: 51.513132, lon: -0.090047),
        Station(id: "940GZZLUBBN", name: "Barbican", lineIds: ["circle", "hammersmith-city", "metropolitan"], zone: "1", lat: 51.520275, lon: -0.097993),
        Station(id: "940GZZLUBWT", name: "Bayswater", lineIds: ["circle", "district"], zone: "1", lat: 51.512284, lon: -0.187938),
        Station(id: "940GZZLUBMY", name: "Bermondsey", lineIds: ["jubilee"], zone: "2", lat: 51.497750, lon: -0.063993),
        Station(id: "940GZZLUBKF", name: "Blackfriars", lineIds: ["circle", "district"], zone: "1", lat: 51.511581, lon: -0.103659),
        Station(id: "940GZZLUBND", name: "Bond Street", lineIds: ["central", "elizabeth", "jubilee"], zone: "1", lat: 51.514304, lon: -0.149723),
        Station(id: "940GZZLUBOR", name: "Borough", lineIds: ["northern"], zone: "1", lat: 51.501199, lon: -0.093370),
        Station(id: "940GZZLUBXN", name: "Brixton", lineIds: ["victoria"], zone: "2", lat: 51.462618, lon: -0.114888),
        Station(id: "940GZZLUCTN", name: "Camden Town", lineIds: ["northern"], zone: "2", lat: 51.539292, lon: -0.142740),
        Station(id: "940GZZLUCWR", name: "Canada Water", lineIds: ["jubilee"], zone: "2", lat: 51.497931, lon: -0.049405),
        Station(id: "940GZZLUCYF", name: "Canary Wharf", lineIds: ["dlr", "elizabeth", "jubilee"], zone: "2", lat: 51.503488, lon: -0.018246),
        Station(id: "940GZZLUCGT", name: "Canning Town", lineIds: ["dlr", "jubilee"], zone: "2/3", lat: 51.513584, lon: 0.008322),
        Station(id: "940GZZLUCHL", name: "Chancery Lane", lineIds: ["central"], zone: "1", lat: 51.518247, lon: -0.111583),
        Station(id: "940GZZLUCHX", name: "Charing Cross", lineIds: ["bakerloo", "northern"], zone: "1", lat: 51.507410, lon: -0.127277),
        Station(id: "940GZZLUCPC", name: "Clapham Common", lineIds: ["northern"], zone: "2", lat: 51.461742, lon: -0.138317),
        Station(id: "940GZZLUCPN", name: "Clapham North", lineIds: ["northern"], zone: "2", lat: 51.465135, lon: -0.130016),
        Station(id: "940GZZLUCPS", name: "Clapham South", lineIds: ["northern"], zone: "2/3", lat: 51.452654, lon: -0.147582),
        Station(id: "940GZZLUCGN", name: "Covent Garden", lineIds: ["piccadilly"], zone: "1", lat: 51.513093, lon: -0.124436),
        Station(id: "940GZZLUERB", name: "Edgware Road (Bakerloo)", lineIds: ["bakerloo"], zone: "1", lat: 51.520299, lon: -0.170150),
        Station(id: "940GZZLUERC", name: "Edgware Road (Circle)", lineIds: ["circle", "district", "hammersmith-city"], zone: "1", lat: 51.519858, lon: -0.167832),
        Station(id: "940GZZLUEAC", name: "Elephant & Castle", lineIds: ["bakerloo", "northern"], zone: "1/2", lat: 51.494536, lon: -0.100606),
        Station(id: "940GZZLUEMB", name: "Embankment", lineIds: ["bakerloo", "circle", "district", "northern"], zone: "1", lat: 51.507058, lon: -0.122666),
        Station(id: "940GZZLUEUS", name: "Euston", lineIds: ["northern", "victoria"], zone: "1", lat: 51.528344, lon: -0.132300),
        Station(id: "940GZZLUESQ", name: "Euston Square", lineIds: ["circle", "hammersmith-city", "metropolitan"], zone: "1", lat: 51.525604, lon: -0.135829),
        Station(id: "940GZZLUFCN", name: "Farringdon", lineIds: ["circle", "elizabeth", "hammersmith-city", "metropolitan"], zone: "1", lat: 51.520252, lon: -0.104913),
        Station(id: "940GZZLUFYR", name: "Finchley Road", lineIds: ["jubilee", "metropolitan"], zone: "2", lat: 51.546825, lon: -0.179845),
        Station(id: "940GZZLUFPK", name: "Finsbury Park", lineIds: ["piccadilly", "victoria"], zone: "2", lat: 51.564158, lon: -0.106825),
        Station(id: "940GZZLUFBY", name: "Fulham Broadway", lineIds: ["district"], zone: "2", lat: 51.480081, lon: -0.195422),
        Station(id: "940GZZLUGTR", name: "Gloucester Road", lineIds: ["circle", "district", "piccadilly"], zone: "1", lat: 51.494316, lon: -0.182658),
        Station(id: "940GZZLUGDG", name: "Goodge Street", lineIds: ["northern"], zone: "1", lat: 51.520599, lon: -0.134361),
        Station(id: "940GZZLUGPS", name: "Great Portland Street", lineIds: ["circle", "hammersmith-city", "metropolitan"], zone: "1", lat: 51.523840, lon: -0.144262),
        Station(id: "940GZZLUGPK", name: "Green Park", lineIds: ["jubilee", "piccadilly", "victoria"], zone: "1", lat: 51.506947, lon: -0.142787),
        Station(id: "940GZZLUHSD", name: "Hammersmith", lineIds: ["district", "hammersmith-city", "piccadilly"], zone: "2", lat: 51.492300, lon: -0.223620),
        Station(id: "940GZZLUHTD", name: "Hampstead", lineIds: ["northern"], zone: "2/3", lat: 51.556239, lon: -0.177464),
        Station(id: "940GZZLUHRC", name: "Heathrow Terminals 2 & 3", lineIds: ["elizabeth", "piccadilly"], zone: "6", lat: 51.471235, lon: -0.452265),
        Station(id: "940GZZLUHR4", name: "Heathrow Terminal 4", lineIds: ["elizabeth", "piccadilly"], zone: "6", lat: 51.458524, lon: -0.445771),
        Station(id: "940GZZLUHR5", name: "Heathrow Terminal 5", lineIds: ["elizabeth", "piccadilly"], zone: "6", lat: 51.470052, lon: -0.490560),
        Station(id: "940GZZLUHSK", name: "High Street Kensington", lineIds: ["circle", "district"], zone: "1", lat: 51.501055, lon: -0.192792),
        Station(id: "940GZZLUHBN", name: "Holborn", lineIds: ["central", "piccadilly"], zone: "1", lat: 51.517580, lon: -0.120475),
        Station(id: "940GZZLUHPK", name: "Holland Park", lineIds: ["central"], zone: "2", lat: 51.507143, lon: -0.205679),
        Station(id: "940GZZLUHPC", name: "Hyde Park Corner", lineIds: ["piccadilly"], zone: "1", lat: 51.503035, lon: -0.152441),
        Station(id: "940GZZLUKNG", name: "Kennington", lineIds: ["northern"], zone: "1/2", lat: 51.488337, lon: -0.105963),
        Station(id: "940GZZLUKBN", name: "Kilburn", lineIds: ["jubilee"], zone: "2", lat: 51.547183, lon: -0.204248),
        Station(id: "940GZZLUKPK", name: "Kilburn Park", lineIds: ["bakerloo"], zone: "2", lat: 51.534979, lon: -0.194232),
        Station(id: "940GZZLUKSX", name: "King's Cross St. Pancras", lineIds: ["circle", "hammersmith-city", "metropolitan", "northern", "piccadilly", "victoria"], zone: "1", lat: 51.530663, lon: -0.123194),
        Station(id: "940GZZLUKNB", name: "Knightsbridge", lineIds: ["piccadilly"], zone: "1", lat: 51.501669, lon: -0.160508),
        Station(id: "940GZZLULGT", name: "Lancaster Gate", lineIds: ["central"], zone: "1", lat: 51.511723, lon: -0.175494),
        Station(id: "940GZZLULSQ", name: "Leicester Square", lineIds: ["northern", "piccadilly"], zone: "1", lat: 51.511386, lon: -0.128426),
        Station(id: "940GZZDLLIM", name: "Limehouse", lineIds: ["dlr"], zone: "2", lat: 51.512393, lon: -0.039809),
        Station(id: "940GZZLULVT", name: "Liverpool Street", lineIds: ["central", "circle", "elizabeth", "hammersmith-city", "metropolitan"], zone: "1", lat: 51.517372, lon: -0.083182),
        Station(id: "940GZZLULNB", name: "London Bridge", lineIds: ["jubilee", "northern"], zone: "1", lat: 51.505721, lon: -0.088873),
        Station(id: "940GZZLUMVL", name: "Maida Vale", lineIds: ["bakerloo"], zone: "2", lat: 51.529777, lon: -0.185758),
        Station(id: "940GZZLUMBA", name: "Marble Arch", lineIds: ["central"], zone: "1", lat: 51.513424, lon: -0.158953),
        Station(id: "940GZZLUMYB", name: "Marylebone", lineIds: ["bakerloo"], zone: "1", lat: 51.522322, lon: -0.163207),
        Station(id: "940GZZLUMMT", name: "Monument", lineIds: ["circle", "district"], zone: "1", lat: 51.510700, lon: -0.085969),
        Station(id: "940GZZLUMGT", name: "Moorgate", lineIds: ["circle", "hammersmith-city", "metropolitan", "northern"], zone: "1", lat: 51.518176, lon: -0.088322),
        Station(id: "940GZZLUNGW", name: "North Greenwich", lineIds: ["jubilee"], zone: "2/3", lat: 51.500470, lon: 0.004287),
        Station(id: "940GZZLUNHG", name: "Notting Hill Gate", lineIds: ["central", "circle", "district"], zone: "1/2", lat: 51.509128, lon: -0.196104),
        Station(id: "940GZZLUODS", name: "Old Street", lineIds: ["northern"], zone: "1", lat: 51.525864, lon: -0.087770),
        Station(id: "940GZZLUOXC", name: "Oxford Circus", lineIds: ["bakerloo", "central", "victoria"], zone: "1", lat: 51.515224, lon: -0.141903),
        Station(id: "940GZZLUPAC", name: "Paddington", lineIds: ["bakerloo", "circle", "district", "elizabeth", "hammersmith-city"], zone: "1", lat: 51.516581, lon: -0.175689),
        Station(id: "940GZZLUPCC", name: "Piccadilly Circus", lineIds: ["bakerloo", "piccadilly"], zone: "1", lat: 51.510050, lon: -0.133798),
        Station(id: "940GZZLUPCO", name: "Pimlico", lineIds: ["victoria"], zone: "1", lat: 51.489097, lon: -0.133761),
        Station(id: "940GZZLUPYB", name: "Putney Bridge", lineIds: ["district"], zone: "2", lat: 51.468262, lon: -0.208731),
        Station(id: "940GZZLUQWY", name: "Queensway", lineIds: ["central"], zone: "1", lat: 51.510312, lon: -0.187152),
        Station(id: "940GZZLURGP", name: "Regent's Park", lineIds: ["bakerloo"], zone: "1", lat: 51.523344, lon: -0.146444),
        Station(id: "940GZZLURMD", name: "Richmond", lineIds: ["district"], zone: "4", lat: 51.463237, lon: -0.301336),
        Station(id: "940GZZLURSQ", name: "Russell Square", lineIds: ["piccadilly"], zone: "1", lat: 51.523073, lon: -0.124285),
        Station(id: "940GZZDLSHA", name: "Shadwell", lineIds: ["dlr"], zone: "2", lat: 51.511693, lon: -0.056643),
        Station(id: "940GZZLUSBC", name: "Shepherd's Bush", lineIds: ["central"], zone: "2", lat: 51.504376, lon: -0.218813),
        Station(id: "940GZZLUSSQ", name: "Sloane Square", lineIds: ["circle", "district"], zone: "1", lat: 51.492270, lon: -0.156377),
        Station(id: "940GZZLUSKS", name: "South Kensington", lineIds: ["circle", "district", "piccadilly"], zone: "1", lat: 51.494094, lon: -0.174138),
        Station(id: "940GZZLUSWK", name: "Southwark", lineIds: ["jubilee"], zone: "1", lat: 51.504270, lon: -0.105331),
        Station(id: "940GZZLUSPU", name: "St. Paul's", lineIds: ["central"], zone: "1", lat: 51.514936, lon: -0.097567),
        Station(id: "940GZZLUSKW", name: "Stockwell", lineIds: ["northern", "victoria"], zone: "2", lat: 51.472184, lon: -0.122644),
        Station(id: "940GZZLUSTD", name: "Stratford", lineIds: ["central", "dlr", "elizabeth", "jubilee"], zone: "2/3", lat: 51.541806, lon: -0.003458),
        Station(id: "940GZZLUSWC", name: "Swiss Cottage", lineIds: ["jubilee"], zone: "2", lat: 51.543681, lon: -0.174894),
        Station(id: "940GZZLUTMP", name: "Temple", lineIds: ["circle", "district"], zone: "1", lat: 51.511006, lon: -0.114260),
        Station(id: "940GZZLUTCR", name: "Tottenham Court Road", lineIds: ["central", "elizabeth", "northern"], zone: "1", lat: 51.516426, lon: -0.130410),
        Station(id: "940GZZLUTMH", name: "Tottenham Hale", lineIds: ["victoria"], zone: "3", lat: 51.588108, lon: -0.060241),
        Station(id: "940GZZLUTWH", name: "Tower Hill", lineIds: ["circle", "district"], zone: "1", lat: 51.509971, lon: -0.076546),
        Station(id: "940GZZLUVXL", name: "Vauxhall", lineIds: ["victoria"], zone: "1/2", lat: 51.485743, lon: -0.124204),
        Station(id: "940GZZLUVIC", name: "Victoria", lineIds: ["circle", "district", "victoria"], zone: "1", lat: 51.496359, lon: -0.143102),
        Station(id: "940GZZLUWRR", name: "Warren Street", lineIds: ["northern", "victoria"], zone: "1", lat: 51.524951, lon: -0.138321),
        Station(id: "940GZZLUWKA", name: "Warwick Avenue", lineIds: ["bakerloo"], zone: "2", lat: 51.523263, lon: -0.183783),
        Station(id: "940GZZLUWLO", name: "Waterloo", lineIds: ["bakerloo", "jubilee", "northern", "waterloo-city"], zone: "1", lat: 51.503299, lon: -0.114780),
        Station(id: "940GZZLUWHP", name: "West Hampstead", lineIds: ["jubilee"], zone: "2", lat: 51.546638, lon: -0.191059),
        Station(id: "940GZZLUWHM", name: "West Ham", lineIds: ["district", "dlr", "hammersmith-city", "jubilee"], zone: "2/3", lat: 51.528136, lon: 0.005055),
        Station(id: "940GZZLUWSM", name: "Westminster", lineIds: ["circle", "district", "jubilee"], zone: "1", lat: 51.501320, lon: -0.124861),
        Station(id: "940GZZLUWCY", name: "White City", lineIds: ["central"], zone: "2", lat: 51.511959, lon: -0.224297),
        Station(id: "940GZZLUWPL", name: "Whitechapel", lineIds: ["district", "elizabeth", "hammersmith-city"], zone: "2", lat: 51.519518, lon: -0.059971),
        Station(id: "940GZZLUWIM", name: "Wimbledon", lineIds: ["district"], zone: "3", lat: 51.421207, lon: -0.206573),
        Station(id: "940GZZLUWYP", name: "Wembley Park", lineIds: ["jubilee", "metropolitan"], zone: "4", lat: 51.563198, lon: -0.279262),
    ].sorted { $0.name < $1.name }

    // Pre-loaded favourites for the Dec 2026 London trip.
    // Paddington = Wilde Aparthotels base; London Bridge = Borough Market.
    static let defaultFavouriteIds: [String] = [
        "940GZZLUPAC", // Paddington
        "940GZZLULNB", // London Bridge
        "940GZZLUWSM", // Westminster
        "940GZZLUOXC", // Oxford Circus
        "940GZZLUKSX", // King's Cross St. Pancras
        "940GZZLUGPK", // Green Park
        "940GZZLUBNK", // Bank
        "940GZZLUVIC", // Victoria
    ]

    static func station(id: String) -> Station? {
        all.first { $0.id == id }
    }

    // v1.9: nearest station to a point, straight-line (haversine) distance
    // over the 97 stations in the app — the same match the pub import used
    // offline in v1.3. Used when a place is saved (Add a place) and by the
    // v1.9 upgrade migration for places saved without one.
    static func nearestStation(lat: Double, lon: Double) -> Station? {
        all.min(by: { distanceKm(fromLat: lat, fromLon: lon, to: $0) < distanceKm(fromLat: lat, fromLon: lon, to: $1) })
    }

    private static func distanceKm(fromLat lat1: Double, fromLon lon1: Double, to station: Station) -> Double {
        let radius = 6371.0
        let p1 = lat1 * .pi / 180, p2 = station.lat * .pi / 180
        let dp = (station.lat - lat1) * .pi / 180
        let dl = (station.lon - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * radius * asin(sqrt(a))
    }
}
