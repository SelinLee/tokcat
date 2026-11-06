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
        if(-not $window.StripButton.Visible -or $window.Sessions.Visible){throw 'The settings page did not expose its taskbar toggle.'}
        $window.ShowSettings($false)
        if(-not $window.Sessions.Visible -or $window.StripButton.Visible){throw 'The task page did not restore the task list.'}
    }finally{$window.Close();$window.Dispose()}
}
Write-Output 'Native desktop window and icon lifetime checks passed.'
