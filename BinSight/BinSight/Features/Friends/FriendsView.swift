import SwiftUI
import Combine

struct FriendsView: View {
    @State private var doc: FriendsDoc?
    @State private var compare: FriendCompareDoc?
    @State private var subscription: AnyCancellable?
    @State private var compareSubscription: AnyCancellable?
    @State private var emailDraft = ""
    @State private var statusMessage: String?
    @State private var sending = false

    @State private var searchText = ""
    @State private var selectedTab: Tab = .friends
    @FocusState private var focusedField: Field?

    enum Tab: String, CaseIterable { case friends = "Friends"; case requests = "Requests" }
    enum Field { case inviteEmail, search }

    private var filteredFriends: [FriendDoc] {
        guard let accepted = doc?.accepted else { return [] }
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty { return accepted }
        return accepted.filter {
            ($0.otherDisplayName ?? "").localizedCaseInsensitiveContains(searchText)
            || ($0.otherEmail ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var requestCount: Int { (doc?.incoming ?? []).count }
    private var inviteMessage: String {
        "I'm using BinSight to sort my waste smarter. Join me!"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DuoBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        titleHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        inviteCard
                            .padding(.horizontal, 20)
                            .padding(.top, 24)

                        searchAndTabs
                            .padding(.horizontal, 20)
                            .padding(.top, 28)

                        content
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }
                    .padding(.bottom, 110)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = nil }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { subscribe() }
        .onDisappear {
            subscription?.cancel()
            compareSubscription?.cancel()
        }
    }

    // MARK: - Title

    private var titleHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
                Text("Friends")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(BinSightTokens.Color.ink)
            Text("Compare your impact")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(BinSightTokens.Color.softInk)
        }
    }

    // MARK: - Invite Card

    private var inviteCard: some View {
        DuoCard(fill: .white, stroke: BinSightTokens.Color.recycle.opacity(0.25), radius: 26, padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    MascotArtView(mood: .happy, size: 76, accessory: "person.2.fill")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Invite a friend")
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(BinSightTokens.Color.ink)
                        Text("Build recycling streaks together.")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(BinSightTokens.Color.softInk)
                    }
                    Spacer()
                }
                .padding(18)
                .background(BinSightTokens.Color.mint.opacity(0.72))

                HStack(spacing: 10) {
                    TextField("", text: $emailDraft, prompt:
                        Text("Email address")
                            .foregroundColor(BinSightTokens.Color.softInk)
                    )
                    .foregroundColor(BinSightTokens.Color.ink)
                    .tint(BinSightTokens.Color.recycle)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .focused($focusedField, equals: .inviteEmail)

                    Button {
                        sendRequest()
                    } label: {
                        if sending {
                            ProgressView().tint(.white)
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .background(BinSightTokens.Color.recycle)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(sending || !emailDraft.contains("@"))
                    .opacity(emailDraft.contains("@") && !sending ? 1 : 0.35)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.white)

                Divider().background(BinSightTokens.Color.stroke)

                ShareLink(item: inviteMessage) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("Share invite")
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(BinSightTokens.Color.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Search & Tabs

    private var searchAndTabs: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BinSightTokens.Color.softInk)
                TextField("", text: $searchText, prompt:
                    Text("Search")
                        .foregroundColor(BinSightTokens.Color.softInk)
                )
                .foregroundColor(BinSightTokens.Color.ink)
                .tint(BinSightTokens.Color.recycle)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .focused($focusedField, equals: .search)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(BinSightTokens.Color.softInk)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Text(tab.rawValue)
                                    .font(.subheadline.weight(selectedTab == tab ? .bold : .medium))
                                if tab == .requests, requestCount > 0 {
                                    Text("\(requestCount)")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .foregroundStyle(.white)
                                        .frame(minWidth: 18, minHeight: 18)
                                        .background(BinSightTokens.Color.hazard, in: Circle())
                                }
                            }
                            .foregroundStyle(selectedTab == tab ? BinSightTokens.Color.recycle : BinSightTokens.Color.softInk)
                            Rectangle()
                                .fill(selectedTab == tab ? BinSightTokens.Color.recycle : .clear)
                                .frame(height: 4)
                                .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch selectedTab {
        case .friends: friendsContent
        case .requests: requestsContent
        }
    }

    @ViewBuilder private var friendsContent: some View {
        if filteredFriends.isEmpty {
            emptyState(
                icon: "person.2.slash",
                title: searchText.isEmpty ? "No friends yet" : "No matches",
                subtitle: searchText.isEmpty
                ? "Invite someone to start comparing your environmental impact."
                : "Try a different search term."
            )
        } else {
            LazyVStack(spacing: 14) {
                ForEach(filteredFriends, id: \.id) { friend in
                    FriendCompareCard(
                        friend: friend,
                        me: compare?.me,
                        friendStats: compare?.friends.first(where: { $0.userId == friend.otherUserId }),
                        onRemove: {
                            Task { try? await ConvexService.shared.removeFriend(friendshipId: friend.friendshipId) }
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder private var requestsContent: some View {
        let incoming = doc?.incoming ?? []
        let outgoing = doc?.outgoing ?? []
        if incoming.isEmpty && outgoing.isEmpty {
            emptyState(icon: "envelope.open", title: "No requests",
                       subtitle: "Friend requests will show up here.")
        } else {
            LazyVStack(spacing: 20) {
                if !incoming.isEmpty {
                    sectionHeader("Pending")
                    LazyVStack(spacing: 0) {
                        ForEach(Array(incoming.enumerated()), id: \.element.id) { idx, friend in
                            IncomingRequestRow(friend: friend) {
                                Task { try? await ConvexService.shared.respondFriendRequest(friendshipId: friend.friendshipId, accept: true) }
                            } onDecline: {
                                Task { try? await ConvexService.shared.respondFriendRequest(friendshipId: friend.friendshipId, accept: false) }
                            }
                            if idx < incoming.count - 1 { Divider().padding(.leading, 62) }
                        }
                    }
                }
                if !outgoing.isEmpty {
                    sectionHeader("Sent")
                    LazyVStack(spacing: 0) {
                        ForEach(Array(outgoing.enumerated()), id: \.element.id) { idx, friend in
                            OutgoingRequestRow(friend: friend) {
                                Task { try? await ConvexService.shared.removeFriend(friendshipId: friend.friendshipId) }
                            }
                            if idx < outgoing.count - 1 { Divider().padding(.leading, 62) }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BinSightTokens.Color.softInk)
                .tracking(1)
            Spacer()
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            MascotArtView(mood: .thinking, size: 94, accessory: icon)
            VStack(spacing: 5) {
                Text(title).font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(BinSightTokens.Color.ink)
                Text(subtitle).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(BinSightTokens.Color.softInk).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Actions

    private func sendRequest() {
        let email = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else { return }
        focusedField = nil
        sending = true; statusMessage = nil
        Task {
            defer { sending = false }
            do {
                let result = try await ConvexService.shared.requestFriendByEmail(email)
                switch result.status {
                case "pending":      statusMessage = "Request sent."
                case "accepted":     statusMessage = "You're now friends!"
                case "self":         statusMessage = "That's your own email."
                case "no_such_user": statusMessage = "No user with that email."
                default:             statusMessage = result.status
                }
                emailDraft = ""
                dismissStatusAfterDelay()
            } catch {
                statusMessage = error.localizedDescription
                dismissStatusAfterDelay()
            }
        }
    }

    private func dismissStatusAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation(.easeOut(duration: 0.3)) { statusMessage = nil }
        }
    }

    private func subscribe() {
        subscription = ConvexService.shared.subscribeFriends()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { doc = $0 })
        compareSubscription = ConvexService.shared.subscribeFriendCompare()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { compare = $0 })
    }
}

// MARK: - Avatar

private struct AvatarView: View {
    let seed: String
    var size: CGFloat = 44

    var body: some View {
        let initial = String(seed.prefix(1)).uppercased()
        let color = avatarColor(for: seed)
        Text(initial)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

private func avatarColor(for seed: String) -> Color {
    let hash = abs(seed.utf8.reduce(0) { $0 + Int($1) })
    let presets: [Color] = [
        Color(red: 0.20, green: 0.70, blue: 0.45),
        Color(red: 0.14, green: 0.50, blue: 0.88),
        Color(red: 0.58, green: 0.42, blue: 0.18),
        Color(red: 0.80, green: 0.34, blue: 0.28),
        Color(red: 0.88, green: 0.56, blue: 0.16),
        Color(red: 0.50, green: 0.28, blue: 0.60),
        Color(red: 0.24, green: 0.64, blue: 0.68),
        Color(red: 0.68, green: 0.32, blue: 0.50),
    ]
    return presets[hash % presets.count]
}

// MARK: - FriendRow

private struct FriendRow: View {
    let friend: FriendDoc
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            DuoAvatar(seed: friend.otherDisplayName ?? friend.otherEmail ?? "?", size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.otherDisplayName ?? "Friend")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                if let email = friend.otherEmail {
                    Text(email)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(BinSightTokens.Color.softInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "person.fill.xmark")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BinSightTokens.Color.softInk)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Friend Compare Card

/// Side-by-side comparison card: avatar + name on top, then three
/// metrics (CO2, items diverted, streak) each rendered as a dual
/// progress bar showing me vs the friend. The leader gets a small
/// crown badge so the result is readable at a glance.
private struct FriendCompareCard: View {
    let friend: FriendDoc
    let me: FriendCompareStats?
    let friendStats: FriendCompareStats?
    let onRemove: () -> Void

    var body: some View {
        DuoCard(fill: .white,
                stroke: BinSightTokens.Color.recycle.opacity(0.18),
                radius: 22, padding: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let me, let friendStats {
                    VStack(spacing: 12) {
                        CompareBar(
                            icon: "leaf.fill",
                            label: "CO₂ saved",
                            unit: "kg",
                            myValue: me.totalCo2Kg,
                            friendValue: friendStats.totalCo2Kg,
                            tint: BinSightTokens.Color.recycle,
                            digits: 2
                        )
                        CompareBar(
                            icon: "checkmark.seal.fill",
                            label: "Items diverted",
                            unit: "",
                            myValue: Double(me.totalRecycled),
                            friendValue: Double(friendStats.totalRecycled),
                            tint: BinSightTokens.Color.accent,
                            digits: 0
                        )
                        CompareBar(
                            icon: "flame.fill",
                            label: "Streak",
                            unit: "d",
                            myValue: Double(me.streakDays),
                            friendValue: Double(friendStats.streakDays),
                            tint: BinSightTokens.Color.hazard,
                            digits: 0
                        )
                    }
                } else {
                    Text("Loading impact…")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(BinSightTokens.Color.softInk)
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            DuoAvatar(seed: friend.otherDisplayName ?? friend.otherEmail ?? "?", size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.otherDisplayName ?? "Friend")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                if let summary = leaderboardSummary {
                    Text(summary)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(BinSightTokens.Color.softInk)
                        .lineLimit(1)
                } else if let email = friend.otherEmail {
                    Text(email)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(BinSightTokens.Color.softInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "person.fill.xmark")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BinSightTokens.Color.softInk)
                    .padding(8)
                    .contentShape(Rectangle())
            }
        }
    }

    /// One-line headline summarizing who's ahead. Reads "+0.4 kg CO₂"
    /// from the user's perspective when they lead, "behind by 3 items"
    /// when they don't, and is neutral on a tie.
    private var leaderboardSummary: String? {
        guard let me, let f = friendStats else { return nil }
        let dCo2 = me.totalCo2Kg - f.totalCo2Kg
        if abs(dCo2) >= 0.05 {
            let sign = dCo2 > 0 ? "+" : "−"
            return "\(sign)\(String(format: "%.1f", abs(dCo2))) kg CO₂"
        }
        let dItems = me.totalRecycled - f.totalRecycled
        if dItems != 0 {
            return dItems > 0 ? "leading by \(dItems)" : "behind by \(-dItems)"
        }
        return "neck and neck"
    }
}

private struct CompareBar: View {
    let icon: String
    let label: String
    let unit: String
    let myValue: Double
    let friendValue: Double
    let tint: Color
    let digits: Int

    private var max: Double { Swift.max(myValue, friendValue, 0.0001) }
    private var myFraction: Double { myValue / max }
    private var friendFraction: Double { friendValue / max }
    private var iLead: Bool { myValue > friendValue }
    private var tied: Bool { abs(myValue - friendValue) < 0.0001 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                Spacer()
            }
            row(label: "You", value: myValue, fraction: myFraction,
                isWinner: iLead && !tied, primary: true)
            row(label: friendShortName, value: friendValue, fraction: friendFraction,
                isWinner: !iLead && !tied, primary: false)
        }
    }

    private var friendShortName: String { "Them" }

    private func row(label: String, value: Double, fraction: Double, isWinner: Bool, primary: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(BinSightTokens.Color.softInk)
                .frame(width: 38, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BinSightTokens.Color.softInk.opacity(0.10))
                    Capsule()
                        .fill(primary ? tint : tint.opacity(0.55))
                        .frame(width: Swift.max(8, geo.size.width * fraction))
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: fraction)
                }
            }
            .frame(height: 10)
            HStack(spacing: 3) {
                Text(formatted(value) + (unit.isEmpty ? "" : " \(unit)"))
                    .font(.system(.caption2, design: .rounded).weight(.heavy).monospacedDigit())
                    .foregroundStyle(BinSightTokens.Color.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .minimumScaleFactor(0.7)
                if isWinner {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(BinSightTokens.Color.hazard)
                }
            }
            .frame(width: 76, alignment: .trailing)
        }
    }

    private func formatted(_ v: Double) -> String {
        if digits == 0 { return String(Int(v.rounded())) }
        return String(format: "%.\(digits)f", v)
    }
}

// MARK: - IncomingRequestRow

private struct IncomingRequestRow: View {
    let friend: FriendDoc
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            DuoAvatar(seed: friend.otherDisplayName ?? friend.otherEmail ?? "?", size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.otherDisplayName ?? "Someone")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                Text("wants to be friends")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(BinSightTokens.Color.softInk)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(action: onDecline) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BinSightTokens.Color.trash)
                        .frame(width: 28, height: 28)
                        .background(BinSightTokens.Color.trash.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(BinSightTokens.Color.recycle)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - OutgoingRequestRow

private struct OutgoingRequestRow: View {
    let friend: FriendDoc
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            DuoAvatar(seed: friend.otherDisplayName ?? friend.otherEmail ?? "?", size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.otherDisplayName ?? "Friend")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.ink)
                Text("waiting for them to accept")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(BinSightTokens.Color.softInk)
            }
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(BinSightTokens.Color.trash)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(BinSightTokens.Color.trash.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.vertical, 10)
    }
}
