$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
$paths = @()
for ($attempt = 0; $attempt -lt 10; $attempt++) {
  try {
    if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
      $paths = @([System.Windows.Forms.Clipboard]::GetFileDropList() | ForEach-Object { [string]$_ })
    }
    break
  } catch {
    if ($attempt -eq 9) { throw }
    Start-Sleep -Milliseconds 100
  }
}
ConvertTo-Json -InputObject @($paths) -Compress
