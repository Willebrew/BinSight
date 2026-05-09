import SwiftUI
import Combine

struct SettingsView: View {
    @EnvironmentObject private var session: AuthSession
    @State private var profile: ProfileDoc?
    @State private var subscription: AnyCancellable?
    @State private var phoneNumber: String = ""
    @State private var savingPhone = false
    @State private var phoneError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    accountSection
                    phoneSection
                    privacySection
                    signOutSection
                }
                .padding(20)
            }
            .navigationTitle("Settings")
        }
        .task {
            subscription = ConvexService.shared.subscribeMe()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { profile = $0 })
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Account").font(.headline)
            Text(profile?.email ?? "—").font(.callout)
            if let name = profile?.name { Text(name).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phone (optional)").font(.headline)
            Text("Used so friends can find you via contacts. We store only a hash.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                TextField("+1 555 555 0123", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .padding(10)
                    .glassSurface(RoundedRectangle(cornerRadius: 12, style: .continuous), variant: .clear)
                Button(savingPhone ? "Saving…" : "Save") { savePhone() }
                    .disabled(savingPhone || phoneNumber.isEmpty)
            }
            if let err = phoneError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy").font(.headline)
            Toggle("Show me on the global impact map", isOn: Binding(
                get: { profile?.privacy.mapOptIn ?? false },
                set: { newValue in Task { try? await ConvexService.shared.updateProfile(mapOptIn: newValue) } }
            ))
            Toggle("Allow contact discovery", isOn: Binding(
                get: { profile?.privacy.contactsOptIn ?? false },
                set: { newValue in Task { try? await ConvexService.shared.updateProfile(contactsOptIn: newValue) } }
            ))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private var signOutSection: some View {
        Button(role: .destructive) {
            session.signOut()
        } label: {
            Text("Sign out").frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .clear)
    }

    private func savePhone() {
        guard let e164 = ContactsImporter.normalizeToE164(phoneNumber) else {
            phoneError = "Couldn't read that number."; return
        }
        savingPhone = true
        phoneError = nil
        Task {
            defer { savingPhone = false }
            do {
                let hash = ContactsImporter.sha256Hex(e164)
                try await ConvexService.shared.updateProfile(phoneHash: hash)
                phoneNumber = ""
            } catch {
                phoneError = error.localizedDescription
            }
        }
    }
}
