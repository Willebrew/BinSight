# BinSight - Ideas & Notes

## Project Overview
iOS app that helps users classify waste items (recycle vs trash) through image recognition, with gamification through metrics and efficiency tracking.

## Founders
- Will
- Henry

## Core Concept
Take a picture of trash → AI tells you whether to recycle or throw it away → Track metrics and show user efficiency

## Technology Stack

### Frontend
- iOS app (Swift/SwiftUI)
- Apple Maps integration for location features

### Backend
- Convex for real-time database and function calling
- Convex Auth for user authentication and social features
- SAGE (Stratus Agentic Generation Engine) as agentic runtime

### AI/ML
- Perplexity Agent API for image classification
  - Multi-provider access (OpenAI, Anthropic, Google, xAI, etc.)
  - Built-in web search for location-specific recycling rules
  - Tool configuration for database operations
  - Transparent pricing with cost tracking
- Perplexity Search API to verify waste identified for metrics
- Multi-object detection (detect multiple waste items in single image)

## Important Notes

### SAGE Integration
- SAGE currently has basic Perplexity support (chat-completions API)
- **Needs update** to fully support Perplexity Agent API:
  - Add support for `/v1/agent` endpoint
  - Enable multi-provider routing through Agent API
  - Leverage built-in web search capabilities
  - Support Agent API presets and tool configuration

## Ideas & Features to Explore

### Core Features
- [ ] Image capture and classification
- [ ] Real-time recycle vs trash decision
- [ ] Confidence scoring for classifications
- [ ] Location-based recycling rules (via web search)
- [ ] User metrics tracking
- [ ] Efficiency scoring
- [ ] Haptic feedback when scanning (to show it's detecting items)
- [ ] Multi-object detection (detect multiple waste items in single photo)
- [ ] Verification using Perplexity Search API for metrics accuracy

### Gamification
- [ ] Leaderboards
- [ ] User efficiency comparisons
- [ ] Streaks or achievements
- [ ] Social sharing of impact

### Advanced Features
- [ ] Material identification details
- [ ] Disposal instructions for unusual items
- [ ] Educational content about recycling
- [ ] Local recycling facility finder
- [ ] Barcode scanning integration
- [ ] History of scanned items

### Dashboard
- [ ] Amount recycled (count/weight)
- [ ] Amount thrown away (count/weight)
- [ ] Materials breakdown (plastic, glass, paper, metal, organic, etc.)
- [ ] Total environmental impact calculation
- [ ] Personal statistics and trends
- [ ] Comparison with averages
- [ ] Monthly/yearly reports

### Social Features
- [ ] User-to-user connections via Convex Auth
- [ ] Phone number input for friend discovery
- [ ] Contacts integration to find friends using BinSight
- [ ] Friend activity feed
- [ ] Compare metrics with friends
- [ ] Group challenges or competitions

### Map & Location
- [ ] User location tracking
- [ ] Apple Maps integration
- [ ] Global impact map showing all user activity
- [ ] Local recycling hotspots
- [ ] Community recycling rates by region
- [ ] Nearby recycling facilities

### Data & Analytics
- [ ] Personal waste sorting accuracy
- [ ] Community-wide recycling rates
- [ ] Environmental impact calculations
- [ ] Trends and insights

## Questions to Explore

1. **Target Audience**: Individual consumers, businesses, schools, or all of the above?
2. **MVP Scope**: Just classification, or include metrics from day one?
3. **Model Selection**: Which vision model via Perplexity Agent API? (GPT-4o, Claude 3.5 Sonnet with vision, etc.)
4. **Location Features**: How granular should location-based recycling rules be?
5. **Offline Support**: Should the app work without internet?
6. **Privacy**: How to handle user data and images?
7. **Haptics**: What haptic patterns for scanning vs. confirmation vs. error?
8. **Multi-object**: How to display multiple detected items? Bounding boxes? List?
9. **Environmental Impact**: How to calculate CO2 savings, trees saved, etc.?
10. **Contacts Privacy**: How to handle phone number sharing and contacts access?
11. **Map Privacy**: Should user locations be anonymous on the global map?
12. **Dashboard Refresh**: Real-time updates or periodic sync?

## Architecture Notes

### Proposed Flow
1. iOS app captures image (with haptic feedback during scanning)
2. Image sent to Convex backend
3. Convex function calls Perplexity Agent API (via SAGE)
4. Agent API uses vision model to classify item(s) - supports multi-object detection
5. Optionally uses web search for local recycling rules
6. Perplexity Search API verifies waste identification for metrics accuracy
7. Returns classification + confidence + context + verification
8. Convex stores classification and updates user metrics
9. iOS app displays result to user with haptic confirmation

### Social Flow
1. User signs up with Convex Auth
2. User enters phone number
3. Contacts integration finds friends using BinSight
4. Users can connect and view each other's activity
5. Compare metrics and compete in challenges

### Map Flow
1. User location tracked (with permission)
2. All user classifications aggregated with location data
3. Apple Maps displays global impact visualization
4. Users can see recycling rates by region
5. Nearby recycling facilities shown

## UI/UX Wireframes

### Initial Camera Page (Landing Screen)
**First screen users see when opening the app.**

**Layout (Mobile Portrait):**
- **Top Section**: Header text - "Scan your waste"
- **Center Area**: Large camera preview/viewfinder
  - Placeholder text: "picture"
  - Central camera icon/placeholder for the live camera feed
- **Bottom Navigation Bar** (3 elements):
  - **Dashboard** (left) - chart/graph icon, navigates to metrics view
  - **Central Circular Shutter Button** - main capture button for taking photos
  - **Settings** (right) - gear icon, navigates to app settings

**User Flow:**
1. User opens app → lands directly on camera page
2. Camera preview is active and ready to scan
3. User taps the central circular button to capture an image of waste item
4. AI processes the image and returns classification (recycle vs trash)

## Open Questions
- What specific metrics to track?
- How to calculate "efficiency"?
- What constitutes a "good" recycling rate?
- How to handle ambiguous items?
- How to handle incorrect classifications?