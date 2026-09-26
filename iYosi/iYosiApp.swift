import SwiftUI

@main struct iYosiApp: App {
    @StateObject private var state = AppState()
    @AppStorage("adultAccessAccepted") private var adultAccessAccepted = false

    var body: some Scene {
        WindowGroup {
            Group {
                if adultAccessAccepted { MapHomeView() }
                else { AdultAccessView(accepted: $adultAccessAccepted) }
            }
            .environmentObject(state)
            .task { await state.refreshAccount() }
        }
    }
}

struct AdultAccessView: View {
    @Binding var accepted: Bool
    @AppStorage("adultAccessDeclined") private var declined = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 58)).foregroundStyle(.teal)
                    .accessibilityHidden(true)
                Text("iYosi").font(.largeTitle.bold())
                Text("An informational guide to designated and community-reported smoking areas in Metro Manila.")
                    .font(.title3)
                Text("Respect smoke-free rules and shared air. Places can be unverified, disputed, prohibited, or closed. A report is not permission to smoke. Check signs, venue rules, and local law before visiting.")
                Text("For adults 18 and older. Browsing does not require an account or location access. The app uses your location only if you tap Near me. Contributions require an account and are reviewed before publication.")
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("Read privacy notice") { PrivacyNoticeView() }
                Spacer()
                if declined { Text("You must be at least 18 to use iYosi.").foregroundStyle(.red) }
                if !declined {
                    Button("I am 18 or older — continue") { accepted = true }
                        .buttonStyle(.borderedProminent)
                    Button("I am under 18") { declined = true }
                        .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
    }
}

struct PrivacyNoticeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pilot privacy notice").font(.title.bold())
                Text("You can browse without signing in. When you choose Near me, iOS supplies a foreground location to center the map. The API does not receive a background location trail. Address searches and visible map bounds are sent to the API to return results.")
                Text("If you create an account, the service stores your email, password credential, adult self-attestation, and your submitted places, confirmations, reviews, and reports. Public place and review responses do not include your account identity. Reports and moderation records are available to administrators.")
                Text("The app keeps your short-lived sign-in token in the device Keychain. You can request account deletion in Account. This pilot notice does not yet set a retention schedule or operator contact; those details must be published before a public release.")
                Text("Map imagery is supplied by Apple Maps and is subject to Apple's terms and privacy practices.")
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }.navigationTitle("Privacy")
    }
}
