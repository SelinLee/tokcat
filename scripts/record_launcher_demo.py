#!/usr/bin/env python3
"""Record the native Cyber Wheel in an isolated English documentation build."""
import argparse
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args, cwd=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, default=Path('/tmp/tokcat-launcher-demo'))
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/assets/demos')
    args = parser.parse_args()
    work = args.work_dir.resolve()
    if work == ROOT or ROOT in work.parents:
        parser.error('Use a work directory outside the repository.')
    work.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'Package.swift', work / 'Package.swift')
    for folder in ('App', 'Sources', 'Tests'):
        if (work / folder).exists():
            shutil.rmtree(work / folder)
        shutil.copytree(ROOT / folder, work / folder)
    preview = work / 'App/Launcher/LauncherRadialPreview.swift'
    source = preview.read_text()
    start = source.index('    static let applications:')
    end = source.index('\n    static func runLive', start)
    apps = [('/Applications/Google Chrome.app', 'Google Chrome'),
            ('/System/Applications/Chess.app', 'Chess'),
            ('/System/Applications/Calculator.app', 'Calculator'),
            ('/System/Applications/Calendar.app', 'Calendar'),
            ('/System/Applications/Contacts.app', 'Contacts'),
            ('/System/Applications/Clock.app', 'Clock'),
            ('/System/Applications/Utilities/Console.app', 'Console')]
    for path, _ in apps:
        if not Path(path).exists():
            raise RuntimeError(f'Demo application is missing: {path}')
    catalog = '    static let applications: [LauncherApplication] = [\n' + ',\n'.join(
        f'        .init(url: URL(fileURLWithPath: "{path}"), name: "{name}")' for path, name in apps) + '\n    ]\n'
    source = source[:start] + catalog + source[end:]
    source = source.replace('NSApp.setActivationPolicy(.accessory)',
                            'NSApp.setActivationPolicy(.accessory)\n        NSApp.appearance = NSAppearance(named: .darkAqua)', 1)
    preview.write_text(source)
    # These substitutions affect only the temporary demo, not the installed app.
    translations = {'"输入内容…"': '"Type anything…"', '"翻译"': '"Translate"',
                    '"网页搜索"': '"Search"', '"查询中…"': '"Looking up…"'}
    for path in (work / 'App/Launcher').glob('*.swift'):
        source = path.read_text()
        for before, after in translations.items():
            source = source.replace(before, after)
        path.write_text(source)
    run('swift', 'build', '--product', 'TokcatApp', cwd=work)
    recorder = work / 'record-launcher'
    run('swiftc', ROOT / 'scripts/docs_screenshots/LauncherDemoRecorder.swift', '-o', recorder)
    movie = work / 'launcher-chrome-source.mp4'
    run(recorder, work / '.build/debug/TokcatApp', work, movie)
    args.output.mkdir(parents=True, exist_ok=True)
    # The short GIF autoplays on GitHub; its linked MP4 keeps the original fluid motion.
    run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', movie,
        '-vf', 'fps=30,scale=1200:750:flags=lanczos', '-c:v', 'libx264', '-crf', '19',
        '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', args.output / 'launcher-chrome.mp4')
    run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', movie,
        '-filter_complex', '[0:v]fps=24,scale=960:600:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle',
        '-loop', '0', args.output / 'launcher-chrome.gif')
    print(f'Demo assets: {args.output}')


if __name__ == '__main__':
    main()
