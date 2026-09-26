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
            UserDefaults.standard.set(baseURL, forKey: "apiBaseURL")
            if baseURL != oldValue { signOut() }
        }
    }
    @Published private(set) var token: String?
    @Published private(set) var account: Account?
    @Published var accountError: String?

    var api: APIClient { APIClient(baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines), token: token) }
    var isSignedIn: Bool { token != nil }

    init() {
        baseURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://localhost:8000"
        token = CredentialStore.read()
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
        CredentialStore.save(nil)
        token = nil
        account = nil
        accountError = nil
    }
}

final class ForegroundLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var point: GeoPoint?
    @Published var message: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func locate() {
        message = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: message = "Location access is off. Search and map browsing still work."
        @unknown default: message = "Location is unavailable."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coordinate = locations.last?.coordinate { point = GeoPoint(coordinate) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        message = error.localizedDescription
    }
}
