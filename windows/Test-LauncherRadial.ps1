param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\launcher-radial-preview'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Load-Launcher.ps1')
[Windows.Forms.Application]::EnableVisualStyles()
function Assert-Radial($condition,[string]$message) { if (-not $condition) { throw $message } }
function Pump-Radial([int]$milliseconds) {
    $deadline=[datetimeoffset]::UtcNow.AddMilliseconds($milliseconds)
    do { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 } while ([datetimeoffset]::UtcNow -lt $deadline)
}
$positions=[Collections.Generic.Dictionary[int,Drawing.PointF]]::new()
# Ensure grapheme handling never turns all letters into one straight text run.
$arc=[Drawing.Bitmap]::new(300,300); $arcGraphics=[Drawing.Graphics]::FromImage($arc); $arcFont=[Drawing.Font]::new('Consolas',18,[Drawing.GraphicsUnit]::Pixel)
try {
    $arcGraphics.Clear([Drawing.Color]::Black); $arcGraphics.TranslateTransform(150,150)
    [TokcatLauncherRadial]::DrawArcText($arcGraphics,'hello world',76,[Math]::PI*1.5,[Math]::PI*0.76,$arcFont,[Drawing.Color]::White,$true,-1,0,-1,0)
    $top=300; $bottom=0
    foreach($y in 40..120) { foreach($x in 50..250) { if($arc.GetPixel($x,$y).R -gt 100) { $top=[Math]::Min($top,$y); $bottom=[Math]::Max($bottom,$y) } } }
    Assert-Radial ($bottom-$top -gt 24) 'Letters must follow a circular baseline instead of joining into a flat text run.'
} finally { $arcFont.Dispose();$arcGraphics.Dispose();$arc.Dispose() }
# Match the Mac layout's published test vectors, including its lower-pair scan.
$weighted=[TokcatRadialLayout]::new([double[]]@(1,4,2,0.25))
Assert-Radial (($weighted.Slots.Index -join ',') -eq '1,2,0,3') 'The highest weight must complete the input circle.'
Assert-Radial ($weighted.Slots[0].Radius -eq 76 -and $weighted.Slots[0].Span -eq [Math]::PI) 'The input and leading result share a 76-point circle.'
Assert-Radial (([TokcatRadialLayout]::new([double[]]@())).Diameter -eq 226) 'The empty wheel has a 226-point canvas.'
$nine=[TokcatRadialLayout]::new([double[]]@(1,1,1,1,1,1,1,1,1))
Assert-Radial (($nine.Slots.Ring -join ',') -eq '0,1,1,1,2,2,2,2,2') 'Outer rings have capacities 3, 5, 7, ...'
foreach($case in @(@(0,'Down',3),@(4,'Up',0),@(0,'Up',1),@(1,'Down',0),@(0,'Right',2),@(0,'Left',3),@(2,'Right',8),@(8,'Left',2),@(4,'Down',4),@(8,'Right',8),@(999,'Down',0))) {
    Assert-Radial ($nine.Neighbor($case[0],[Windows.Forms.Keys]$case[1],$positions) -eq $case[2]) ('Mac directional parity: '+($case -join ' '))
}
foreach($count in 2..18) {
    $layout=[TokcatRadialLayout]::new([double[]]@(1..$count | ForEach-Object {1}))
    foreach($slot in $layout.Slots) {
        Assert-Radial ($layout.HitTest($slot.Center,$false) -eq $slot.Index -and $layout.HitTest($slot.Center,$true) -eq $slot.Index) 'Every visible sector must be clickable and aimable.'
    }
}
Assert-Radial ($nine.HitTest([Drawing.PointF]::Empty,$true) -eq -1 -and $nine.HitTest([Drawing.PointF]::new(0,-74),$true) -eq -1) 'The center and input arc must never execute a result.'
Assert-Radial ($nine.HitTest([Drawing.PointF]::new(0,104),$false) -eq -1) 'The gap between circles must stay transparent and unselectable.'
$invalid=[TokcatRadialLayout]::new([double[]]@([double]::NaN,[double]::PositiveInfinity,-5,0,1e12,0.001))
foreach($slot in $invalid.Slots) { Assert-Radial (-not [double]::IsNaN($slot.Span) -and $slot.Span -ge 0.419) 'Invalid usage weights must retain finite readable arcs.' }
$motion=[TokcatRadialMotion]::new()
$initial=[TokcatLauncherResult[]]@(0..3 | ForEach-Object { [TokcatLauncherResult]@{Key=('fixture:'+$_);Title=('结果 '+$_);RadialWeight=1} })
$motion.Update($initial,[TokcatRadialLayout]::new([double[]]@(1,1,1,1)),$false)
$reordered=[TokcatLauncherResult[]]@($initial[3],$initial[0],$initial[1],$initial[2])
$motion.Update($reordered,[TokcatRadialLayout]::new([double[]]@(1,1,1,1)),$true)
if (-not [TokcatRadialMotion]::ReducedMotion) {
    $motion.Advance(0.3)
    Assert-Radial ($motion.IsAnimating -and $motion.Flow -gt 0) 'Reflow uses a liquid spring over 0.96 seconds.'
    foreach($entry in $motion.Entries) { Assert-Radial ($entry.Id -in $initial.Key) 'Reflow retains identities across reorder.' }
    foreach($bridge in $motion.Bridges) { Assert-Radial ($bridge.Radius -gt 0 -and $bridge.End -gt $bridge.Start) 'Liquid bridges stay on a circular ring.' }
    $motion.Update([TokcatLauncherResult[]]@($initial[0]),[TokcatRadialLayout]::new([double[]]@(1)),$true)
    Assert-Radial (@($motion.Entries | Where-Object Departing).Count -eq 3) 'Interrupted reflows retain retiring entries until they fade.'
    $motion.Advance(0.96)
}
$motion.Finish()
Assert-Radial (-not $motion.IsAnimating -and $motion.Extent -eq 113) 'Settling removes retired bubbles and shrinks the canvas.'

$tempParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
$testRoot=Join-Path $tempParent ('tokcat-radial-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$palette=[Drawing.Color[]]@([Drawing.Color]::WhiteSmoke,[Drawing.Color]::White,[Drawing.Color]::Black,[Drawing.Color]::Gray,[Drawing.Color]::AliceBlue)
$controller=$null
try {
    $settings=[TokcatLauncherSettings]::new(); $settings.Skin='radial'; $settings.AutoTextColor=$true
    $settings.DictionaryPath=Join-Path $testRoot 'dictionary.json'
    $settings.Remember('first history',$null); $settings.Remember('second history',$null)
    [IO.File]::WriteAllText($settings.DictionaryPath,'{"hello":"你好；问候。\nHello, world!\n这是一段可以滚动阅读和复制的词典释义。"}',[Text.UTF8Encoding]::new($false))
    $settingsPath=Join-Path $testRoot 'launcher.json'; $settings.Save($settingsPath)
    Assert-Radial (([TokcatLauncherSettings]::Load($settingsPath)).Skin -eq 'radial') 'The third skin persists without replacing cyber.'
    $controller=[TokcatLauncherController]::new($settingsPath,$palette,$false)
    $controller.Show(); Pump-Radial 100
    $window=$controller.Window; $nativeEditor=$window.Query
    Assert-Radial ($window.Appearance.IsRadial -and $window.Radial.Following -and $window.Width -eq $window.Height) 'The real radial popup opens as a square following the pointer.'
    Assert-Radial ($window.Results.Items.Count -eq 0 -and -not $window.Hint.Visible) 'The empty wheel contains only its input arc.'
    Assert-Radial ($null -ne $window.Query.Region) 'The native editor remains focusable with its straight selection fill clipped out.'
    $keyDown=$window.GetType().GetMethod('QueryKeyDown',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$keyDown.Invoke($window,[object[]]@($window,[Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::Up)))
    [void]$keyDown.Invoke($window,[object[]]@($window,[Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::Up)))
    Assert-Radial ($window.Query.Text -eq 'first history') 'Up continues browsing history after the first recalled query.'
    [void]$keyDown.Invoke($window,[object[]]@($window,[Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::Down)))
    Assert-Radial ($window.Query.Text -eq 'second history') 'Down recalls newer history before spatial navigation resumes.'
    $window.Query.Text='hello'
    Assert-Radial (@($window.Results.Items | Where-Object Kind -eq 'translate').Count -eq 1 -and -not $window.DictionaryDefinition) 'Bare words offer opt-in translation without automatically opening definitions.'
    Assert-Radial (@($window.Results.Items | Where-Object Key -eq 'web-search').Count -eq 1) 'Every query has a small web search choice.'
    $translate=@($window.Results.Items | Where-Object Kind -eq 'translate')[0]
    $window.Results.SelectedItem=$translate; $controller.SubmitSelection()
    Pump-Radial 700
    Assert-Radial ($window.DictionaryDefinition -like '你好*') 'Selecting translation reveals the configured local dictionary.'
    Assert-Radial (@($window.Results.Items | Where-Object Kind -eq 'definition').Count -eq 1) 'Definitions provide a separate copy choice.'
    Assert-Radial (-not $window.Radial.DefinitionBounds.IsEmpty) 'A separate feathered reading surface is visible.'
    $window.Radial.BeginAim() | Out-Null; $window.Radial.MoveAim(0,76)
    $wheel=[Windows.Forms.Message]::Create($window.Handle,0x020A,[IntPtr]::new(-120*65536),[IntPtr]::Zero)
    Assert-Radial ($window.Radial.PreFilterMessage([ref]$wheel) -and $window.Radial.Reading -and $window.Radial.AimIndex -eq -1) 'Ctrl+scroll reads definitions and clears the ray target.'
    $window.Radial.FinishAim($true)
    Assert-Radial ($window.Visible -and -not $window.Radial.PointerLocked) 'Releasing a reading gesture cannot submit the copy choice.'
    $controller.ShowWebTranslations()
    Assert-Radial (-not $window.DictionaryDefinition -and @($window.Results.Items | Where-Object Kind -eq 'translation').Count -eq 2) 'Web translation remains reachable from the dictionary.'
    $window.Query.Text='sqrt(9)+2^3'; Pump-Radial 80
    Assert-Radial ($window.Results.Items[0].Kind -eq 'calculation' -and $window.Results.Items[0].Title -eq '11') 'Calculator results occupy the primary bubble.'
    $window.Radial.Navigate([Windows.Forms.Keys]::Right)
    Assert-Radial (-not $window.Radial.Following) 'Spatial keyboard selection freezes the wheel.'
    $window.Radial.BeginAim() | Out-Null
    Assert-Radial ($window.Radial.Aiming -and $window.Radial.PointerLocked) 'Ctrl pointing locks the pointer.'
    $window.Radial.FinishAim($true)
    Assert-Radial ($window.Visible -and -not $window.Radial.PointerLocked) 'A Ctrl tap in the dead zone neither submits nor keeps the pointer locked.'
    $window.Radial.BeginAim() | Out-Null; $window.Radial.MoveAim(0,76)
    $window.Radial.CancelAim()
    Assert-Radial ($window.Visible -and -not $window.Radial.PointerLocked) 'Cancelling a populated aim never executes it.'
    $window.Query.Text='setup'; $opened=@{Value=$false}; $controller.add_OpenSettings({$opened.Value=$true}.GetNewClosure())
    $window.Radial.BeginAim() | Out-Null; $window.Radial.MoveAim(0,76); $window.Radial.FinishAim($true)
    Assert-Radial ($opened.Value -and -not $window.Visible -and -not $window.Radial.PointerLocked) ('Release executes the sector under the ray and restores the pointer. opened='+$opened.Value+' visible='+$window.Visible+' locked='+$window.Radial.PointerLocked+' hint='+$window.Hint.Text+' kinds='+($window.Results.Items.Kind -join ','))
    $controller.Show(); $window.Query.Text='输入中文 café 👩‍💻 é'; Pump-Radial 80
    Assert-Radial ($window.Query -eq $nativeEditor -and $window.Query.IsHandleCreated) 'The native editor is retained for IME and Unicode.'
    $window.Appearance.Configure('cyber',$true)
    Assert-Radial ($window.Appearance.IsCyber -and -not $window.Appearance.IsRadial -and $window.Query -eq $nativeEditor) 'Switching back preserves Cyber Floating and the native editor.'
    Assert-Radial ($window.Width -eq [Math]::Round(560*$window.LayoutScale) -and $window.Query.Parent.Dock -eq 'Top') 'Floating restores its regular width and input layout.'
    $window.Appearance.Configure('classic',$false)
    Assert-Radial (-not $window.Appearance.IsCyber -and $window.TransparencyKey.IsEmpty) 'Classic restores its opaque native surface.'
    $window.Hide()

    # Deterministic native raster previews use a generated wallpaper, never user content.
    $preview=[TokcatLauncherWindow]::new($palette); $preview.IsPreview=$true
    try {
        foreach($light in @($true,$false)) {
            foreach($mode in @('empty','applications','translation','calculation','unicode')) {
                $preview.Appearance.Configure('radial',$true)
                $preview.Query.Text=switch($mode) { empty {''} applications {'应用'} translation {'tran+hello'} calculation {'sqrt(9)+2^3'} unicode {'输入中文 café 👩‍💻 é 很长的测试文本'} }
                $rows=switch($mode) {
                    empty { @() }
                    applications { @(0..8 | ForEach-Object { [TokcatLauncherResult]@{Title=(@('记事本','计算器','浏览器','文件管理器','设置','终端','代码编辑器','翻译','网页搜索')[$_]);Kind='settings';Key=('preview:'+$_);RadialWeight=(2/(1+$_*0.25))} }) }
                    translation { @([TokcatLauncherResult]@{Title='翻译';Kind='translate';Key='translate';RadialWeight=1.8},[TokcatLauncherResult]@{Title='网页搜索';Kind='website';Key='web-search';RadialWeight=0.25}) }
                    calculation { @([TokcatLauncherResult]@{Title='11';Kind='calculation';Key='calculation'},[TokcatLauncherResult]@{Title='网页搜索';Kind='website';Key='web-search';RadialWeight=0.25}) }
                    unicode { @([TokcatLauncherResult]@{Title='中文与 café 👩‍💻';Kind='translation';Key='unicode'}) }
                }
                $preview.SetResults([TokcatLauncherResult[]]$rows,''); $preview.Radial.Motion.Finish()
                $source=[Drawing.Bitmap]::new($preview.Width,$preview.Height)
                $graphics=[Drawing.Graphics]::FromImage($source)
                try { $graphics.Clear($(if($light){[Drawing.Color]::FromArgb(228,238,232)}else{[Drawing.Color]::FromArgb(22,32,48)})); $preview.Appearance.UsePreviewBackground($source) } finally { $graphics.Dispose();$source.Dispose() }
                $image=$preview.Radial.Render()
                try {
                    Assert-Radial ($image.GetPixel(0,0).A -eq 0 -and $image.GetPixel($image.Width/2,$image.Height/2).A -eq 0) 'Unused center and outer corners remain transparent.'
                    $theme=if($light){'light'}else{'dark'}
                    $image.Save((Join-Path $OutputDirectory ('radial-'+$theme+'-'+$mode+'.png')),[Drawing.Imaging.ImageFormat]::Png)
                } finally { $image.Dispose() }
            }
        }
    } finally { $preview.Dispose() }
    Write-Output 'Windows radial launcher parity checks passed.'
    Write-Output $OutputDirectory
} finally {
    if($controller) { $controller.Dispose() }
    $resolved=[IO.Path]::GetFullPath($testRoot)
    if($resolved.StartsWith($tempParent,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^tokcat-radial-test-[0-9a-f]{32}$') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
