# App icon

`AppIcon.png` is the flat charcoal-and-warm-white icon generated with the built-in
imagegen tool. The background fills the canvas without transparent outer padding.
`favicon.png` is its 32-pixel export. The macOS bundle uses `AppIcon.icns`, built
at standard and Retina sizes by `scripts/build-icon.sh` using Apple's `sips` and
`iconutil`.

## Generation prompt

Use case: logo-brand. Create a production-ready square app icon and favicon for screen-to-codex. Minimal flat solid-color design, as restrained and clear as the ChatGPT app icon, but do NOT reproduce the OpenAI knot. ONLY TWO solid colors: warm white #F7F7F2 background and almost-black charcoal #202522 symbol. Background must fill the ENTIRE square canvas edge to edge, opaque, zero transparent margins. Large centered bold symbol occupying 82% of canvas width and height: four simple rounded screenshot corner brackets enclosing one clean chat bubble with a single terminal chevron cut out of it. Balanced thick strokes and generous clear negative space; remain readable at 16px. Perfectly straight-on, absolutely flat vector-like raster artwork. NO glass, NO gradients, NO shadows, NO glow, NO texture, NO border, NO bevel, NO 3D, NO outer rounded-square container, NO padding frame, NO text, NO letters, NO watermarks, NO mockup, NO alternate versions. One square 1024x1024 icon. The entire image is the icon, not an icon floating on another background.
