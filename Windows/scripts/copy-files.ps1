$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
[string[]]$paths = ConvertFrom-Json -InputObject $env:GUIYU_COPY_PATHS
if (!$paths.Count) { throw '请选择要复制的文档或文件夹。' }
$files = New-Object System.Collections.Specialized.StringCollection
foreach ($path in $paths) {
  if (!(Test-Path -LiteralPath $path)) { throw ('文件已不存在：' + $path) }
  [void]$files.Add($path)
}
$data = New-Object System.Windows.Forms.DataObject
$data.SetFileDropList($files)
$effect = New-Object System.IO.MemoryStream
$effect.Write([byte[]](1,0,0,0), 0, 4)
$effect.Position = 0
$data.SetData('Preferred DropEffect', $effect)
# Persist the native file list after this PowerShell process exits; Copy, never Move.
[System.Windows.Forms.Clipboard]::SetDataObject($data, $true, 10, 100)
