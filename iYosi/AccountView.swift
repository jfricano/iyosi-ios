import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var state: AppState
    @State private var registering = false
    @State private var email = ""
    @State private var password = ""
    @State private var adultAttested = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(registering ? "Create adult account" : "Sign in to contribute") {
                    TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(registering ? .newPassword : .password)
                    if registering { Toggle("I am 18 or older", isOn: $adultAttested) }
                    Button(registering ? "Create account" : "Sign in") { Task { await authenticate() } }
                        .disabled(busy || email.isEmpty || password.isEmpty || (registering && (!adultAttested || password.count < 12 || password.count > 128)))
                }
                Section {
                    Button(registering ? "Already have an account? Sign in" : "Create an account") {
                        registering.toggle(); error = nil
                    }
                    NavigationLink("API server settings") { ServerSettingsView() }
                    if registering { Text("Passwords must be 12–128 characters. Age self-attestation is used for the private pilot.").font(.footnote) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(registering ? "Register" : "Sign in")
        }
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
                if !state.isSignedIn { AuthView() }
                else {
                    Form {
                        Section("Account") {
                            if let account = state.account { Text(account.email); Text("Role: \(account.role)") }
                            else if let accountError = state.accountError { Text(accountError).foregroundStyle(.red) }
                            Button("Sign out") { state.signOut() }
                        }
                        Section("Your proposals") {
                            if submissions.isEmpty { Text("No proposals yet.").foregroundStyle(.secondary) }
                            ForEach(submissions) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.headline)
                                    Text("\(item.intent.capitalized) · \(item.state.capitalized) · \(DateText.display(item.createdAt))")
                                    if let reason = item.decisionReason { Text(reason).font(.footnote) }
                                }
                            }
                        }
                        Section("Privacy") {
                            NavigationLink("Privacy notice") { PrivacyNoticeView() }
                            if deletionRequested { Text("Deletion request received.") }
                            else { Button("Request account deletion", role: .destructive) { showDeletionConfirmation = true } }
                        }
                        Section("API server") { NavigationLink("Server settings") { ServerSettingsView() } }
                        if let error { Text(error).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("Account")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .confirmationDialog("Request account deletion?", isPresented: $showDeletionConfirmation) {
                Button("Submit deletion request", role: .destructive) { Task { await requestDeletion() } }
            } message: { Text("An administrator will review your request.") }
            .task(id: state.token) { await load() }
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
            Section("Base URL") {
                TextField("https://api.example.com", text: $draft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("Save server") { state.baseURL = draft.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section {
                Text("Use http://localhost:8000 in the iOS Simulator with the local Compose API. Use an HTTPS URL for a remote server. Changing servers signs you out.")
                    .font(.footnote)
            }
        }
        .navigationTitle("API server")
        .onAppear { draft = state.baseURL }
    }
}
