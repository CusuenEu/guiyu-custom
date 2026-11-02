param([Parameter(Mandatory=$true)][string]$Manifest)
# A launcher started from PowerShell 7 can pass module paths incompatible with
# Windows PowerShell 5.1. This helper needs only the system's own modules.
$env:PSModulePath = [IO.Path]::Combine($PSHOME, 'Modules')
$ErrorActionPreference = 'Stop'
$data = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
function Status($phase, $message, $processId = 0) {
  @{ phase=$phase; message=$message; processId=$processId } | ConvertTo-Json -Compress | Set-Content -LiteralPath $data.statusFile -Encoding UTF8
}
try {
  if ($data.digest -notmatch '^[a-f0-9]{64}$' -or $data.packageVersion -notmatch '^\d{4}\.\d{3,4}\.\d{1,2}$') { throw 'Invalid update metadata' }
  $stream = [IO.File]::OpenRead($data.installer)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $actualHash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
  finally { $stream.Dispose(); $sha.Dispose() }
  if ($actualHash -ne $data.digest) { throw 'Installer checksum changed' }
  @{ pid=$PID } | ConvertTo-Json -Compress | Set-Content -LiteralPath $data.readyFile -Encoding UTF8
  Status 'waiting' 'Waiting for Guiyu to close'
  # No forced termination: give normal file operations and Electron shutdown time.
  $parent = Get-Process -Id $data.parentPid -ErrorAction SilentlyContinue
  if ($parent) { $parent | Wait-Process -Timeout 120 }
  Status 'installing' 'Installing verified update'
  $installer = Start-Process -FilePath $data.installer -ArgumentList ('/S /D=' + $data.installDir) -PassThru -Wait
  if ($installer.ExitCode -ne 0) { throw "Installer exited with $($installer.ExitCode)" }
  $version = (Get-Item -LiteralPath $data.executable).VersionInfo.ProductVersion
  if ($version -ne $data.packageVersion -and $version -ne ($data.packageVersion + '.0')) { throw "Unexpected installed version: $version" }
  $restarted = Start-Process -FilePath $data.executable -WorkingDirectory $data.installDir -PassThru
  Status 'completed' 'Update installed and Guiyu restarted' $restarted.Id
  Remove-Item -LiteralPath $data.installer -Force
} catch {
  Status 'failed' $_.Exception.Message
  # Keep the verified installer and status log for retry; do not claim success.
  Add-Type -AssemblyName System.Windows.Forms
  [Windows.Forms.MessageBox]::Show("更新未完成：$($_.Exception.Message)`n请重试或运行此安装包：`n$($data.installer)", '归屿更新', 'OK', 'Error') | Out-Null
  exit 1
}
