$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
. (Join-Path $PSScriptRoot 'Load-TaskbarWidget.ps1')
Add-Type -Path (Join-Path $PSScriptRoot 'DesktopUi.cs') -ReferencedAssemblies @([Windows.Forms.Form].Assembly.Location,[Drawing.Color].Assembly.Location)
[Windows.Forms.Application]::EnableVisualStyles()
# A native handle failure must terminate a test instead of opening an unattended error dialog.
[Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::ThrowException)
foreach($iteration in 1..2){
    $window=New-Object TokcatMainWindow
    try{
        $window.Show()
        [Windows.Forms.Application]::DoEvents()
        if(-not $window.IsHandleCreated -or -not $window.Sessions.IsHandleCreated){throw 'The dashboard did not create native window handles.'}
        # ImageList reads its bitmaps lazily; creating the real window catches disposed source images.
        if($window.Sessions.SmallImageList.Handle -eq [IntPtr]::Zero){throw 'The task icon image list did not create a native handle.'}
        if($window.Sessions.SmallImageList.Images.Count -ne 8){throw 'Task state images were not available after window creation.'}
        $window.ShowSettings($true)
        if(-not $window.StripButton.Visible -or -not $window.TaskbarLayoutButton.Visible -or $window.Sessions.Visible){throw 'The settings page did not expose taskbar controls.'}
        $window.ShowSettings($false)
        if(-not $window.Sessions.Visible -or $window.StripButton.Visible){throw 'The task page did not restore the task list.'}
        $window.LauncherButton.PerformClick()
        if(-not $window.LauncherSettingsHost.Visible -or $window.Sessions.Visible -or $window.RefreshButton.Visible){throw 'The launcher navigation did not expose its settings page.'}
        $window.ShowSettings($false)
        if($window.LauncherSettingsHost.Visible -or -not $window.Sessions.Visible){throw 'Returning from launcher settings did not restore tasks.'}
    }finally{$window.Close();$window.Dispose()}
}
$dialog = [TokcatTaskbarLayoutDialog]::new([string[]]@('Output','Weekly','Upload','Download'))
try {
    $dialog.Show()
    [Windows.Forms.Application]::DoEvents()
    $grid = @($dialog.Controls | Where-Object { $_ -is [Windows.Forms.DataGridView] })[0]
    $footer = @($dialog.Controls | Where-Object { $_ -is [Windows.Forms.FlowLayoutPanel] })[0]
    if ($grid.Rows.Count -ne 2 -or $grid.Rows[0].Cells[1].Value -ne 'Weekly') { throw 'The saved taskbar layout did not load.' }
    $grid.CurrentCell = $grid.Rows[1].Cells[0]
    $footer.Controls[1].PerformClick()
    $footer.Controls[0].PerformClick()
    $grid.Rows[1].Cells[1].Value = 'FiveHour'
    $footer.Controls[3].PerformClick()
    if (($dialog.SelectedRows -join '|') -cne 'Output|Weekly||FiveHour') { throw 'The taskbar layout editor did not save separate rows.' }
} finally { $dialog.Dispose() }
Write-Output 'Native desktop window and icon lifetime checks passed.'
