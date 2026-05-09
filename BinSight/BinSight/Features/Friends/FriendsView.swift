import SwiftUI
import Combine

struct FriendsView: View {
    @State private var doc: FriendsDoc?
    @State private var subscription: AnyCancellable?
    @State private var emailDraft = ""
    @State private var statusMessage: String?
    @State private var sending = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    addCard
                    if let d = doc, !d.incoming.isEmpty {
                        section("Pending requests") {
                            ForEach(d.incoming) { f in incomingRow(f) }
                        }
                    }
                    if let d = doc {
                        section("Friends (\(d.accepted.count))") {
                            if d.accepted.isEmpty {
                                emptyHint("No friends yet — invite someone by email above.")
                            } else {
                                ForEach(d.accepted) { f in acceptedRow(f) }
                            }
                        }
                    }
                    if let d = doc, !d.outgoing.isEmpty {
                        section("Sent requests") {
                            ForEach(d.outgoing) { f in outgoingRow(f) }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Friends")
        }
        .onAppear {
            subscription = ConvexService.shared.subscribeFriends()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { doc = $0 })
        }
        .onDisappear { subscription?.cancel() }
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a friend").font(.headline)
            HStack {
                Image(systemName: "envelope.fill").foregroundStyle(.secondary)
                TextField("their.email@example.com", text: $emailDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                Button {
                    sendRequest()
                } label: {
                    if sending { ProgressView() } else { Text("Add").font(.subheadline.weight(.semibold)) }
                }
                .disabled(sending || !emailDraft.contains("@"))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            if let s = statusMessage {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), variant: .regular)
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), variant: .regular)
    }

    private func acceptedRow(_ f: FriendDoc) -> some View {
        HStack {
            avatar(f.otherDisplayName ?? f.otherEmail ?? "?")
            VStack(alignment: .leading, spacing: 2) {
                Text(f.otherDisplayName ?? f.otherEmail ?? "Friend")
                    .font(.subheadline.weight(.semibold))
                if let email = f.otherEmail, f.otherDisplayName != nil {
                    Text(email).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Button(role: .destructive) {
                    Task { try? await ConvexService.shared.removeFriend(friendshipId: f.friendshipId) }
                } label: { Label("Remove friend", systemImage: "person.fill.xmark") }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), variant: .regular)
    }

    private func incomingRow(_ f: FriendDoc) -> some View {
        HStack {
            avatar(f.otherDisplayName ?? f.otherEmail ?? "?")
            VStack(alignment: .leading, spacing: 2) {
                Text(f.otherDisplayName ?? f.otherEmail ?? "Friend").font(.subheadline.weight(.semibold))
                Text("wants to be friends").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Button {
                    Task { try? await ConvexService.shared.respondFriendRequest(friendshipId: f.friendshipId, accept: false) }
                } label: { Image(systemName: "xmark") }
                .buttonStyle(.bordered)
                Button {
                    Task { try? await ConvexService.shared.respondFriendRequest(friendshipId: f.friendshipId, accept: true) }
                } label: { Image(systemName: "checkmark") }
                .buttonStyle(.borderedProminent)
                .tint(BinSightTokens.Color.recycle)
            }
        }
        .padding(12)
        .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), variant: .regular)
    }

    private func outgoingRow(_ f: FriendDoc) -> some View {
        HStack {
            avatar(f.otherDisplayName ?? f.otherEmail ?? "?")
            VStack(alignment: .leading, spacing: 2) {
                Text(f.otherDisplayName ?? f.otherEmail ?? "Friend").font(.subheadline.weight(.semibold))
                Text("waiting for them to accept").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { try? await ConvexService.shared.removeFriend(friendshipId: f.friendshipId) }
            } label: { Image(systemName: "xmark") }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), variant: .regular)
    }

    private func avatar(_ seed: String) -> some View {
        let initial = String(seed.prefix(1)).uppercased()
        return Text(initial)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(BinSightTokens.Color.accent, in: Circle())
    }

    private func sendRequest() {
        let email = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else { return }
        sending = true
        statusMessage = nil
        Task {
            defer { sending = false }
            do {
                let result = try await ConvexService.shared.requestFriendByEmail(email)
                switch result.status {
                case "pending":     statusMessage = "Request sent."
                case "accepted":    statusMessage = "You're now friends 🎉"
                case "self":        statusMessage = "That's your own email."
                case "no_such_user": statusMessage = "No BinSight user with that email yet."
                default:            statusMessage = "Status: \(result.status)"
                }
                emailDraft = ""
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}
