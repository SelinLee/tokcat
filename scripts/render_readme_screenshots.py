#!/usr/bin/env python3
"""Render English documentation previews from native views in an isolated source copy.

Does not change the installed app, its language, user preferences, or local agent data.
English copy is for documentation previews, not a claim of full app localization.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TOOLCHAIN = Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin')


def run(args, cwd, env):
    subprocess.run([str(arg) for arg in args], cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, help='Reuse an isolated build directory.')
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/assets/screenshots')
    args = parser.parse_args()
    work = (args.work_dir or Path(tempfile.mkdtemp(prefix='tokcat-readme-'))).resolve()
    if work == ROOT or ROOT in work.parents:
        parser.error('The isolated build directory must be outside the repository.')
    work.mkdir(parents=True, exist_ok=True)
    print(f'Preview build: {work}', flush=True)
    shutil.copy2(ROOT / 'Package.swift', work / 'Package.swift')
    for folder in ('App', 'Sources', 'Tests'):
        shutil.copytree(ROOT / folder, work / folder, dirs_exist_ok=True)
    translations = json.loads((ROOT / 'scripts/docs_screenshots/english.json').read_text())
    for folder in ('App', 'Sources'):
        for path in (work / folder).rglob('*.swift'):
            text = path.read_text()
            for original, english in sorted(translations.items(), key=lambda item: -len(item[0])):
                text = text.replace(original, english)
            path.write_text(text)

    # Date/time formatting must also be English; local OS settings stay untouched.
    for name in ('AgentSessionPreview.swift', 'AgentTaskPreview.swift'):
        path = work / 'App' / name
        text = path.read_text().replace(
            '.environment(\\.colorScheme,',
            '.environment(\\.locale, Locale(identifier: "en_US")).environment(\\.colorScheme,')
        text = text.replace('let now = Date()', 'let now = ISO8601DateFormatter().date(from: "2026-09-23T09:42:00Z")!')
        text = text.replace('"Tasks \\(count)"', '"\\(count) tasks"').replace('"Done 1"', '"1 completed"')
        path.write_text(text)
    # Live rows use a TimelineView clock; freeze it to the same demo instant.
    path = work / 'App/AgentSessionsView.swift'
    path.write_text(path.read_text().replace('let now = context.date',
        'let now = ISO8601DateFormatter().date(from: "2026-09-23T09:42:00Z")!'))
    # Long English picker labels otherwise wrap inside the Chinese-sized control.
    path = work / 'App/TaskDashboardView.swift'
    path.write_text(path.read_text().replace('.pickerStyle(.segmented).frame(width: 190)',
        '.labelsHidden().pickerStyle(.segmented).frame(width: 220)'))
    # Preserve crisp metric text in the documentation's enlarged menu-bar close-up.
    path = work / 'App/MenuBarCatIcon.swift'
    path.write_text(path.read_text().replace('private static let scale: CGFloat = 2',
                                           'private static let scale: CGFloat = 4'))
    shutil.copy2(ROOT / 'scripts/docs_screenshots/MenuBarDocumentationPreview.swift',
                 work / 'App/MenuBarDocumentationPreview.swift')
    launcher = work / 'App/TokcatApp.swift'
    text = launcher.read_text().replace('#if DEBUG', '''#if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--preview-readme-menubar"),
           CommandLine.arguments.count > index + 1 {
            do { try MenuBarDocumentationPreview.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fatalError("Documentation preview failed: \\(error)") }
            return
        }''', 1)
    launcher.write_text(text)

    env = os.environ.copy()
    env['TZ'] = 'UTC'
    sdk = Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk')
    if sdk.exists():
        env['SDKROOT'] = str(sdk)
    env['CLANG_MODULE_CACHE_PATH'] = str(work / 'ModuleCache')
    swift = TOOLCHAIN / 'swift-build'
    run([swift if swift.exists() else 'swift', *([] if swift.exists() else ['build']),
         '--disable-sandbox', '--product', 'TokcatApp'], work, env)
    candidates = [work / '.build/out/Products/Debug/TokcatApp', work / '.build/debug/TokcatApp']
    binary = next((path for path in candidates if path.exists()), None)
    if binary is None:
        raise RuntimeError('Could not locate the preview executable.')
    rendered = work / 'rendered'
    rendered.mkdir(exist_ok=True)
    for mode in ('readme-menubar', 'session-monitor', 'task-dashboard'):
        run([binary, f'--preview-{mode}', rendered, '-AppleLanguages', '(en)', '-AppleLocale', 'en_US'], work, env)
    args.output.mkdir(parents=True, exist_ok=True)
    for theme in ('light', 'dark'):
        for source, target in [('menubar-overview', 'readme-menubar'), ('ai-monitor', 'readme-dropdown'),
                               ('task-dashboard', 'readme-tasks'), ('task-monitor', 'readme-monitor')]:
            shutil.copy2(rendered / f'{source}-{theme}.png', args.output / f'{target}-{theme}.png')
    print(f'English documentation images: {args.output}', flush=True)


if __name__ == '__main__':
    main()
