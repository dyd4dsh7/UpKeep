# Upkeep Icon Composer artwork

These full-canvas SVG layers are the editable source artwork for `Support/AppIcon.icon`.

In Icon Composer:

1. Create a macOS icon named `AppIcon` with a warm white canvas (`#FAF9F7`).
2. Import `01-loop-arrow.svg` and `02-down-arrow.svg` in that order.
3. Keep both layers opaque; apply subtle automatic specular highlights and low refraction.
4. For Dark, use a near-black blue canvas (`#17191D`) and preserve the blue artwork.
5. For Mono, map the loop to the primary tone and the down arrow to a lighter secondary tone.
6. Save over `Support/AppIcon.icon` after making any visual refinements.

The packaging script includes both `AppIcon.icon` for Liquid Glass appearances and the existing
`AppIcon.icns` fallback for older macOS releases. The application no longer swaps flattened icons
at runtime, so macOS remains responsible for rendering and appearance treatment.
