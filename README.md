# SVSD onboarding

An eight-screen SwiftUI onboarding flow with a Metal metaball backdrop, plus a browser motion study.

## Open the iOS app

Open `SVSD.xcodeproj` in Xcode and run the `SVSD` target on an iPhone simulator. In Debug builds, tap **Replay** after the intro to play it again. The project uses SwiftUI and has no third-party dependencies.

## Preview the motion studies

Open `micro-interactions/index.html` in a browser, or serve this folder locally:

```sh
cd micro-interactions && python3 -m http.server 8000
```

Then visit `http://localhost:8000`. The opening study plays once on load: the oversized logo holds as a full-bleed screen behind “kith”, then contracts into the welcome layout. The palette follows light/dark appearance; reduced motion skips the intro.

## Source

The onboarding flow implements the linked Figma screens. Phone verification, permission steps, contacts, and location updates are simulated; the app does not read contacts, track location, or access photos. In planning, tap **Demo** to run a scripted route and schedule local push-style notifications. These are demo simulations, not remote push or live background tracking.
