# Glance Grid App Functionality Overview

The Glance Grid App is a media playback and background-recording application built with Flutter. It displays sequences of videos and images from Firebase Firestore while simultaneously recording the user's reactions via the front-facing camera.

Here is a breakdown of how the key components work, focusing on content synchronization, adaptive playback, and camera recording.

## 1. Architecture & Application Initialization

- **Startup Flow (`main.dart` & `startup_wrapper.dart`)**:
  When the app launches, `StartupWrapper` determines the routing. It retrieves a unique device ID (`DeviceIdService`) and checks against Firestore (`UserService`) to see if the user is registered. 
  - If a user exists, the application proceeds to the `VideoPlayerScreen`.
  - If it is a new user, they are redirected to `UserFormScreen` to register.

## 2. Content Fetching & Synchronization (`VideoService` & `VideoSync`)

- **Fetching Media Metadata (`VideoService`)**:
  Once in the `VideoPlayerScreen`, the application queries the `videos` collection in Firestore via `VideoService.fetchVideosForDevice(deviceId)`. The resulting metadata contains URLs to media (videos and images), durations, types, and document IDs (`docId`).

- **Preloading and Caching (`VideoSync`)**:
  Media files are cached locally for smooth playback. The `AdaptiveVideoGrid` preloads files by invoking `VideoSync.instance.downloadSingleFile(...)`.
  - `VideoSync` determines the media format (e.g., `.jpg` for images, `.mp4` for videos) based on the `type`.
  - Content is downloaded to the application's local documents directory (`/images` or `/videos`).
  - If a file has already been downloaded, it returns the local file path immediately, avoiding redundant network requests.
  - As each file is downloaded, the media URL in the application's memory is replaced with the local path.

## 3. Adaptive Video Grid & Playback (`AdaptiveVideoGrid` & `FileGridItem`)

- **Media Display and Navigation (`AdaptiveVideoGrid`)**:
  The media sequence is housed in a `PageView.builder`. It cycles through the `FileGridItem` children. `_goToNextPage()` automatically triggers navigation to the next view or loops back to the start when the sequence reaches the end.
  
- **Individual Media Elements (`FileGridItem`)**:
  `FileGridItem` adapts its behavior based on the `type` parameter:
  - **Images**: Rendered inside an `Image.file` or `Image.network` widget. A `Timer` counts down based on the `duration` parameter. When the timer expires, it signals completion by calling `onCompleted` and advances to the next page via `onDurationComplete`.
  - **Videos**: Rendered using Flutter's `video_player` plugin. As the video plays, it tracks progress. When it reaches near the end (duration - 200 milliseconds margin), it fires `onCompleted` and `onDurationComplete`.
  - **Event Hooks**: `onStarted` is called when media begins playing. `onVideoDuration` accurately sets the rotation duration inside the recorder, syncing the camera's segment length with the playing media.

## 4. Foreground Camera Recording & Processing (`ForegroundRecorder.dart`)

The `RecorderManager` runs continuously in the foreground as an invisible background process. It automatically captures user reactions while they watch the media.

- **Initialization & Permissions**: 
  Triggered when `VideoPlayerScreen` builds. It solicits the user for explicit consent via persistent configurations (`SharedPreferences`) and acquires runtime device permissions (Camera & Microphone).

- **Segment-based Recording (`_rotateSegment`)**:
  To prevent enormous video files from overwhelming device storage, `RecorderManager` utilizes segmented continuous recording. Upon tracking the duration of the current media from `AdaptiveVideoGrid`, the recorder spawns an automatic rotation `Timer` (typically `duration + 5s`). This acts as a fallback to slice recordings safely.
  
- **Concurrency Locks**: 
  Safeguards the Flutter `CameraController` with `_isProcessingCamera` thread locks, effectively blocking duplicate starts and race conditions during rotations and UI saves. Self-healing mechanisms (`_restartCamera`) are present to rapidly reboot the subsystem on obscure camera exceptions.

## 5. Tying it All Together: Synchronization & Video File Storage

The real magic happens at the crossroads of `VideoPlayerScreen` and `RecorderManager`, making sure reactions map 1-to-1 with the media they correspond to.

1. **Clip Prefixing**: When a media file begins playing, `AdaptiveVideoGrid` triggers `onVideoStarted(docId)`. This directly informs the `RecorderManager` by invoking `setCurrentVideoDocId(docId)`.
2. **Camera Rotation & Completion**: When the media reaches the end, `AdaptiveVideoGrid` raises `onVideoCompleted(docId)`.
3. **Saving the Segment**: The player forcefully calls `RecorderManager.instance.notifySegmentEnd(docId)`.
4. **Storage Protocol**:
   - `notifySegmentEnd` ceases the current camera recording.
   - It captures the `.mp4` segment from camera cache.
   - It renames and duplicates this segment inside the local application documents directory with the convention: `{docId}_{timestamp}.mp4`.
   - After successfully caching the video reaction corresponding directly to the viewed media (`docId`), it immediately starts recording the next segment for the next grid item without dropping frames.
   - Users can then browse their completed reaction clips from the `ClipBrowserScreen` integrated via the player's appbar.
