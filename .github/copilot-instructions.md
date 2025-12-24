# Mejour iOS App - Copilot Instructions

## Project Overview
**Mejour** is a SwiftUI-based iOS map application for exploring and sharing favorite places with friends. Users can mark locations (restaurants, cafes, scenic spots, etc.), create posts with photos, and follow friends to see their discoveries.

## Architecture Overview

### Core Components

1. **ViewModel** (`MapViewModel.swift`)
   - Single `@MainActor` source of truth for UI state
   - Manages map scope (personal vs. community), places, posts, and user location
   - Caches friend posts by userId and places by serverId
   - Handles CoreLocation delegation for user tracking

2. **Managers** (Singleton pattern, all `@MainActor`)
   - **AuthManager**: Token-based authentication; use `AuthManager.shared`
   - **PostsManager**: CRUD operations for posts with multipart/form-data support
   - **PlaceManager**: Place creation and retrieval
   - Base URL: `https://meejing-backend.vercel.app`

3. **Data Models**
   - **Place**: Local ID (UUID) + Server ID (Int); includes coordinate, type, tags, visibility
   - **LogItem**: Post representation with author/place server IDs; created from `APIPost` responses
   - **API Models** (`PostAPIModel.swift`): Server-side structures (`APIPost`, `APIPlace`, `APIUserBrief`)

4. **State Management**
   - **FollowStore**: UserDefaults-backed singleton tracking followed user IDs; auto-persists
   - `@Published` properties in ViewModels/Managers trigger SwiftUI re-renders

### Data Flow
```
Backend API ← Managers (Auth, Posts, Places)
     ↓                  ↓
   Tokens, Places,   Caching & error handling
   Posts, Users
     ↓
  ViewModel (MapViewModel.shared)
     ↓
  Views (RootMapView, SheetView)
```

## Key Patterns & Conventions

### API Communication
- **Authentication**: Attach access token from `AuthManager.shared.accessToken` to all requests
- **Request Builders**: Managers use helper methods (`authedRequest`, `requestToken`)
- **Error Handling**: Validate HTTP response status; throw `APIError` enum
- **Multipart Forms**: Use `MultipartFormData` class (in Models/) for photo uploads
- **Naming**: Snake_case in JSON (e.g., `display_name`, `place_id`, `created_at`)

Example (from PostsManager):
```swift
let api: APIPost = try await authedRequest(
    path: "/api/map/posts/",
    method: "POST",
    contentType: contentType,
    body: data
)
```

### View Hierarchy
- **RootMapView**: Main tab-based entry point (Mine, Friends, Community tabs)
- **SheetView/**: Modal overlays for details (PlaceSheetView, ProfileSheetView, EditPlaceSheet)
- **BarView/**: Navigation components (CustomTwoTabBar, Toolbar)
- **OtherView/**: Standalone screens (AuthEntryView, FriendProfileView)
- **PostView/**: Post-related screens (AddLogWizard, LogDetailView)

### MapScope Enum
- `.mine`: User's own places and posts
- `.community`: Community/friend-filtered content
Used throughout VM to filter displayed places and posts.

### Place Type Enum
- Cases: `restaurant`, `cafe`, `scenic`, `shop`, `other`
- Each has: SF Symbol `iconName`, associated `color` (Color enum)
- Used for filtering and visual distinction in UI

## Important Developer Workflows

### Building & Running
```bash
# Open Xcode project
open /Users/xujunkai/Developer/mejour/mejour.xcodeproj

# Or use xcodebuild (simulator)
xcodebuild -scheme mejour -destination generic/platform=iOS build
```

### Testing API Endpoints
- Use `APITestView.swift` (currently disabled in `mejourApp.swift`)
- Uncomment line in mejourApp: `APITestView()` → builds and tests manually

### Adding New API Endpoints
1. Define response model in `Models/PostAPIModel.swift` (match JSON keys via `CodingKeys`)
2. Add method to appropriate Manager (or create new one)
3. Use `authedRequest()` helper for authenticated calls
4. Handle `APIError` and update `@Published` state
5. Call from ViewModel and expose via `@Published` property

### Working with Caches
- **Places**: `logsByPlace[placeServerId]` stores posts for a place
- **User Posts**: `userPostsCache[userId]` for friend posts
- **Explored Places**: `exploredPlaceServerIds` set + derived property `myExploredPlaces`
- Always update after API calls; reference by `serverId` (Int)

## Critical Integration Points

### CoreLocation & MapKit
- `MapViewModel` implements `CLLocationManagerDelegate`
- Monitor `userCoordinate` and `userHeading` from `@Published` properties
- Request location permission before accessing location

### Photo Upload (Multipart/Form-Data)
- Posts can include photos via `PostsManager.createPost(photoData:)`
- Use `MultipartFormData` to build request body
- Expected form fields: `place_id`, `title`, `body`, `visibility`, `photo`

### User Following (FollowStore)
- Check if following: `FollowStore.shared.contains(userId)`
- Add: `FollowStore.shared.add(userId)` (auto-persists to UserDefaults)
- Fetch friend posts through `userPostsCache` populated by separate API call

## Server Assumptions & Gotchas

- **Token Format**: Bearer token in Authorization header
- **snake_case Fields**: All JSON uses snake_case; model `CodingKeys` required
- **Server IDs (Int)**: Places and Posts identified by `serverId` (Int), users by `authorServerId`
- **Coordinates**: Sent as `CLCodable` struct; server likely expects latitude/longitude properties
- **Timestamps**: ISO 8601 strings (`createdAt`, `updatedAt`); parse if needed

## File Structure at a Glance

```
mejour/
├── mejourApp.swift (entry point)
├── Manager/       (AuthManager, PostsManager, PlaceManager)
├── ViewModel/     (MapViewModel – main orchestrator)
├── Models/        (Place, LogItem, API models, FollowStore)
├── View/          (RootMapView + sheets + components)
├── UI/            (LiquidGlassBackgroundSimulated, UIComponents)
└── Utils/         (AnyButtonStyle, etc.)
```

## When Modifying Code

- **ViewModel changes**: Expect MapKit/CoreLocation impact; test with `RootMapView`
- **API changes**: Update Manager method + model in `PostAPIModel.swift` + ViewModel property
- **New sheets**: Create file in `View/SheetView/`, add case to `ActiveSheet` enum
- **Authentication**: Ensure token is set before any API call; check `AuthManager.isAuthenticated`
- **Error messages**: Use `@Published var errorMessage` in Manager/ViewModel; display in relevant sheet
