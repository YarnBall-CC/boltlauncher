# Screenshot generation notes

## Output specification

- Canvas: 2880 × 1800 pixels (16:10)
- Format: PNG
- Locale: English (U.S.)
- Set: five ordered Mac App Store screenshots
- UI source: `assets/settings-window.png`, cropped from the real BoltLauncher settings screenshot
- App icon source: the repository's 1024 px icon asset

## Image generation mode

Built-in image generation created only the abstract brand background. Exact headlines, shortcut symbols, menu items, and the real settings UI are composed deterministically in `render.html` so marketing text and product behavior stay accurate.

## Background prompt

```text
Use case: ads-marketing
Asset type: master background for five Mac App Store screenshots, 16:10 landscape
Primary request: Create a premium, minimal abstract background derived from the reference app icon's cobalt blue, indigo, and warm yellow palette. Background only.
Input images: Image 1 is a color-palette reference only; do not reproduce or include the icon.
Scene/backdrop: soft icy blue to white gradient, a broad cobalt-blue glow near the lower-right edge, very subtle concentric contour lines and a faint precision grid, generous clean negative space.
Style/medium: polished Apple-adjacent editorial technology aesthetic, restrained and crisp, flat 2D with extremely subtle depth.
Composition/framing: landscape 16:10; keep the upper-left and central area calm enough for large typography and UI compositing.
Lighting/mood: bright, fast, calm, trustworthy.
Color palette: pale #EAF5FF, white, cobalt #1677EA, deep indigo #322F92, tiny optional warm-yellow accents #FFE066.
Text (verbatim): none.
Constraints: background only; no app window, no devices, no icons, no people, no text, no letters, no logos, no watermark. Avoid busy gradients or stock-photo effects.
```
