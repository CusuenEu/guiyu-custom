$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Image]::FromFile($env:GUIYU_DOCUMENT)
try {
  if ([double]$image.Width * [double]$image.Height -gt 40000000) { throw '图片尺寸过大，请缩小后重试。' }
  $scale = [Math]::Min(1, 2400 / [Math]::Max($image.Width, $image.Height))
  $width = [Math]::Max(1, [int]($image.Width * $scale))
  $height = [Math]::Max(1, [int]($image.Height * $scale))
  $bitmap = New-Object System.Drawing.Bitmap($width, $height)
  try {
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.Clear([System.Drawing.Color]::White)
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.DrawImage($image, 0, 0, $width, $height)
    } finally { $graphics.Dispose() }
    $stream = New-Object IO.MemoryStream
    try {
      $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
      if ($stream.Length -gt 5MB) { throw '图片解码后过大，请缩小后重试。' }
      [Console]::Write([Convert]::ToBase64String($stream.ToArray()))
    } finally { $stream.Dispose() }
  } finally { $bitmap.Dispose() }
} finally { $image.Dispose() }
