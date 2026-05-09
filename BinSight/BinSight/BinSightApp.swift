//
//  BinSightApp.swift
//  BinSight
//
//  Created by Will Killebrew on 5/9/26.
//

import SwiftUI

@main
struct BinSightApp: App {
    @StateObject private var convex = ConvexService.shared
    @StateObject private var session = AuthSession.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isAuthenticated {
                    RootTabView()
                } else {
                    SignInView()
                }
            }
            .environmentObject(convex)
            .environmentObject(session)
            .task { await session.bootstrap() }
        }
    }
}
