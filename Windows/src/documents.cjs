const fs = require("node:fs/promises"),
  path = require("node:path");
const { unzipSync, strFromU8 } = require("fflate");
const { runPS, list, cleanStem, prefixFor } = require("./core.cjs");
const xml = (s) =>
  s
    .replace(/<\/(?:w:p|row|si)>/g, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(+n));
let pdfModule;
async function pdfText(e, pages) {
  if (!pdfModule) {
    const matrix = await import("@thednp/dommatrix");
    global.DOMMatrix = matrix.default;
    pdfModule = await import("pdfjs-dist/legacy/build/pdf.mjs");
  }
  const task = pdfModule.getDocument({
    data: new Uint8Array(await fs.readFile(e.path)),
    useSystemFonts: true,
    disableFontFace: true,
    isEvalSupported: false,
  });
  const doc = await task.promise;
  try {
    const parts = [];
    for (let i = 1; i <= Math.min(pages, doc.numPages); i++) {
      const page = await doc.getPage(i),
        content = await page.getTextContent();
      parts.push(
        content.items.map((x) => x.str + (x.hasEOL ? "\n" : " ")).join(""),
      );
      page.cleanup();
    }
    return parts.join("\n");
  } finally {
    await task.destroy();
  }
}
async function extract(e, pages = 2) {
  let ext = path.extname(e.path).toLowerCase();
  if (e.size > 100 * 1024 * 1024)
    throw Error("文档超过100MB，请手工填写名称。");
  if ([".txt", ".md", ".csv", ".tsv", ".json", ".log"].includes(ext)) {
    const f = await fs.open(e.path);
    try {
      let b = Buffer.alloc(24000);
      let { bytesRead } = await f.read(b);
      b = b.subarray(0, bytesRead);
      return b[0] === 255 && b[1] === 254
        ? b.subarray(2).toString("utf16le")
        : new TextDecoder("utf-8", { fatal: true }).decode(b);
    } catch {
      return "文本编码暂不支持，请手工填写名称。";
    } finally {
      await f.close();
    }
  }
  if ([".docx", ".xlsx"].includes(ext)) {
    const zip = unzipSync(new Uint8Array(await fs.readFile(e.path)), {
      filter: (f) =>
        f.originalSize <= 20 * 1024 * 1024 &&
        /^(word\/document.xml|xl\/sharedStrings.xml|xl\/worksheets\/sheet1.xml)$/.test(
          f.name,
        ),
    });
    if (ext === ".docx") {
      let body = strFromU8(zip["word/document.xml"] || new Uint8Array());
      let cuts = body.split(
        /<w:br[^>]*w:type="page"[^>]*\/>|<w:lastRenderedPageBreak\s*\/>/,
      );
      return xml(
        cuts.length > 1 ? cuts.slice(0, pages).join("\n") : body,
      ).slice(0, pages <= 2 ? 6000 : 36000);
    }
    return ["xl/sharedStrings.xml", "xl/worksheets/sheet1.xml"]
      .map((k) => xml(strFromU8(zip[k] || new Uint8Array())))
      .join("\n")
      .slice(0, 12000);
  }
  if (ext === ".pdf") {
    const text = await pdfText(e, pages);
    if (text.trim().length >= 20 || process.platform !== "win32") return text;
  }
  if (
    process.platform === "win32" &&
    [".pdf", ".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff"].includes(ext)
  ) {
    const script = await fs.readFile(
      path.join(__dirname, "../scripts/read-document.ps1"),
      "utf8",
    );
    return runPS(
      script,
      { GUIYU_DOCUMENT: e.path, GUIYU_PAGES: String(pages) },
      120000,
    );
  }
  if (process.platform === "win32" && [".doc", ".rtf"].includes(ext)) {
    return runPS(
      `$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.Encoding]::UTF8;$w=$null;$d=$null;try{$w=New-Object -ComObject Word.Application;$w.Visible=$false;$w.DisplayAlerts=0;$w.AutomationSecurity=3;$d=$w.Documents.Open($env:GUIYU_DOCUMENT,$false,$true);$t=$d.Content.Text;$t.Substring(0,[Math]::Min(6000,$t.Length))}finally{if($d){$d.Close(0)};if($w){$w.Quit()}}`,
      { GUIYU_DOCUMENT: e.path },
    );
  }
  return "";
}
function titles(text) {
  let all = [];
  for (const re of [
    /项目名称\s*[：:]\s*([^\r\n]{4,100})/g,
    /(?:方案名称|标题|采购项目)\s*[：:]\s*([^\r\n]{4,100})/g,
  ])
    for (const m of text.matchAll(re))
      all.push({ name: m[1].trim(), evidence: "正文明确标题" });
  for (const line of text
    .split(/[\r\n]+/)
    .map((x) => x.trim())
    .slice(0, 60))
    if (
      line.length >= 6 &&
      line.length <= 90 &&
      /(项目|方案|建设|运维|采购|服务)/.test(line) &&
      !/(目录|页码|保密|注意事项|联系人|电话|投标人|供应商)/.test(line)
    )
      all.push({ name: line, evidence: "文档开头标题" });
  return all;
}
async function naming(e, settings) {
  let docs = e.folder
    ? (await list(e.path))
        .filter((x) => !x.folder && /\.(docx?|pdf|rtf|txt|md)$/i.test(x.name))
        .sort((a, b) => rank(a.name) - rank(b.name))
        .slice(0, 12)
    : [e];
  let candidates = [],
    warnings = [];
  for (const d of docs) {
    try {
      let t = await extract(d, 2),
        found = titles(t);
      if (
        !found.some((x) => x.evidence === "正文明确标题") &&
        /\.pdf$/i.test(d.name)
      )
        found.push(...titles(await extract(d, 8)));
      candidates.push(
        ...found.map((c) => ({
          ...c,
          evidence: d.name + " · " + c.evidence,
          rank: rank(d.name),
        })),
      );
    } catch (err) {
      warnings.push(d.name + "：" + err.message);
    }
  }
  if (!e.folder && !candidates.length && /投标|方案|响应/.test(e.name)) {
    const peers = (await list(path.dirname(e.path)))
      .filter(
        (d) => !d.folder && d.path !== e.path && /招标|采购|方案/.test(d.name),
      )
      .sort((a, b) => rank(a.name) - rank(b.name))
      .slice(0, 5);
    for (const d of peers) {
      try {
        candidates.push(
          ...titles(await extract(d, 2)).map((c) => ({
            ...c,
            evidence: "同项目参考 " + d.name + " · " + c.evidence,
            rank: rank(d.name),
          })),
        );
      } catch (err) {
        warnings.push(d.name + "：" + err.message);
      }
    }
  }
  const prefix = prefixFor(e, settings),
    ext = e.folder ? "" : path.extname(e.name);
  candidates.sort(
    (a, b) =>
      (a.evidence.includes("正文明确标题") ? 0 : 1) -
        (b.evidence.includes("正文明确标题") ? 0 : 1) || a.rank - b.rank,
  );
  candidates.push({
    name: e.folder ? e.name : path.basename(e.name, ext),
    evidence: "原名称，可手工修改",
  });
  const seen = new Set();
  candidates = candidates
    .map((c) => ({ ...c, name: cleanStem(c.name, prefix.category) }))
    .filter((c) => c.name && !seen.has(c.name) && seen.add(c.name))
    .slice(0, 8);
  return { entry: e, ...prefix, ext, candidates, warnings };
}
function rank(n) {
  return /(招标|采购|rfp|rfq)/i.test(n)
    ? 0
    : /(方案|建议书)/.test(n)
      ? 1
      : /(投标|响应)/.test(n)
        ? 3
        : 2;
}
module.exports = { extract, naming, titles, pdfText };
