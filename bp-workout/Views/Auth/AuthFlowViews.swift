import SwiftUI

// MARK: - Shared chrome (matches ImportProgramTextView / Workout hub)

private struct AuthFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(BlueprintTheme.cream)
            .padding(12)
            .background(BlueprintTheme.cardInner)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BlueprintTheme.border, lineWidth: 1)
            )
    }
}

extension View {
    fileprivate func authFieldChrome() -> some View {
        modifier(AuthFieldChrome())
    }
}

private struct AuthSecondaryButtonLabel: View {
    let title: String
    let systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Root

/// Wraps the main app: email/password session required (no silent device-only accounts).
struct AuthRootView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject private var auth: SupabaseSessionManager = .shared

    var body: some View {
        Group {
            switch auth.phase {
            case .checking:
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(BlueprintTheme.purple)
                        .scaleEffect(1.1)
                    Text("Loading…")
                        .font(.subheadline)
                        .foregroundStyle(BlueprintTheme.mutedLight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BlueprintTheme.bg)
            case .signedOut:
                AuthLoginView()
            case .signedIn:
                if auth.awaitingPasswordResetCompletion {
                    AuthSetNewPasswordView()
                } else {
                    RootView()
                        .environmentObject(appSettings)
                        .environmentObject(UserProgramLibrary.shared)
                }
            }
        }
        .task {
            await auth.bootstrap()
        }
        .animation(.easeInOut(duration: 0.2), value: auth.phase)
        .animation(.easeInOut(duration: 0.2), value: auth.awaitingPasswordResetCompletion)
    }
}

// MARK: - Sign in

private struct AuthLoginView: View {
    @ObservedObject private var auth: SupabaseSessionManager = .shared
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showSignUp = false
    @State private var showForgot = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BLUEPRINT")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BlueprintTheme.purple)
                            .tracking(1.6)
                        Text("Welcome back")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(BlueprintTheme.cream)
                        Text("Sign in to sync workouts and programs, and to use AI import and suggestions.")
                            .font(.subheadline)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.muted)
                        TextField("you@example.com", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .authFieldChrome()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.muted)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .authFieldChrome()
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(BlueprintTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack(spacing: 10) {
                            if busy {
                                ProgressView()
                                    .tint(BlueprintTheme.cream)
                            }
                            Text("Sign in")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BlueprintTheme.purple)
                    .disabled(busy || !canSubmit)

                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            showSignUp = true
                        } label: {
                            AuthSecondaryButtonLabel("Create account", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .tint(BlueprintTheme.lavender)

                        Button {
                            showForgot = true
                        } label: {
                            AuthSecondaryButtonLabel("Forgot password?", systemImage: "key.horizontal")
                        }
                        .buttonStyle(.bordered)
                        .tint(BlueprintTheme.muted)
                    }

                    configCallouts
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(BlueprintTheme.bg)
            .blueprintDismissKeyboardOnScroll()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                email = UserDefaults.standard.string(forKey: SupabaseSessionManager.savedEmailKey) ?? ""
            }
            .sheet(isPresented: $showSignUp) {
                AuthSignUpView()
            }
            .sheet(isPresented: $showForgot) {
                AuthForgotPasswordView()
            }
        }
    }

    @ViewBuilder
    private var configCallouts: some View {
        if !SupabaseConfig.isConfigured || !BlueprintAPIConfig.isConfigured {
            VStack(alignment: .leading, spacing: 8) {
                if !SupabaseConfig.isConfigured {
                    Text("Sign-in requires SUPABASE_URL and SUPABASE_ANON_KEY in the target Info (or environment).")
                        .font(.caption2)
                        .foregroundStyle(BlueprintTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !BlueprintAPIConfig.isConfigured {
                    Text("Catalog refresh and workout sync need BLUEPRINT_API_URL pointing at your Blueprint API.")
                        .font(.caption2)
                        .foregroundStyle(BlueprintTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 8
    }

    private func signIn() async {
        errorMessage = nil
        busy = true
        defer { busy = false }
        do {
            try await auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            UserDefaults.standard.set(email.trimmingCharacters(in: .whitespacesAndNewlines), forKey: SupabaseSessionManager.savedEmailKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Sign up

private struct AuthSignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth: SupabaseSessionManager = .shared
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create account")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(BlueprintTheme.cream)
                        Text("Use at least 8 characters with letters and numbers. You’ll use this email to sign in on every device.")
                            .font(.subheadline)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.muted)
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .authFieldChrome()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.muted)
                        SecureField("8+ characters, letters & digits", text: $password)
                            .textContentType(.newPassword)
                            .authFieldChrome()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm password")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.muted)
                        SecureField("Confirm password", text: $confirm)
                            .textContentType(.newPassword)
                            .authFieldChrome()
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(BlueprintTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await signUp() }
                    } label: {
                        HStack(spacing: 10) {
                            if busy {
                                ProgressView()
                                    .tint(BlueprintTheme.cream)
                            }
                            Text("Create account")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BlueprintTheme.purple)
                    .disabled(busy || !canSubmit)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(BlueprintTheme.bg)
            .blueprintDismissKeyboardOnScroll()
            .navigationTitle("Sign up")
            .navigationBarTitleDisplayMode(.inline)
            .tint(BlueprintTheme.purple)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(BlueprintTheme.lavender)
                }
            }
        }
    }

    private var canSubmit: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard e.contains("@"), password.count >= 8, password == confirm else { return false }
        return password.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
            && password.range(of: #"[0-9]"#, options: .regularExpression) != nil
    }

    private func signUp() async {
        errorMessage = nil
        busy = true
        defer { busy = false }
        do {
            try await auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            UserDefaults.standard.set(email.trimmingCharacters(in: .whitespacesAndNewlines), forKey: SupabaseSessionManager.savedEmailKey)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Forgot password

private struct AuthForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth: SupabaseSessionManager = .shared
    @State private var email = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reset password")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(BlueprintTheme.cream)
                        Text("We’ll email a link when this address has an account. Open the link on this device to return here and choose a new password.")
                            .font(.subheadline)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.muted)
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .authFieldChrome()
                    }

                    if sent {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "envelope.badge")
                                .font(.title3)
                                .foregroundStyle(BlueprintTheme.mint)
                            Text("Check your inbox. If an account exists, a reset link is on the way.")
                                .font(.subheadline)
                                .foregroundStyle(BlueprintTheme.mint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BlueprintTheme.mint.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BlueprintTheme.mint.opacity(0.35), lineWidth: 1)
                        )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(BlueprintTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await send() }
                    } label: {
                        HStack(spacing: 10) {
                            if busy {
                                ProgressView()
                                    .tint(BlueprintTheme.cream)
                            }
                            Text(sent ? "Send again" : "Send reset link")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BlueprintTheme.purple)
                    .disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(BlueprintTheme.bg)
            .blueprintDismissKeyboardOnScroll()
            .navigationTitle("Reset")
            .navigationBarTitleDisplayMode(.inline)
            .tint(BlueprintTheme.purple)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(BlueprintTheme.lavender)
                }
            }
        }
    }

    private func send() async {
        errorMessage = nil
        busy = true
        defer { busy = false }
        do {
            try await auth.requestPasswordReset(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            sent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - New password (recovery)

private struct AuthSetNewPasswordView: View {
    @ObservedObject private var auth: SupabaseSessionManager = .shared
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BLUEPRINT")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BlueprintTheme.purple)
                            .tracking(1.6)
                        Text("Choose a new password")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(BlueprintTheme.cream)
                        Text("Use at least 8 characters with letters and numbers.")
                            .font(.subheadline)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("New password")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.muted)
                        SecureField("New password", text: $password)
                            .textContentType(.newPassword)
                            .authFieldChrome()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.muted)
                        SecureField("Confirm password", text: $confirm)
                            .textContentType(.newPassword)
                            .authFieldChrome()
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(BlueprintTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        HStack(spacing: 10) {
                            if busy {
                                ProgressView()
                                    .tint(BlueprintTheme.cream)
                            }
                            Text("Update password")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BlueprintTheme.purple)
                    .disabled(busy || !canSubmit)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(BlueprintTheme.bg)
            .blueprintDismissKeyboardOnScroll()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .tint(BlueprintTheme.purple)
        }
    }

    private var canSubmit: Bool {
        password.count >= 8 && password == confirm
            && password.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
            && password.range(of: #"[0-9]"#, options: .regularExpression) != nil
    }

    private func save() async {
        errorMessage = nil
        busy = true
        defer { busy = false }
        do {
            try await auth.completePasswordRecovery(newPassword: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
