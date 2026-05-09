import SwiftUI
import Combine

struct FriendsView: View {
    @State private var friends: [FriendDoc] = []
    @State private var leaderboard: [LeaderboardRow] = []
    @State private var matches: [FriendMatch] = []
    @State private var bag: Set<AnyCancellable> = []
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Section { contactsImporter } header: { sectionHeader("Find friends") }

                if !matches.isEmpty {
                    Section { matchList } header: { sectionHeader("On BinSight") }
                }

                Section { friendList } header: { sectionHeader("Friends") }
                Section { leaderboardList } header: { sectionHeader("Weekly leaderboard") }
            }
            .padding(20)
        }
        .navigationTitle("Friends")
        .task {
            ConvexService.shared.subscribeFriends()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { friends = $0 })
                .store(in: &bag)

            ConvexService.shared.subscribeLeaderboard()
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { leaderboard = $0 })
                .store(in: &bag)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.headline).padding(.top, 4)
    }

    private var contactsImporter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hash your contacts on this device and check who's already using BinSight. Raw numbers never leave the phone.")
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                runImport()
            } label: {
                HStack {
                    if importing { ProgressView().tint(.white) }
                    Text(importing ? "Searching…" : "Find from contacts").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .background(BinSightTokens.Color.accent, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)

            if let err = importError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), variant: .regular)
    }

    private var matchList: some View {
        VStack(spacing: 8) {
            ForEach(matches) { m in
                HStack {
                    VStack(alignment: .leading) {
                        Text(m.name ?? m.handle ?? "User").font(.headline)
                    }
                    Spacer()
                    Button("Add") {
                        Task { try? await sendRequest(otherAuthUserId: m.authUserId) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BinSightTokens.Color.recycle)
                }
                .padding(12)
                .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), variant: .clear)
            }
        }
    }

    private var friendList: some View {
        VStack(spacing: 8) {
            if friends.isEmpty {
                Text("No friends yet — invite some from contacts above.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(friends) { f in
                    HStack {
                        Text(f.other.name ?? f.other.handle ?? "User")
                            .font(.headline)
                        Spacer()
                        Text(f.status.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.gray.opacity(0.15), in: Capsule())
                    }
                    .padding(12)
                    .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), variant: .regular)
                }
            }
        }
    }

    private var leaderboardList: some View {
        VStack(spacing: 8) {
            ForEach(Array(leaderboard.enumerated()), id: \.element.authUserId) { index, row in
                HStack {
                    Text("#\(index + 1)").font(.headline.monospaced())
                    Text(row.name ?? row.handle ?? "User")
                    Spacer()
                    Text("\(row.kgRecycled, specifier: "%.2f") kg CO₂")
                        .font(.caption.monospaced())
                }
                .padding(12)
                .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous), variant: .clear)
            }
        }
    }

    private func runImport() {
        importing = true
        importError = nil
        Task {
            defer { importing = false }
            do {
                let hashes = try await ContactsImporter.collectHashedPhones()
                guard !hashes.isEmpty else {
                    importError = "No phone numbers found in contacts."
                    return
                }
                matches = try await ConvexService.shared.findFriendsByPhoneHashes(hashes)
                if matches.isEmpty {
                    importError = "No matches yet — invite friends!"
                }
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func sendRequest(otherAuthUserId: String) async throws {
        struct Args: Encodable { let otherAuthUserId: String }
        let _: String? = try await ConvexService.shared.client.mutation(
            "friends:request",
            args: Args(otherAuthUserId: otherAuthUserId)
        )
    }
}
