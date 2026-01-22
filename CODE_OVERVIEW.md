**Main.dart**:
- Entry point (`main`) and Firebase initialization.
- `MyApp`: app shell and theme.
- `VideoPlayerScreen`: primary UI with AppBar actions:
  - `Load videos from Firebase Storage` button → `_loadFromFirebase()`.
  - `Use hardcoded URLs` button → `_useHardcoded()`.
- `_loadFromFirebase()`: lists `videos/` in Firebase Storage, filters by metadata `contentType.startsWith('video/')`, calls `getDownloadURL()` and sets `_videoUrls`.
- `_useHardcoded()`: switches to built-in HTTPS sample URLs.
- Playback state fields: `_usingFirebase`, `_isPlaying`, `_currentPlayingUrl`.
- Passes `videoUrls` to `AdaptiveVideoGrid` and receives `onVideoStarted` / `onVideoCompleted` callbacks.

**lib/widgets/adaptive_video_grid.dart**:
- `VideoGridItem`:
  - Manages a single `VideoPlayerController` for `videoUrl`.
  - Performs a lightweight HTTP `HEAD` preflight to validate status (200) and `Content-Type: video/*` before initializing the player.
  - Auto-plays when initialized, reports progress via `onProgress`, calls `onStarted` and `onCompleted` callbacks, and triggers parent's `onDurationComplete` when finished (or after `videoDuration`).
  - Minimal retry (up to 2 attempts) on initialization failure.
- `AdaptiveVideoGrid`:
  - `PageView` of `VideoGridItem` instances.
  - Handles page changes, shows per-item progress indicators (mobile: overlay at bottom; tablet/large: footer + dots), and exposes `onVideoStarted` / `onVideoCompleted` events to the parent.
  - `goToNextVideo()` advances the page (wraps around).

**Android network config**:
- `android/app/src/main/res/xml/network_security_config.xml` added with Google domains allowed; also hardcoded sample URLs use `https://` to avoid Android cleartext restrictions.

**Behavior summary**:
- Autoplay videos, advance when finished (or after a provided `videoDuration`).
- No native controllers shown in UI; videos scale using `FittedBox` + `BoxFit.cover`.
- Loading overlay shown while fetching lists from Firebase.
- When switching lists (Firebase ↔ hardcoded): current controllers are disposed by clearing `_videoUrls` briefly; UI shows loader while the swap completes.
- Parent (`main.dart`) prevents re-loading Firebase list if a Firebase video is already playing.

**Where to look for issues**:
- If player reports "cannot parse response" or ExoPlayer `Source error`, verify the download URL — it may redirect to HTML, be expired, or return a non-video `Content-Type`.
- For iOS simulator playback problems, check ATS/HTTPS, signed URL expiration, and codec compatibility.

**Files touched**:
- `lib/main.dart`
- `lib/widgets/adaptive_video_grid.dart`
- `android/app/src/main/res/xml/network_security_config.xml`

