Add-Type -AssemblyName System.Windows.Forms,System.Drawing
if (-not ('TokcatLauncherController' -as [type])) {
    $launcherSources=@((Join-Path $PSScriptRoot 'LauncherCore.cs'),(Join-Path $PSScriptRoot 'LauncherUi.cs'),(Join-Path $PSScriptRoot 'LauncherTranslation.cs'),(Join-Path $PSScriptRoot 'LauncherAppearance.cs'),(Join-Path $PSScriptRoot 'LauncherSettingsPage.cs'),(Join-Path $PSScriptRoot 'EverythingSearch.cs'),(Join-Path $PSScriptRoot 'LauncherRanking.cs'))
    Add-Type -Path $launcherSources -ReferencedAssemblies System.Core.dll,System.Web.Extensions.dll,System.Windows.Forms.dll,System.Drawing.dll
}
