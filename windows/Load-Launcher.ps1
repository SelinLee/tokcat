Add-Type -AssemblyName System.Windows.Forms,System.Drawing
if (-not ('TokcatLauncherController' -as [type])) {
    $launcherSources=@((Join-Path $PSScriptRoot 'LauncherCore.cs'),(Join-Path $PSScriptRoot 'LauncherUi.cs'))
    Add-Type -Path $launcherSources -ReferencedAssemblies System.Core.dll,System.Web.Extensions.dll,System.Windows.Forms.dll,System.Drawing.dll
}
