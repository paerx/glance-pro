# shadercn → native Metal

Vendored from https://github.com/shadcn-labs/shadercn at
`edf7412ac6f7b377b695ca2b2d14535a3be85d44` (33 variants).

The application loads the checked-in `glance/Resources/ShaderOrbCatalog.json`.
No Node, web view, network, microphone, or JavaScript runtime is needed by Glance.
The JSON contains Metal source, uniform offsets, parameter ranges, colors and
all three state presets. Swift ports the upstream renderer's spring/drive logic.

To regenerate (Node 24.12+ recommended):

```sh
cd tools/shadercn
npm ci --ignore-scripts
npm run generate
```

TypeGPU resolves upstream TypeScript into WGSL, then naga converts it to Metal.
The generator adds a fullscreen vertex entry point and binds the single uniform
buffer at fragment buffer index 0. It does not approximate or redraw the shaders.

From the repository root, validate using a Mac with a Metal GPU:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift tools/shadercn/validate.swift \
  glance/Resources/ShaderOrbCatalog.json /tmp/glance-orbs.png
```

This compiles all 33 pipelines, checks each reflected uniform offset, renders
Thinking/Speaking/Idle (99 frames), rejects blank output and creates a contact sheet.

## Integration

Settings → General → Animation → Shader Orbs. Select ORB-01…ORB-33, then a
state to customize. Scanning maps to Thinking, success to Speaking, failure to
Idle. Each orb/state saves separate parameter, color and drive overrides.
Size applies to the overlay, bounded by the display; the inline preview is fitted
to the settings panel. Pause affects only the preview. Reset restores the current
state's upstream preset; Copy configuration exports the saved configuration JSON.

Original and Minimal remain available. Existing style preferences are preserved.
GPU rendering runs at 30 fps, at a maximum raster of 480×480; hidden/closed views
stop rendering. A missing GPU or compile error falls back to the existing assets.
Success/failure display timing and recognition decisions are unchanged.

## Attribution and licensing

The shadercn runtime is MIT (see `UPSTREAM-LICENSE`). The individual upstream
`gpu.ts` files explicitly restrict the XorDev shaders to **non-commercial use
with attribution**, despite the repository's top-level MIT license. That notice
is preserved in source and generated Metal. Do not treat the shaders as covered
by Glance's MIT license. Commercial distribution requires appropriate permission
from the shader author. See `UPSTREAM-CREDITS.md` and the packaged
`glance/Resources/ShaderOrb-LICENSE.txt`.
