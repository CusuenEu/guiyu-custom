param([string]$OutDir = 'Windows/out')
$ErrorActionPreference = 'Stop'
if ($env:CI -ne 'true') { throw 'This installation test runs only on a disposable CI runner.' }
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop '归屿.lnk'
$actions = @(@('GuiyuName','归屿-智能命名','--smart-name'), @('GuiyuArchive','归屿-智能归档','--smart-archive'))
$registry = [Microsoft.Win32.Registry]::CurrentUser
if (Test-Path -LiteralPath $shortcutPath) { throw 'Existing desktop shortcut; refusing to overwrite.' }
foreach ($kind in @('*','Directory')) {
  foreach ($action in $actions) {
    if ($registry.OpenSubKey("Software\Classes\$kind\shell\$($action[0])")) { throw 'Existing shell entry; refusing to overwrite.' }
  }
}
$installers = @(Get-ChildItem -LiteralPath $OutDir -Filter '*-Windows-*-setup.exe')
if ($installers.Count -ne 2) { throw 'Expected both Windows installers.' }
foreach ($installer in $installers) {
  $arch = if ($installer.Name -match '-ia32-') { 'ia32' } else { 'x64' }
  $installDir = Join-Path $env:RUNNER_TEMP "归屿 安装 $arch"
  $exe = Join-Path $installDir 'Guiyu.exe'
  $process = Start-Process -FilePath $installer.FullName -ArgumentList ("/S /D=" + $installDir) -PassThru -Wait
  if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $exe)) { throw "Install failed: $arch" }
  if (!(Test-Path -LiteralPath $shortcutPath)) { throw 'Missing desktop shortcut.' }
  # Shell.Application preserves Unicode LNK paths where the legacy WSH reader does not.
  $shell = New-Object -ComObject Shell.Application
  $link = $shell.NameSpace($desktop).ParseName('归屿.lnk').GetLink
  [string]$iconPath = ''
  $iconIndex = $link.GetIconLocation([ref]$iconPath)
  Write-Host "Shortcut target=[$($link.Path)] icon=[$iconPath,$iconIndex] expected=[$exe]"
  if ($link.Path -ne $exe -or $iconPath -ne $exe -or $iconIndex -ne 0) { throw 'Wrong desktop shortcut target/icon.' }
  foreach ($kind in @('*','Directory')) {
    foreach ($action in $actions) {
      $key = $registry.OpenSubKey("Software\Classes\$kind\shell\$($action[0])")
      if (!$key -or $key.GetValue('') -ne $action[1]) { throw 'Wrong shell label.' }
      $key.Dispose()
      $key = $registry.OpenSubKey("Software\Classes\$kind\shell\$($action[0])\command")
      if ($key.GetValue('') -ne ('"' + $exe + '" ' + $action[2] + ' "%1"')) { throw 'Wrong shell command or quoting.' }
      $key.Dispose()
    }
  }
  # Manual registration (used by the ZIP edition) must have the same labels/commands.
  $env:GUIYU_EXE = $exe
  $env:GUIYU_MENU_ACTION = 'install'
  & (Join-Path $PSScriptRoot '../scripts/explorer-menu.ps1')
  foreach ($kind in @('*','Directory')) {
    foreach ($action in $actions) {
      $key = $registry.OpenSubKey("Software\Classes\$kind\shell\$($action[0])")
      if ($key.GetValue('') -ne $action[1]) { throw 'Manual shell label differs from installer.' }
      $key.Dispose()
    }
  }
  $uninstaller = Join-Path $installDir '卸载归屿.exe'
  $process = Start-Process -FilePath $uninstaller -ArgumentList '/S' -PassThru -Wait
  if ($process.ExitCode -ne 0) { throw 'Uninstall failed.' }
  if (Test-Path -LiteralPath $shortcutPath) { throw 'Desktop shortcut survived uninstall.' }
  foreach ($kind in @('*','Directory')) {
    foreach ($action in $actions) {
      if ($registry.OpenSubKey("Software\Classes\$kind\shell\$($action[0])")) { throw 'Shell entry survived uninstall.' }
    }
  }
  Write-Host "PASS: $arch installer, desktop icon, shell labels/commands, manual registration, uninstall."
}
