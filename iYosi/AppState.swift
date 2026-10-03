import Foundation
import Security
import CoreLocation
import Combine

enum CredentialStore {
    private static let service = "com.orcasolutions.iyosi.api"
    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "access_token",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String?) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "access_token"]
        SecItemDelete(query as CFDictionary)
        guard let token, let data = token.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

@MainActor final class AppState: ObservableObject {
    @Published var baseURL: String {
        didSet {
            #if DEBUG
            if DesignPreview.enabled { return }
            #endif
            UserDefaults.standard.set(baseURL, forKey: "apiBaseURL")
            if baseURL != oldValue { signOut() }
        }
    }
    @Published private(set) var token: String?
    @Published private(set) var account: Account?
    @Published var accountError: String?

    var api: APIClient {
        #if DEBUG
        if DesignPreview.enabled {
            return APIClient(baseURL: "http://localhost:8000", token: token, session: DesignPreview.session)
        }
        #endif
        return APIClient(baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines), token: token)
    }
    var isSignedIn: Bool { token != nil }
    var isDesignPreview: Bool {
        #if DEBUG
        return DesignPreview.enabled
        #else
        return false
        #endif
    }

    init() {
        baseURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://localhost:8000"
        #if DEBUG
        token = DesignPreview.enabled ? (DesignPreview.signedIn ? "design-preview" : nil) : CredentialStore.read()
        #else
        token = CredentialStore.read()
        #endif
    }

    func authenticate(email: String, password: String, registering: Bool) async throws {
        let credentials = registering ? try await api.register(email: email, password: password)
                                      : try await api.login(email: email, password: password)
        token = credentials.accessToken
        CredentialStore.save(token)
        await refreshAccount()
    }
    func refreshAccount() async {
        guard isSignedIn else { account = nil; return }
        do { account = try await api.me(); accountError = nil }
        catch {
            accountError = error.localizedDescription
            if let apiError = error as? APIError, apiError.code == "unauthenticated" { signOut() }
        }
    }
    func signOut() {
        #if DEBUG
        if !DesignPreview.enabled { CredentialStore.save(nil) }
        #else
        CredentialStore.save(nil)
        #endif
        token = nil
        account = nil
        accountError = nil
    }
}

final class ForegroundLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationRequested = false
    @Published var point: GeoPoint?
    @Published var message: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func locate() {
        message = nil
        locationRequested = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted:
            locationRequested = false
            message = "Location access is off. Search and map browsing still work."
        @unknown default:
            locationRequested = false
            message = "Location is unavailable."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if locationRequested && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) {
            manager.requestLocation()
        } else if locationRequested && (manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted) {
            locationRequested = false
            message = "Location access is off. Search and map browsing still work."
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locationRequested = false
        if let coordinate = locations.last?.coordinate { point = GeoPoint(coordinate) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationRequested = false
        message = "Location is unavailable. Search and map browsing still work."
    }
}
