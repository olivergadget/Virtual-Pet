import CoreLocation
import Foundation

/// Location does two jobs here. It's requested at startup alongside notifications, and it
/// gives the pet a sense of *home*, so it can react to you being out and about.
@Observable
final class PetLocator {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var coordinate: CLLocationCoordinate2D?

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    private let manager = CLLocationManager()
    private let relay = LocationRelay()
    private var pump: Task<Void, Never>?

    init() {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 150
        manager.delegate = relay
        authorization = manager.authorizationStatus

        let events = relay.events
        pump = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .authorization(let status):
                    self.authorization = status
                    if self.isAuthorized { self.manager.startUpdatingLocation() }
                case .location(let coordinate):
                    self.coordinate = coordinate
                }
            }
        }
    }

    /// Shows the system prompt, or resumes updates if permission was granted previously.
    func requestAccess() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
        authorization = manager.authorizationStatus
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// How far the phone is from the pet's den, in metres.
    func distanceFromHome(of pet: Pet) -> CLLocationDistance? {
        guard let latitude = pet.homeLatitude,
              let longitude = pet.homeLongitude,
              let coordinate
        else { return nil }
        let home = CLLocation(latitude: latitude, longitude: longitude)
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return here.distance(from: home)
    }

    /// A friendly one-liner about where the pet thinks you are.
    func homeStatus(for pet: Pet) -> String? {
        guard let distance = distanceFromHome(of: pet) else { return nil }
        switch distance {
        case ..<120:
            return "\(pet.name) can tell you're home."
        case ..<2_000:
            return "\(pet.name) reckons you're somewhere in the neighbourhood."
        case ..<30_000:
            let kilometres = distance / 1_000
            return String(format: "%.0f km from the den. %@ is watching the door.", kilometres, pet.name)
        default:
            let kilometres = distance / 1_000
            return String(format: "%.0f km away. %@ has taken this personally.", kilometres, pet.name)
        }
    }
}

/// Core Location's delegate callbacks land outside the main actor's world, so they are
/// funnelled through an async stream instead of touching model state directly.
private nonisolated final class LocationRelay: NSObject, CLLocationManagerDelegate {
    enum Event: Sendable {
        case authorization(CLAuthorizationStatus)
        case location(CLLocationCoordinate2D)
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    override init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.events = stream
        self.continuation = continuation
        super.init()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        continuation.yield(.authorization(manager.authorizationStatus))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        continuation.yield(.location(latest.coordinate))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Nothing to do: the pet simply won't know where home is this session.
    }
}
