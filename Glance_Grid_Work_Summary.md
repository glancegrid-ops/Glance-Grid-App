# Glance Grid Work Summary

## Session Overview
**Date:** January 22, 2026
**Focus:** Bug fixes, Performance Improvements, Architectural Refactoring, and New User Management Features.

## Tasks Completed

### 1. Critical Bug Fixes & UX Improvements
*   **Recording Storage Fix:**
    *   Resolved issue where recorded clips were saved with incorrect filenames.
    *   Updated `VideoGridItem` and callbacks to explicitly pass the `docId`.
    *   Fixed a race condition in `onVideoCompleted` by awaiting `notifySegmentEnd` before state cleanup.
*   **UI/UX Glitches:**
    *   Removed blocking loading overlay that prevented interaction.
    *   Prevented videos from playing while obscured by the loader.
    *   Fixed Dot Indicator visibility by adding a background container and improving contrast (active white, inactive translucent).
    *   Adjusted positioning of UI elements to prevent overlaps.
*   **Code Quality:**
    *   Fixed deprecated `withOpacity` usage by migrating to `withValues`.
    *   Ran `flutter analyze` and resolved reported issues.

### 2. Architectural Refactoring
*   **Folder Structure:**
    *   Restructured the project into a scalable feature-based architecture: `models`, `services`, `screens`, `widgets`, `helpers`.
    *   Cleaned up `main.dart` to strictly handle app initialization and entry.
*   **State Management & Navigation:**
    *   Moved `StartupWrapper` and `VideoPlayerScreen` to dedicated files in `screens/`.
    *   Created `UiHelpers` for reusable UI logic (e.g., Password Dialog).

### 3. Feature Implementation: User Management & Security
*   **Dependencies:**
    *   Added `flutter_secure_storage` and `uuid` for secure, persistent device identification.
*   **Data Models:**
    *   Created `UserModel` (name, description, deviceId).
    *   Created `VideoModel` (videoUrl, allowed userIds).
*   **Services Layer:**
    *   `DeviceIdService`: Handles generation and retrieval of unique device IDs.
    *   `UserService`: Manages user profiles in Firestore (Add/Fetch).
    *   `VideoService`: centralized video fetching logic.
*   **User Onboarding Flow:**
    *   Implemented `UserFormScreen` for capturing new user details.
    *   Implemented logic in `StartupWrapper` to route users based on registration status (New User -> Form, Existing User -> Video Player).
*   **Content Security:**
    *   Implemented server-side-like filtering in `VideoService` to only fetch videos authorized for the current `deviceId`.

## Man-Hours Estimation

| Category | Description | Estimated Time |
| :--- | :--- | :--- |
| **Bug Fixing** | Diagnosis, fix implementation for recording bugs, UI overlays, and race conditions. | 2.5 Hours |
| **Refactoring** | Restructuring project folders, moving classes, updating imports, cleaning `main.dart`. | 2.0 Hours |
| **Feature Dev** | setup `secure_storage`, User Form UI, User/Video Models, Service implementation, Onboarding flow logic. | 3.5 Hours |
| **Testing** | Verification of fixes, flow testing, and static analysis. | 1.0 Hours |
| **Total** | | **9.0 Hours** |

---
*Note: This estimation assumes a senior-level Flutter developer pace, accounting for context switching, analysis, and implementation.*

---

## Session 2: Image Recording Support & Bug Fix
**Date:** February 12-17, 2026  
**Branch:** `feat/3rd_iteration`  
**Focus:** Image file type support with dynamic duration display and recording storage fix for image-type content.

## Tasks Completed

### 1. Image File Type Support
*   **Data Model Enhancement:**
    *   Extended `FileModel` to support both `video` and `image` file types with dynamic duration from Firebase.
    *   Updated `FileModel.fromJson()` to parse `type` (enum) and `duration` from Firestore documents.
*   **UI Display Logic:**
    *   Enhanced `FileGridItem` to conditionally initialize as image or video based on file type.
    *   Images display using `Image.file()` or `Image.network()` with a timer-based duration instead of video playback.
    *   Progress tracking added for image display via periodic timer (100ms intervals).
    *   Completion callbacks (`onCompleted`, `onDurationComplete`) fired after image display duration expires.

### 2. Recording Storage Fix for Images
*   **Root Cause Identification:**
    *   Discovered that recordings were not being stored when displaying image-type files because segment rotation occurred before `notifySegmentEnd()` was called (for images with shorter durations).
    *   The recorder's internal `_currentVideoDocId` was null during save, causing the log: ✗ Cannot save clip: docId is null or empty.
*   **Solution Implementation:**
    *   **Temp Path Tracking:** Added `_lastSegmentTempPath` field to track the temporary video file produced by `stopVideoRecording()` during segment rotation.
    *   **Updated `_rotateSegment()`:** Now captures and stores the temp path when rotating segments.
    *   **Updated `_stopRecordingIfNeeded()`:** Records temp path for graceful shutdown scenarios.
    *   **Enhanced `notifySegmentEnd()`:**
        *   Accepts optional `docId` parameter to avoid UI-to-recorder state races.
        *   Falls back to last recorded temp path if controller isn't actively recording.
        *   Saves the temp file to app documents with docId-timestamped filename.
        *   Cleans up temp file and clears `_lastSegmentTempPath` after successful save.
    *   **UI Integration:** Updated `VideoPlayerScreen.onVideoCompleted()` to pass the completed item's `docId` to `notifySegmentEnd(docId)`.
*   **Result:** Both video and image recordings now save correctly without any special handling—same MP4 format, same storage mechanism.

### 3. UI Widget Updates
*   **AdaptiveVideoGrid Enhancement:**
    *   Updated to pass video metadata (docId, type, duration) through grid items.
    *   Maintained backward compatibility with existing video playback flow.
    *   Ensured proper callback propagation for both image and video completion events.
*   **FileGridItem Callback Updates:**
    *   Updated `onStarted` callback to pass docId for both image and video types.
    *   Ensured consistent callback signatures across image timer and video playback flows.
    *   Fixed initialization order to prevent race conditions between state updates and callbacks.

### 4. Testing & Validation
*   Built APK for release testing (exit code 0).
*   Verified image recordings now appear in app documents directory with correct naming pattern.
*   Tested image display with various durations from Firebase.
*   Verified recorder state transitions during fast image playback cycles.

## Man-Hours Estimation (Session 2)

| Category | Description | Estimated Time |
| :--- | :--- | :--- |
| **Analysis & Investigation** | Diagnosing why images weren't saving, tracing state flow, identifying segment rotation race condition. | 1.5 Hours |
| **Feature Dev: Image Support** | Extending FileModel, updating FileGridItem for conditional image/video rendering, timer logic. | 1.5 Hours |
| **UI Widget Updates** | Updating AdaptiveVideoGrid and FileGridItem callbacks, ensuring proper state and callback propagation. | 1.0 Hours |
| **Bug Fix: Recording Storage** | Implementing temp path tracking, updating notifySegmentEnd logic, UI integration with docId passing. | 2.0 Hours |
| **Testing & Verification** | Build validation, recorded clip verification, log inspection, APK release build. | 0.5 Hours |
| **Total (Session 2)** | | **6.5 Hours** |

---
*Note: This branch focused on enabling a new file type (images) while ensuring the recording pipeline remained robust for both types. The core fix was simple (pass docId + track temp path) but required careful analysis to identify the root cause.*

---

## Session 3: Feature Expansion & Robustness
**Date:** February 17, 2026
**Focus:** Enhancing user controls (Brightness, Wakelock), implementing media management (Download/Select), expanding content support (Images), and hardening the recording pipeline against hardware failures.

## Tasks Completed

### 1. User Experience Enhancements
*   **Screen Brightness Control:**
    *   Integrated `screen_brightness` package to allow users to adjust screen brightness directly within the app.
    *   Implemented `setApplicationScreenBrightness` to override system settings during playback.
    *   Added auto-reset logic (`resetApplicationScreenBrightness`) when leaving the player to restore user's system preferences.
*   **Device Awake Persistence:**
    *   Integrated `wakelock_plus` to prevent the device screen from dimming or locking during video playback.
    *   Enabled wakelock on player initialization and disabled on disposal to conserve battery.

### 2. Media Management (Download & Select)
*   **Selection Mode:**
    *   Implemented a long-press gesture in `ClipBrowserScreen` to trigger a multi-selection mode.
    *   Added visual checkboxes and state management for tracking selected clips.
    *   Updated AppBar to show context-aware actions (Select All, Download count) when valid selections exist.
    *   Extended selection UI with a "Delete" button that removes all selected clips after user confirmation.
*   **Download Functionality:**
    *   Integrated `gal` package to save media files to the device's native gallery.
    *   Added `permission_handler` logic to request and handle `storage` and `photos` permissions gracefully.
    *   Implemented `_downloadSelectedClips` method with a progress dialog to provide user feedback during batch operations.
    *   Ensured compatibility with both Android (MediaStore) and iOS (Photo Library).

### 3. Image Support & Architecture Refactor
*   **Data Model Evolution:**
    *   Refactored `VideoModel` into a generic `FileModel` to support both `FileType.video` and `FileType.image`.
    *   Updated `FileModel` to parse `type` and `duration` fields from Firestore, enabling mixed content playlists.
    *   Removed obsolete `video_model.dart` and migrated all references to `file_model.dart`.
*   **Generic Grid Implementation:**
    *   Refactored `VideoGridItem` into `FileGridItem`, capable of rendering either a `VideoPlayer` or an `Image` widget based on content type.
    *   Implemented timer-based duration logic for images to mimic video playback behavior (e.g., show image for 10s then auto-advance).
    *   Updated `AdaptiveVideoGrid` to handle heterogeneous lists of content seamlessly.
*   **Local Caching:**
    *   Updated `VideoSync` service to download and cache both images and videos to local storage.
    *   Implemented separate cache directories (`/videos`, `/images`) for better organization.

### 4. Robust Recorder (Self-Healing Mechanism)
*   **Race Condition Fixes:**
    *   Addressed a critical crash where `stopVideoRecording` and `startVideoRecording` overlapped during rapid transitions (like image slides).
    *   Implemented a global lock (`_isProcessingCamera`) to serialize all camera operations.
    *   Updated `notifySegmentEnd` to wait for the lock instead of aborting, ensuring clips are saved even if the camera is momentarily busy.
    *   Fixed a race condition where the `docId` changed before the save operation completed by capturing the ID at the start of the function.
*   **Hardware Crash Recovery:**
    *   Diagnosed `CameraException: Connection timed out` errors caused by aggressive start/stop cycles.
    *   Implemented `_restartCamera()`: A self-healing method that fully disposes and re-initializes the camera subsystem upon detecting fatal errors.
    *   Increased inter-segment safety delays from 200ms to **1000-2000ms** to allow hardware encoders to fully flush and reset.
    *   Added automatic retry logic for `Configuration Failed` errors during initialization.

## Man-Hours Estimation (Session 3)

| Category | Description | Estimated Time |
| :--- | :--- | :--- |
| **UX Enhancements** | Brightness integration, Wakelock implementation, testing on devices. | 2.5 Hours |
| **Media Management** | Selection UI state logic, Gal integration, Permission handling, Batch download flow. | 4.5 Hours |
| **Image & Refactor** | FileModel creation, Generic FileGridItem, Caching logic update, removal of legacy code. | 7.0 Hours |
| **Recorder Robustness** | Diagnosing race conditions, implementing locking mechanism, building `_restartCamera` recovery, tuning safety delays. | 5.0 Hours |
| **Total (Session 3)** | | **19.0 Hours** |

---

## Session 4: Location Tracking & User Analytics
**Date:** March 2, 2026
**Branch:** `feat/location-tracking`
**Focus:** Implementing location-based user analytics with intelligent update logic, modular architecture, and platform-specific permissions.

## Tasks Completed

### 1. Location Data Models
*   **LocationData Model:**
    *   Represents a single location point with `latitude`, `longitude`, and `timestamp`.
    *   Includes `toJson()` and `fromJson()` for Firestore serialization.
*   **UserLocationHistory Model:**
    *   Maintains an array of LocationData points with metadata (deviceId, lastUpdated).
    *   Supports efficient Firestore storage and retrieval.

### 2. LocationService (Core Location Logic)
*   **Location Fetching:**
    *   Integrated `geolocator` package for cross-platform location acquisition.
    *   Implements `getCurrentLocation()` to fetch real-time latitude and longitude.
    *   Handles permission states and graceful error handling (returns null if unavailable).
*   **Distance Calculation:**
    *   Implements `calculateDistance()` using Haversine formula to compute meters between two lat/lng points.
    *   Enables intelligent update logic to avoid unnecessary database writes.
*   **Modular Design:**
    *   Completely separated from UI layer in `lib/services/location_service.dart`.
    *   Can be called from any layer without side effects or Flutter widget dependencies.

### 3. LocationUpdateService (Background Update Management)
*   **Intelligent Update Logic:**
    *   Fetches location every 10 seconds via periodic Timer.
    *   Compares current location against last stored location in UserLocationHistory.
    *   Updates Firestore **only if** distance > 500 meters to minimize database write costs.
    *   On update: Appends new LocationData to the `locations` array in user collection and updates `lastUpdated` timestamp.
*   **State Management:**
    *   Singleton pattern (`LocationUpdateService.instance`) for global access.
    *   Maintains reference to current and last stored locations for comparison logic.
    *   Safely starts/stops the periodic timer to prevent memory leaks.
*   **Error Handling:**
    *   Gracefully handles permission denials (logs and silently skips updates).
    *   Catches Firestore errors and retries next cycle instead of crashing.

### 4. UserModel & Firestore Schema Update
*   **UserModel Extension:**
    *   Added `locations` field: `List<Map<String, dynamic>>` to store location history array.
    *   Updated `toJson()` and `fromJson()` to serialize/deserialize locations.
*   **Firestore Collection Structure:**
    *   User document now includes a `locations` array field containing timestamped lat/lng objects.
    *   `lastUpdated` timestamp separate for quick last-update-time queries.

### 5. App Initialization Integration
*   **StartupWrapper Update:**
    *   Added `LocationUpdateService.instance.startLocationTracking()` call in `initState()`.
    *   Ensures location updates begin immediately after user authentication.
    *   Stops tracking on app disposal via `LocationUpdateService.instance.stopLocationTracking()`.
*   **Non-Blocking Design:**
    *   Location service runs independently without blocking UI or other features.
    *   Modular structure prevents interference with existing functionality.

### 6. Platform Permissions
*   **iOS Info.plist:**
    *   Added `NSLocationWhenInUseUsageDescription`: For foreground location access during app usage.
    *   Added `NSLocationAlwaysAndWhenInUseUsageDescription`: For both foreground and background location access.
*   **Android AndroidManifest.xml:**
    *   Added `android.permission.ACCESS_FINE_LOCATION`: For precise location data (GPS).
    *   Added `android.permission.ACCESS_COARSE_LOCATION`: For network-based location fallback.

### 7. Dependencies
*   **geolocator:** ^10.0.0+ for cross-platform location services.
*   Existing `flutter_secure_storage` for secure device ID retrieval.
*   **permission_handler:** Already integrated for granular permission management.

## Architecture & Modularity

**Separation of Concerns:**
- `LocationService` (Pure Dart): Handles location fetching and distance math, no UI dependencies.
- `LocationUpdateService` (Dart with Firebase): Manages periodic updates and Firestore writes.
- `UserModel` (Data layer): Extended to include location history, backward compatible.
- `StartupWrapper` (UI/Init layer): Triggers location tracking on app startup.

**Benefits:**
- Location logic does not affect video playback, recording, or any other feature.
- Can be independently tested, mocked, or extended.
- Easy to add features like geofencing or location-based recommendations in the future.

## Man-Hours Estimation (Session 4)

| Category | Description | Estimated Time |
| :--- | :--- | :--- |
| **Dependency Setup** | Add geolocator, verify compatibility, configure build files. | 0.5 Hours |
| **Location Models** | Design LocationData and UserLocationHistory, Firestore serialization. | 1.0 Hours |
| **LocationService** | Implement location fetching, Haversine distance calculation, error handling. | 2.0 Hours |
| **LocationUpdateService** | Periodic timer, 500m threshold logic, Firestore array updates, state management. | 2.5 Hours |
| **UserModel & Firestore** | Extend UserModel with locations array, update schema, backward compatibility. | 1.0 Hours |
| **App Integration** | StartupWrapper integration, lifecycle management, non-blocking design. | 1.0 Hours |
| **Platform Permissions** | iOS Info.plist, Android AndroidManifest.xml, permission handler. | 0.5 Hours |
| **Testing & Validation** | Build verification, location data flow testing, Firestore document validation. | 1.0 Hours |
| **Total (Session 4)** | | **9.5 Hours** |

---
*Note: This feature is fully modular and does not impact existing functionality. The 500m threshold and 10s interval were configured to balance user movement tracking accuracy with database cost and battery efficiency.*
