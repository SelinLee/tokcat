#!/usr/bin/env python3
"""Render native menu-bar status and record Cyber Wheel in an isolated documentation build."""
import argparse
import json
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
    parser.add_argument('--reuse-launcher', action='store_true', help='Reuse the previous Chrome capture in the work directory.')
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
    shutil.copy2(ROOT / 'scripts/docs_screenshots/MenuBarMotionPreview.swift', work / 'App/MenuBarMotionPreview.swift')
    entry = work / 'App/TokcatApp.swift'
    entry.write_text(entry.read_text().replace('#if DEBUG', r'''#if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--preview-readme-menubar-motion"),
           CommandLine.arguments.count > index + 1 {
            do { try MenuBarMotionPreview.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fatalError("Menu-bar demo failed: \(error)") }
            return
        }''', 1))
    run('swift', 'build', '--product', 'TokcatApp', cwd=work)
    binary = work / '.build/debug/TokcatApp'
    frames = work / 'menubar-frames'
    if frames.exists():
        shutil.rmtree(frames)
    run(binary, '--preview-readme-menubar-motion', frames)
    movie = work / 'launcher-chrome-source.mp4'
    if args.reuse_launcher:
        if not movie.is_file():
            raise RuntimeError('No previous launcher capture exists in the work directory.')
    else:
        recorder = work / 'record-launcher'
        run('swiftc', ROOT / 'scripts/docs_screenshots/LauncherDemoRecorder.swift', '-o', recorder)
        run(recorder, binary, work, movie)
    args.output.mkdir(parents=True, exist_ok=True)
    # Retain 30 fps for the downloadable video, and an autoplaying GIF for GitHub.
    combined = args.output / 'launcher-chrome.mp4'
    duration = float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries',
        'format=duration', '-of', 'default=nw=1:nk=1', str(movie)], text=True).strip())
    intro_duration = sum(stage['frames'] for stage in json.loads((frames / 'states.json').read_text())) / 30
    ending = intro_duration + duration - 0.6
    transition = (
        '[0:v]fps=30,scale=1200:750:flags=lanczos,format=yuv420p,settb=AVTB,setpts=PTS-STARTPTS[a];'
        '[1:v]fps=30,scale=1200:750:flags=lanczos,format=yuv420p,settb=AVTB,setpts=PTS-STARTPTS[b];'
        '[2:v]fps=30,scale=1200:750:flags=lanczos,format=yuv420p,settb=AVTB,setpts=PTS-STARTPTS[c];'
        f'[a][b]xfade=transition=fade:duration=0.3:offset={intro_duration - 0.3:.6f}[mid];'
        f'[mid][c]xfade=transition=fade:duration=0.3:offset={ending:.6f}[out]')
    run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '30',
        '-i', frames / 'frame-%04d.png', '-i', movie, '-loop', '1', '-framerate', '30',
        '-t', '0.6', '-i', frames / 'frame-0000.png', '-filter_complex', transition, '-map', '[out]',
        '-c:v', 'libx264', '-crf', '19', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', combined)
    run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', combined,
        '-filter_complex', '[0:v]fps=24,scale=960:600:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle',
        '-loop', '0', args.output / 'launcher-chrome.gif')
    print(f'Menu-bar + launcher demo assets: {args.output}')


if __name__ == '__main__':
    main()
