$ErrorActionPreference='Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$inputPath = $env:GUIYU_DOCUMENT
$limit = [int]$env:GUIYU_PAGES
if($limit -lt 1){$limit=2}
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null=[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
$null=[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null=[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
$null=[Windows.Data.Pdf.PdfDocument,Windows.Data.Pdf,ContentType=WindowsRuntime]
function Await($operation,$type){
 $m=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {$_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'} | Select-Object -First 1
 $t=$m.MakeGenericMethod($type).Invoke($null,@($operation)); $t.Wait(); return $t.Result
}
function WaitAction($op){$t=[System.WindowsRuntimeSystemExtensions]::AsTask($op);$t.Wait()}
$file=Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($inputPath)) ([Windows.Storage.StorageFile])
$engine=[Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if(!$engine){throw 'Windows OCR 不可用，请在 Windows 设置中安装中文／英文 OCR 语言组件。'}
function ReadBitmap($stream){
 $decoder=Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
 $bitmap=Await ($decoder.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,[Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied)) ([Windows.Graphics.Imaging.SoftwareBitmap])
 try {$result=Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult]);return $result.Text} finally {$bitmap.Dispose()}
}
if([IO.Path]::GetExtension($inputPath).ToLower() -eq '.pdf'){
 $pdf=Await ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
 for($i=0;$i -lt [Math]::Min($limit,$pdf.PageCount);$i++){
  $page=$pdf.GetPage($i);$stream=New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
  try{$options=New-Object Windows.Data.Pdf.PdfPageRenderOptions;$options.DestinationWidth=1600; WaitAction ($page.RenderToStreamAsync($stream,$options));$stream.Seek(0);ReadBitmap $stream}finally{$stream.Dispose();$page.Dispose()}
 }
}else{$stream=Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream]);try{ReadBitmap $stream}finally{$stream.Dispose()}}
