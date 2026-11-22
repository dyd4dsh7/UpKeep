# Upkeep Icon Composer artwork

The full-canvas SVG layers in `Support/AppIcon.icon/Assets/` are the editable source artwork for `Support/AppIcon.icon`.

In Icon Composer:

1. Create a macOS icon named `AppIcon` with a warm white canvas (`#FAF9F7`).
2. Import `Assets/01-loop-arrow.svg` and `Assets/02-down-arrow.svg` in that order.
3. Keep both layers opaque; apply subtle automatic specular highlights and low refraction.
4. For Dark, use a near-black blue canvas (`#17191D`) and preserve the blue artwork.
5. For Mono, map the loop to the primary tone and the down arrow to a lighter secondary tone.
6. Save over `Support/AppIcon.icon` after making any visual refinements.

The SwiftPM packaging script ships only `AppIcon.icns`. It does not compile an
adaptive Icon Composer asset catalog, so `AppIcon.icon` stays in the repository as
source artwork.
While running, `AppBrand` observes AppKit's effective appearance and selects the
existing light or dark PNG through `NSApplication.applicationIconImage`. AppKit
retains control of Dock sizing and the native update badge; no custom Dock view is used.
Both runtime variants are rendered into the same padded canvas (864px artwork canvas
centered in 1024px), keeping the visible plate near 824px rather than the source
artwork's nearly edge-to-edge size. In-app branding keeps the original artwork.
The stopped application's Finder/Dock icon uses the bundled ICNS fallback.
