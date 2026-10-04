import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var state: AppState
    /// Account presents this inside its own navigation so its Done action stays available.
    var embedded = false
    @State private var registering = false
    @State private var email = ""
    @State private var password = ""
    @State private var adultAttested = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Group {
            if embedded { form }
            else {
                NavigationStack {
                    form
                        .navigationTitle(registering ? "Create account" : "Sign in")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }
    private var form: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    GuideEyebrow(text: "A practical city guide")
                    Text(registering ? "Help keep the guide current." : "A little local knowledge goes a long way.")
                        .font(GuideTheme.editorial(28)).fixedSize(horizontal: false, vertical: true)
                    Text("Browse places without an account. Sign in to share a report, review, or correction.")
                        .font(GuideTheme.body(15, relativeTo: .subheadline)).foregroundStyle(GuideTheme.muted)
                }.padding(.vertical, 6)
            }.listRowBackground(Color.clear)

            Section {
                TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password).textContentType(registering ? .newPassword : .password)
                if registering { Toggle("I am 18 or older", isOn: $adultAttested) }
                Button { Task { await authenticate() } } label: {
                    HStack {
                        if busy { ProgressView().tint(GuideTheme.paper) }
                        Text(registering ? "Create account" : "Sign in")
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(GuideButtonStyle())
                .disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 || password.isEmpty || (registering && (!adultAttested || password.count < 12 || password.count > 128)))
            } header: {
                Text(registering ? "Create an adult account" : "Sign in to contribute")
            } footer: {
                if registering { Text("Use a password of 12–128 characters. Age self-attestation is used for the private pilot.") }
            }.listRowBackground(GuideTheme.surface)

            Section {
                Button(registering ? "Already have an account? Sign in" : "Create an account") {
                    registering.toggle(); error = nil
                }
                NavigationLink("API server settings") { ServerSettingsView() }
            }.listRowBackground(GuideTheme.surface)
            if let error {
                Section { GuideNotice(text: error, symbol: "exclamationmark.triangle", warning: true) }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }.guideForm()
    }
    private func authenticate() async {
        busy = true; error = nil
        do { try await state.authenticate(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, registering: registering) }
        catch { self.error = error.localizedDescription }
        busy = false
    }
}

struct AccountView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var submissions: [SubmissionStatus] = []
    @State private var error: String?
    @State private var deletionRequested = false
    @State private var showDeletionConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if !state.isSignedIn { AuthView(embedded: true) }
                else {
                    Form {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                GuideEyebrow(text: "Your account")
                                Text("Local knowledge. Shared with care.")
                                    .font(GuideTheme.editorial(27)).fixedSize(horizontal: false, vertical: true)
                                if let account = state.account {
                                    Text(account.email).textSelection(.enabled)
                                    Text("Role: \(account.role)").font(.footnote).foregroundStyle(GuideTheme.muted)
                                } else if let accountError = state.accountError {
                                    GuideNotice(text: accountError, symbol: "exclamationmark.triangle", warning: true)
                                }
                            }.padding(.vertical, 6)
                            Button("Sign out") { state.signOut() }
                        }.listRowBackground(GuideTheme.surface)
                        Section("Your proposals") {
                            if submissions.isEmpty { Text("No proposals yet.").foregroundStyle(GuideTheme.muted) }
                            ForEach(submissions) { item in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.name).font(GuideTheme.heading(17, relativeTo: .headline))
                                    Label("\(item.intent.capitalized) · \(item.state.capitalized)", systemImage: "doc.text")
                                        .font(GuideTheme.body(14, relativeTo: .subheadline)).foregroundStyle(GuideTheme.muted)
                                    Text(DateText.display(item.createdAt)).font(.caption).foregroundStyle(GuideTheme.muted)
                                    if let reason = item.decisionReason { Text(reason).font(.footnote) }
                                }.padding(.vertical, 5)
                            }
                        }.listRowBackground(GuideTheme.surface)
                        Section("Privacy") {
                            NavigationLink("Privacy notice") { PrivacyNoticeView() }
                            if deletionRequested { Label("Deletion request received.", systemImage: "checkmark.circle").foregroundStyle(GuideTheme.teal) }
                            else {
                                Button("Request account deletion", role: .destructive) { showDeletionConfirmation = true }
                                    .tint(GuideTheme.warning)
                            }
                        }.listRowBackground(GuideTheme.surface)
                        Section("API server") {
                            NavigationLink("Server settings") { ServerSettingsView() }
                        }.listRowBackground(GuideTheme.surface)
                        if let error {
                            Section { GuideNotice(text: error, symbol: "exclamationmark.triangle", warning: true) }
                                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        }
                    }.guideForm()
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .confirmationDialog("Request account deletion?", isPresented: $showDeletionConfirmation) {
                Button("Submit deletion request", role: .destructive) { Task { await requestDeletion() } }
            } message: { Text("An administrator will review your request. Once it is approved, your reviews are removed and the text you wrote in submissions, confirmations and reports is erased. Places already published stay in the guide.") }
            .task(id: state.token) { await load() }
            .guideScreen()
        }
    }
    private func load() async {
        guard state.isSignedIn else { submissions = []; return }
        await state.refreshAccount()
        do { submissions = try await state.api.submissions() }
        catch { self.error = error.localizedDescription }
    }
    private func requestDeletion() async {
        do { _ = try await state.api.deletionRequest(); deletionRequested = true }
        catch { self.error = error.localizedDescription }
    }
}

struct ServerSettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var draft = ""
    var body: some View {
        Form {
            Section {
                TextField("https://api.example.com", text: $draft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("Save server") { state.baseURL = draft.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: { Text("Base URL") }
            footer: { Text("Changing servers signs you out.") }
                .listRowBackground(GuideTheme.surface)
            Section {
                GuideNotice(text: "Use http://localhost:8000 in the iOS Simulator with the local Compose API. Use an HTTPS URL for a remote server.", symbol: "network")
            }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
        .guideForm()
        .navigationTitle("API server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = state.baseURL }
    }
}
