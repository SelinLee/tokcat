# English README screenshots

The product tour uses native SwiftUI/AppKit views with synthetic tasks and English
documentation copy. These previews do not imply that the whole app is localized.
The renderer copies source files to a temporary directory, substitutes the text
in `english.json`, builds that copy, and runs the existing preview entry points.
It does not read real agent logs, change the installed app, or alter user settings.

From the repository root on macOS:

```sh
python3 scripts/render_readme_screenshots.py --work-dir /tmp/tokcat-readme-preview
swift scripts/docs_screenshots/verify_english.swift docs/assets/screenshots/readme-*.png
```

Use a work directory outside the repository. Reusing it keeps Swift build caches.
The output contains nine light/dark pairs: task dashboard, menu bar, dropdown,
task monitor, token trends, cost trends, companion interaction, character choices,
and agent support. The READMEs select the theme with `<picture>`.

Usage previews seed a temporary SQLite database and use an isolated settings
domain and task monitor. The app is never started against real data. Reused work
directories retain build caches but replace all source/resource folders, so removed
pet systems cannot survive in a documentation build.

Before publishing, inspect every image for clipped or wrapped labels, check the
OCR results, and verify the README image links. Keep real conversations and usage
screenshots out of these documentation assets.


## Menu-bar status and launcher motion demo

```sh
python3 scripts/record_launcher_demo.py
```

Requires macOS 15+, Xcode, ffmpeg, and Google Chrome in `/Applications`. Run with
Screen Recording and keyboard-event access already available to the recording
process. The default work directory is `/tmp/tokcat-launcher-demo`; choose another
with `--work-dir`, and change the asset destination with `--output`.

The script first renders a compact menu-bar example with native formatters for
`tok/s` and weekly remaining quota, with no cat icon, and the real task-dot renderer
with synthetic tasks: running (gold pulse), waiting for input/approval (gold/red flash), completed
(green), and failed (red). It then fades into a temporary English native launcher
preview with Chrome and six standard macOS apps, types `chrome` one letter at a
time, and clears the input. A final fade returns to the opening status scene.
Only its backdrop and preview windows are captured, without audio or cursor.
The installed app, its settings, and local conversations are not used. The GIF
plays in both README headers; clicking it downloads the higher-quality MP4.

Review the beginning, each typing stage, transitions, and the final empty frame
before publishing. The temporary `typing-states.json` records the real queries and matching result
titles; `menubar-frames/states.json` records the status chapter timings. Use
`--reuse-launcher` to rebuild the overview with a previously recorded native
Chrome capture from the work directory.
