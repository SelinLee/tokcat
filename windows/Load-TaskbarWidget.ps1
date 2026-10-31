if (-not ('TokcatTaskbarWidget' -as [type])) {
    Add-Type -AssemblyName System.Windows.Forms,System.Drawing,UIAutomationClient,UIAutomationTypes,WindowsBase
    $taskbarAssemblies = @([Windows.Forms.Form].Assembly.Location, [Drawing.Color].Assembly.Location, [System.Windows.Automation.AutomationElement].Assembly.Location, [System.Windows.Automation.ControlType].Assembly.Location, [Windows.Rect].Assembly.Location) | Select-Object -Unique
    Add-Type -Path (Join-Path $PSScriptRoot 'TaskbarWidget.cs') -ReferencedAssemblies $taskbarAssemblies
}
[TokcatTaskbarWidget]::EnableDpiAwareness()
