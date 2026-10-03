import SwiftUI

@main struct iYosiApp: App {
    @StateObject private var state = AppState()
    @AppStorage("adultAccessAccepted") private var adultAccessAccepted = false

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let preview = DesignPreview.screen { DesignPreviewRoot(screen: preview) }
                else { appContent }
                #else
                appContent
                #endif
            }
            .environmentObject(state)
            .tint(GuideTheme.tealInk)
            .task { await state.refreshAccount() }
        }
    }

    @ViewBuilder private var appContent: some View {
        if adultAccessAccepted { MapHomeView() }
        else { AdultAccessView(accepted: $adultAccessAccepted) }
    }
}

struct AdultAccessView: View {
    @Binding var accepted: Bool
    @AppStorage("adultAccessDeclined") private var storedDeclined = false
    @State private var previewDeclined = false

    private var declined: Bool {
        #if DEBUG
        if DesignPreview.enabled { return previewDeclined }
        #endif
        return storedDeclined
    }

    private func declineAccess() {
        #if DEBUG
        if DesignPreview.enabled { previewDeclined = true; return }
        #endif
        storedDeclined = true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GuideWordmark(size: 34)
                    VStack(alignment: .leading, spacing: 12) {
                        GuideEyebrow(text: "A Metro Manila place guide")
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Find the place.").font(GuideTheme.heading(38, relativeTo: .largeTitle)).tracking(-1.5)
                            Text("Check the status.").font(GuideTheme.editorial(36, relativeTo: .largeTitle))
                                .foregroundStyle(GuideTheme.teal).tracking(-1)
                        }.accessibilityElement(children: .combine)
                        Text("A guide to designated smoking areas and community reports, with context before you make the trip.")
                            .font(GuideTheme.body(17)).foregroundStyle(GuideTheme.muted)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Image("CityGuideIllustration").resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                        Text("ILLUSTRATED CITY BLOCK · FICTIONAL")
                            .font(GuideTheme.heading(9, relativeTo: .caption2)).tracking(1.2)
                            .foregroundStyle(GuideTheme.muted)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        GuideEyebrow(text: "Every place, in context")
                        GuideFact(title: "Status", value: "Reviewed evidence and unverified reports get different labels.", symbol: "checkmark.seal")
                        GuideFact(title: "Latest check", value: "Read the last confirmation and access note before directions.", symbol: "clock")
                    }.guideCard()
                    Text("Respect smoke-free rules and shared air. A report is not permission to smoke. Check posted signs, venue rules, and local law.")
                        .font(GuideTheme.body(14, relativeTo: .subheadline)).foregroundStyle(GuideTheme.muted)
                    Text("For adults 18 and older. Browse without an account or location access. Location is requested only when you choose Near me; an account is needed to contribute.")
                        .font(GuideTheme.body(14, relativeTo: .subheadline)).foregroundStyle(GuideTheme.muted)
                }
                .frame(maxWidth: 620, alignment: .leading).padding(24).frame(maxWidth: .infinity)
            }.guideScreen()
                .safeAreaInset(edge: .bottom) { accessActions }
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var accessActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if declined {
                GuideNotice(text: "You must be at least 18 to use iYosi.", symbol: "person.crop.circle.badge.exclamationmark", warning: true)
            } else {
                Button { accepted = true } label: {
                    HStack {
                        Text("I am 18 or older — continue").fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }.buttonStyle(GuideButtonStyle())
            }
            ViewThatFits(in: .horizontal) {
                HStack { secondaryAccessActions }
                VStack(alignment: .leading) { secondaryAccessActions }
            }
        }
        .font(GuideTheme.body(13, relativeTo: .caption)).foregroundStyle(GuideTheme.ink).tint(GuideTheme.tealInk)
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
        .background(GuideTheme.surface)
        .overlay(alignment: .top) { Rectangle().fill(GuideTheme.line).frame(height: 1) }
    }

    @ViewBuilder private var secondaryAccessActions: some View {
        if !declined {
            Button("I am under 18") { declineAccess() }.frame(minHeight: 44).foregroundStyle(GuideTheme.muted)
        }
        Spacer(minLength: 12)
        NavigationLink("Privacy notice") { PrivacyNoticeView() }.frame(minHeight: 44)
    }
}

struct PrivacyNoticeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GuideEyebrow(text: "Consideration for shared air")
                Text("Your information.").font(GuideTheme.heading(30))
                Text("Pilot privacy notice").font(GuideTheme.editorial(25)).foregroundStyle(GuideTheme.teal)
                Text("You can browse without signing in. When you choose Near me, iOS supplies a foreground location to center the map. The API does not receive a background location trail. Address searches and visible map bounds are sent to the API to return results.")
                Text("If you create an account, the service stores your email, password credential, adult self-attestation, and your submitted places, confirmations, reviews, and reports. Public place and review responses do not include your account identity. Reports and moderation records are available to administrators.")
                Text("The app keeps your short-lived sign-in token in the device Keychain. You can request account deletion in Account. This pilot notice does not yet set a retention schedule or operator contact; those details must be published before a public release.")
                Text("Map imagery is supplied by Apple Maps and is subject to Apple's terms and privacy practices.")
            }.frame(maxWidth: 620, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }.guideScreen().navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
    }
}
