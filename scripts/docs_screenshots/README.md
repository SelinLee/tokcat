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
The output contains light/dark menu-bar, dropdown, task dashboard, and monitor
images. The READMEs select the theme with `<picture>`.

Before publishing, inspect every image for clipped or wrapped labels, check the
OCR results, and verify the README image links. Keep real conversations and usage
screenshots out of these documentation assets.
