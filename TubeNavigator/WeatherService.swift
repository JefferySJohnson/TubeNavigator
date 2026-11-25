import Foundation
import CoreLocation
import WeatherKit
import SwiftUI

// WeatherKit weather for TubeNavigator.
// Uses the phone's location when allowed (weather differs across London),
// falling back to Paddington (the hotel) when location is unavailable.
// Requires the WeatherKit capability on the App ID
// (com.rolltide.TubeNavigator, explicit App ID — a wildcard App ID cannot
// carry WeatherKit) and the com.apple.developer.weatherkit entitlement.
// WeatherKit worked in the iPhone 18 Pro Max simulator on 16 Nov 2026
// (live Paddington weather) — still verify on a real iPhone before the trip.
// No API key; 500,000 calls/month are included in the Developer Program.
// Apple requires the "Data from Apple Weather" attribution in the UI.
// The place name comes from reverse-geocoding the location
// (CLGeocoder), so the strip reads "Maineville" at home and "London"
// on the trip, with "Paddington" near the hotel.

@MainActor
final class WeatherViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var current: CurrentWeather?
    @Published var todayHigh: Measurement<UnitTemperature>?
    @Published var todayLow: Measurement<UnitTemperature>?
    @Published var restOfDay: [HourWeather] = []
    @Published var placeName = "London"
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let manager = CLLocationManager()
    private let paddington = CLLocation(latitude: 51.5166, longitude: -0.1765)
    private var didStart = false

    override init() {
        super.init()
        manager.delegate = self
    }

    func load() {
        guard !didStart else { return }
        didStart = true
        isLoading = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            Task { await fetch(for: paddington, place: "Paddington") }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            Task { await fetch(for: paddington, place: "Paddington") }
        default:
            break
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { await fetchWithPlace(for: location) }
    }

    private func fetchWithPlace(for location: CLLocation) async {
        let place: String
        if location.distance(from: paddington) < 2000 {
            place = "Paddington"
        } else if let locality = await localityName(for: location) {
            place = locality
        } else {
            place = "Your location"
        }
        await fetch(for: location, place: place)
    }

    private func localityName(for location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                let place = placemarks?.first
                continuation.resume(returning: place?.locality ?? place?.subLocality ?? place?.administrativeArea)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { await fetch(for: paddington, place: "Paddington") }
    }

    private func fetch(for location: CLLocation, place: String) async {
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            current = weather.currentWeather
            let today = weather.dailyForecast.first
            todayHigh = today?.highTemperature
            todayLow = today?.lowTemperature
            let now = Date()
            let calendar = Calendar.current
            restOfDay = weather.hourlyForecast.filter { hour in
                hour.date > now && calendar.isDate(hour.date, inSameDayAs: now)
            }
            placeName = place
            errorMessage = nil
        } catch {
            errorMessage = "Weather isn't available right now."
        }
        isLoading = false
    }

    func tempF(_ measurement: Measurement<UnitTemperature>?) -> String {
        guard let measurement else { return "—" }
        return "\(Int(measurement.converted(to: .fahrenheit).value.rounded()))°"
    }

    func conditionText(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear: return "Clear"
        case .cloudy: return "Cloudy"
        case .mostlyClear: return "Mostly clear"
        case .mostlyCloudy: return "Mostly cloudy"
        case .partlyCloudy: return "Partly cloudy"
        case .rain: return "Rain"
        case .heavyRain: return "Heavy rain"
        case .drizzle: return "Drizzle"
        case .snow: return "Snow"
        case .heavySnow: return "Heavy snow"
        case .sleet: return "Sleet"
        case .hail: return "Hail"
        case .thunderstorms: return "Thunderstorms"
        case .isolatedThunderstorms: return "Isolated thunderstorms"
        case .scatteredThunderstorms: return "Scattered thunderstorms"
        case .strongStorms: return "Strong storms"
        case .foggy: return "Foggy"
        case .haze: return "Haze"
        case .windy: return "Windy"
        case .blizzard: return "Blizzard"
        case .blowingDust: return "Blowing dust"
        case .freezingDrizzle: return "Freezing drizzle"
        case .freezingRain: return "Freezing rain"
        case .hurricane: return "Hurricane"
        case .tropicalStorm: return "Tropical storm"
        case .sunFlurries: return "Sun flurries"
        case .sunShowers: return "Sun showers"
        case .wintryMix: return "Wintry mix"
        default: return "—"
        }
    }
}
