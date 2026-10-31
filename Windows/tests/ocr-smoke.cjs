"use strict";
const { app, BrowserWindow } = require("electron");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const root = process.env.GUIYU_TEST_APP_ROOT || path.resolve(__dirname, "..");
const { recognize } = require(path.join(root, "src/offline-ocr.cjs"));
console.log("OCR smoke test starting");
const keepAlive = setInterval(() => {}, 1000);

function imagePdf(jpeg, width, height) {
  const parts = [Buffer.from("%PDF-1.4\n")];
  const offsets = [0];
  const add = (id, body) => {
    offsets[id] = parts.reduce((n, p) => n + p.length, 0);
    parts.push(Buffer.from(`${id} 0 obj\n`), ...body, Buffer.from("\nendobj\n"));
  };
  add(1, [Buffer.from("<< /Type /Catalog /Pages 2 0 R >>")]);
  add(2, [Buffer.from("<< /Type /Pages /Kids [3 0 R] /Count 1 >>")]);
  add(3, [Buffer.from(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${width} ${height}] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>`)]);
  add(4, [Buffer.from(`<< /Type /XObject /Subtype /Image /Width ${width} /Height ${height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>\nstream\n`), jpeg, Buffer.from("\nendstream")]);
  const content = `q ${width} 0 0 ${height} 0 0 cm /Im0 Do Q`;
  add(5, [Buffer.from(`<< /Length ${Buffer.byteLength(content)} >>\nstream\n${content}\nendstream`)]);
  const xref = parts.reduce((n, p) => n + p.length, 0);
  parts.push(Buffer.from(`xref\n0 6\n0000000000 65535 f \n${offsets.slice(1).map(n => String(n).padStart(10, "0") + " 00000 n \n").join("")}trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`));
  return Buffer.concat(parts);
}
app.whenReady().then(async () => {
  const anchor = new BrowserWindow({ show: false });
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-ocr-test-"));
  const pdf = path.join(dir, "scan.pdf");
  const source = path.join(dir, "sample.png");
  const titledImage = path.join(dir, "title.png");
  try {
    await fs.writeFile(source, await fs.readFile(path.join(root, "assets/copy-prompt.png")));
    const imageText = await recognize(source);
    if (!imageText.includes("分类")) throw Error(`Image OCR did not recognize expected Chinese text: ${imageText.slice(0, 120)}`);
    const script = "Add-Type -AssemblyName System.Drawing; $i=[System.Drawing.Image]::FromFile($env:GUIYU_TEST_IMAGE); $m=New-Object System.IO.MemoryStream; $i.Save($m,[System.Drawing.Imaging.ImageFormat]::Jpeg); [Console]::Write([Convert]::ToBase64String($m.ToArray())+'|'+$i.Width+'|'+$i.Height); $m.Dispose(); $i.Dispose()";
    const [jpeg, width, height] = execFileSync("powershell.exe", ["-NoProfile", "-Command", script], { encoding: "utf8", env: { ...process.env, GUIYU_TEST_IMAGE: source }, maxBuffer: 20 * 1024 * 1024 }).split("|");
    await fs.writeFile(pdf, imagePdf(Buffer.from(jpeg, "base64"), +width, +height));
    const pdfText = await recognize(pdf);
    if (!pdfText.includes("分类")) throw Error(`Scanned PDF OCR did not recognize expected Chinese text: ${pdfText.slice(0, 120)}`);
    const draw = "Add-Type -AssemblyName System.Drawing; $b=New-Object Drawing.Bitmap 1200,180; $g=[Drawing.Graphics]::FromImage($b); $g.Clear([Drawing.Color]::White); $f=New-Object Drawing.Font 'Microsoft YaHei',32; $g.DrawString($env:GUIYU_TEST_TITLE,$f,[Drawing.Brushes]::Black,20,35); $g.DrawString($env:GUIYU_TEST_OTHER,$f,[Drawing.Brushes]::Black,20,110); $b.Save($env:GUIYU_TEST_OUTPUT,[Drawing.Imaging.ImageFormat]::Png); $f.Dispose(); $g.Dispose(); $b.Dispose()";
    execFileSync("powershell.exe", ["-NoProfile", "-Command", draw], { env: { ...process.env, GUIYU_TEST_TITLE: "项目名称：贵州网络安全运维项目", GUIYU_TEST_OTHER: "备注：不应识别此行", GUIYU_TEST_OUTPUT: titledImage } });
    const candidates = await require(path.join(root, "src/documents.cjs")).recognizeTitles({ path: titledImage, name: "title.png", size: (await fs.stat(titledImage)).size });
    if (!candidates.some(c => c.name.includes("项目"))) throw Error(`Image naming did not produce a title: ${JSON.stringify(candidates)}`);
    const { namingPreview, recognizeRegion } = require(path.join(root, "src/naming-preview.cjs"));
    for (const file of [source, pdf]) {
      const data = await namingPreview({ path: file, name: path.basename(file), size: (await fs.stat(file)).size }, 0);
      if (!data.supported || !data.image || data.pageCount !== 1 || data.text)
        throw Error(`Preview missing image or unexpectedly contains page text for ${path.basename(file)}`);
    }
    const selected = await recognizeRegion({ path: titledImage, name: "title.png", size: (await fs.stat(titledImage)).size }, 0, { x: 0, y: 0.1, w: 1, h: 0.5 });
    if (!selected.includes("项目") || selected.includes("备注")) throw Error(`OCR must return only the selected region: ${selected}`);
    const unsupported = await namingPreview({ name: "example.docx", path: "example.docx" }, 0);
    if (unsupported.supported) throw Error("Unsupported preview must be reported clearly");
    console.log("Local image and scanned PDF OCR passed.");
  } finally {
    await fs.unlink(pdf).catch(() => {});
    await fs.unlink(source).catch(() => {});
    await fs.unlink(titledImage).catch(() => {});
    await fs.rmdir(dir).catch(() => {});
    anchor.destroy();
  }
}).then(() => { clearInterval(keepAlive); app.exit(0); }, e => { clearInterval(keepAlive); console.error(e); app.exit(1); });
