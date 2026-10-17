# SVSD onboarding

A small native SwiftUI implementation of the Figma onboarding frame, plus a browser page for comparing four logo micro-interactions.

## Open the iOS app

Open `SVSD.xcodeproj` in Xcode and run the `SVSD` target on an iPhone simulator. The project uses SwiftUI and has no third-party dependencies.

## Preview the motion studies

Open `micro-interactions/index.html` in a browser, or serve this folder locally:

```sh
cd micro-interactions && python3 -m http.server 8000
```

Then visit `http://localhost:8000`. The opening study plays once on load: the oversized logo holds as a full-bleed screen behind “kith”, then contracts into the welcome layout. The palette follows light/dark appearance; reduced motion skips the intro.

## Source

The welcome screen is based on Figma node `72:1056` in the linked `SVSD-design-comp` file (iPhone 16, 393 × 852). On launch, an inverse-color `kith` placeholder holds over the oversized SVSD mark; the mark contracts into the logo before the tagline and controls fade in. Dark appearance inverts the colors. Reduced Motion skips the intro and shows the final screen immediately. The CTA destination remains unspecified by the supplied frame.
