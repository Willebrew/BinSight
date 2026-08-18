# BinSight

iOS app that classifies a photographed waste item as **recycle / trash / compost / hazard**, surfaces location-aware disposal rules, and gamifies environmental impact with metrics, friends, leaderboards, and a global impact map.

Founders: Will + Henry.

## Stack

- **iOS 26+ SwiftUI** with Liquid Glass (`glassEffect`, `GlassEffectContainer`)
- **Convex** - real-time database, file storage, actions, Convex Auth (email OTP via Resend)
- **Perplexity sonar-pro** (chat-completions API) called from a Convex action; built-in web search returns citations alongside the structured classification
- **Perplexity Search API** for verification + nearby recycling-facility lookups
- **MapKit + Core Location** for the impact map
- **Swift Charts** for dashboard visualizations
- **Contacts framework** with on-device SHA-256 hashing for friend discovery (raw phone numbers never leave the device)

## Repo layout

```
BinSight/
├── BRAINSTORM.md            # product notes
├── README.md                # this file
├── convex/                  # Convex backend
│   ├── schema.ts            # users (auth) + profiles, classifications, friendships, leaderboard
│   ├── auth.ts              # Convex Auth config (email OTP via Resend)
│   ├── auth.config.ts
│   ├── authProviders/       # Resend OTP provider
│   ├── http.ts              # auth HTTP routes
│   ├── files.ts             # storage upload URLs
│   ├── sage.ts              # Perplexity Agent + Search wrapper
│   ├── classifyWaste.ts     # action: image → classification (Node)
│   ├── classifications.ts   # CRUD + queries for results
│   ├── facilities.ts        # action: nearby recycling facilities
│   ├── facilitiesCache.ts   # 24h cache for facilities
│   ├── friends.ts           # phone-hash friend discovery + requests
│   ├── leaderboard.ts       # weekly materialized rankings
│   ├── map.ts               # anonymized geohash5 aggregation
│   ├── metrics.ts           # dashboard summary
│   ├── users.ts             # profile management
│   ├── crons.ts             # cron schedule
│   └── impactTable.ts       # placeholder kg-CO2 lookup
└── BinSight/                # Xcode project
    ├── BinSight.xcodeproj
    └── BinSight/
        ├── BinSightApp.swift
        ├── RootTabView.swift
        ├── Auth/AuthSession.swift
        ├── Camera/{CameraModel,CameraPreview,CameraScreen,HapticEngine}.swift
        ├── DesignSystem/{GlassRoot,GlassSurface,Tokens}.swift
        ├── Features/
        │   ├── Capture/CaptureFlow.swift
        │   ├── Dashboard/DashboardView.swift
        │   ├── Friends/{FriendsView,ContactsImporter}.swift
        │   ├── History/HistoryView.swift
        │   ├── Map/ImpactMapView.swift
        │   ├── Onboarding/SignInView.swift
        │   ├── Result/ResultCardView.swift
        │   └── Settings/SettingsView.swift
        └── Services/{ConvexService,ConvexAuthProvider,LocationProvider,Models}.swift
```

## Current build mode: direct Perplexity (v0)

This branch ships a **direct-to-Perplexity** iPhone build so you can install and use the app without standing up a backend. The full Convex backend code is preserved under `convex/` for the next phase.

In v0:
- Camera → on-device classification call to Perplexity sonar-pro → Liquid Glass result card
- All scans persist locally on device (history, dashboard)
- Friends, leaderboards, global impact map are scaffolded server-side but disabled in the app until Convex is wired

## Setup

### iPhone install (direct mode)

```bash
cd BinSight
xcodebuild -project BinSight.xcodeproj -scheme BinSight \
  -destination "platform=iOS,name=<Your iPhone>" \
  PERPLEXITY_API_KEY=pplx-yourkey build
xcrun devicectl device install app --device <udid> \
  /path/to/BinSight.app
```

Or in Xcode: set `PERPLEXITY_API_KEY` in build settings (or via a gitignored `Secrets.xcconfig`), select your iPhone as the run destination, ⌘R.

> ⚠️ **Rotate your Perplexity key** before sharing this build - it's read from Info.plist at runtime, so anyone with the .ipa can extract it. Server-side classification (Convex action) is the production path; v0 is for personal testing only.

### iOS configuration (Xcode)

Open `BinSight/BinSight.xcodeproj` and add these usage descriptions in Build Settings → Custom iOS Target Properties:

- `NSCameraUsageDescription` - "Used to scan waste items."
- `NSContactsUsageDescription` - "Hashed locally to find friends already on BinSight."
- `NSLocationWhenInUseUsageDescription` - "Used to surface local recycling rules."

## End-to-end verification

1. iOS sim → email sign in → OTP verify → camera grants
2. Capture a plastic bottle photo
3. Result card displays per-item recycle/trash decision with citations within ~6s
4. History tab shows the captured image alongside the model output
5. Dashboard updates totals within 1s (via real-time subscription)
6. Toggle Reduce Transparency in simulator accessibility settings - Liquid Glass surfaces fall back gracefully

## Privacy

- Phone numbers are hashed (SHA-256 of E.164) **on-device** before being sent to Convex; raw numbers never leave the phone.
- Map participation is opt-in (`privacy.mapOptIn`) and uses 5-character geohash cells (~5km) so individual locations cannot be derived.
- Original photos are retained so users can review history alongside model output.

## Open follow-ups

- Replace placeholder kg-CO₂ constants in `convex/impactTable.ts` with a citable dataset (EPA WARM).
- Decide H3 vs geohash5 for global map fidelity.
- Add Sign In with Apple alongside email OTP.
- Wire SAGE upgrades (presets, multi-provider routing) once core loop is shipping.

## License

Private project (Will + Henry). All rights reserved unless a LICENSE file is added.
