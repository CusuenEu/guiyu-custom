const fs = require("node:fs/promises"),
  path = require("node:path");
const { unzipSync, strFromU8 } = require("fflate");
const { runPS, list, prefixFor, formatSuggestion } = require("./core.cjs");
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
const titlePolicy = require("./title-policy.cjs");
function titles(text) {
  return titlePolicy.titleSuggestions(titlePolicy.textPages(text));
}
async function pdfOpening(e, signal, ocrPage) {
  signal?.throwIfAborted();
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
  const doc = await task.promise,
    pages = [];
  try {
    for (let i = 1; i <= Math.min(2, doc.numPages); i++) {
      signal?.throwIfAborted();
      const page = await doc.getPage(i),
        content = await page.getTextContent(),
        items = content.items.filter((x) => typeof x.str === "string");
      if (
        items
          .map((x) => x.str)
          .join("")
          .trim().length < 15 &&
        (process.platform === "win32" || ocrPage)
      ) {
        let text = "";
        try {
          if(ocrPage) text = await ocrPage({file:e.path,page:i-1,signal});
          else {
            const script=await fs.readFile(path.join(__dirname,"../scripts/read-document.ps1"),"utf8");
            text=await runPS(script,{GUIYU_DOCUMENT:e.path,GUIYU_PAGES:"1",GUIYU_START_PAGE:String(i-1)},120000,signal);
          }
        } catch(error) { signal?.throwIfAborted(); /* An unavailable OCR page must not suppress page 2. */ }
        pages.push({
          index: i - 1,
          lines: titlePolicy.textPages(text)[0]?.lines || [],
        });
        page.cleanup();
        continue;
      }
      const groups = [];
      for (const item of items) {
        const x = item.transform[4],
          y = item.transform[5],
          height = Math.hypot(item.transform[2], item.transform[3]);
        let row = groups.find((r) => Math.abs(r.y - y) < 3);
        if (!row) {
          row = { y, items: [] };
          groups.push(row);
        }
        row.items.push({ text: item.str, x, width: item.width, height });
      }
      const rows = groups
        .sort((a, b) => b.y - a.y)
        .slice(0, 40)
        .map((r) => {
          const cells = r.items.sort((a, b) => a.x - b.x);
          return {
            text: cells.map((c) => c.text).join(" "),
            height: Math.max(...cells.map((c) => c.height)),
            y: r.y,
            center: (cells[0].x + cells.at(-1).x + cells.at(-1).width) / 2,
          };
        });
      const sizes = rows
          .map((r) => r.height)
          .filter(Boolean)
          .sort((a, b) => a - b),
        largest = Math.max(0, ...sizes),
        median = sizes[Math.floor(sizes.length / 2)] || 0;
      const lines = rows.map((r) => ({
        ...r,
        prominent:
          r.height >= largest * 0.9 &&
          largest >= 18 &&
          (largest >= median * 1.15 || rows.length <= 8),
      }));
      for (let j = 0; j < lines.length - 1; j++)
        lines[j].joinsNext =
          lines[j].prominent &&
          lines[j + 1].prominent &&
          Math.abs(lines[j].center - lines[j + 1].center) < 40 &&
          Math.abs(lines[j].y - lines[j + 1].y) <
            Math.max(lines[j].height, lines[j + 1].height) * 2.5;
      pages.push({ index: i - 1, lines });
      page.cleanup();
    }
  } finally {
    await task.destroy();
  }
  return pages;
}
async function recognizeTitles(e, signal) {
  signal?.throwIfAborted();
  if (e.size > 100 * 1024 * 1024)
    throw Error("文档超过100MB，请手工填写名称。");
  const ext = path.extname(e.name).toLowerCase();
  if (ext === ".xlsx")
    return titlePolicy.spreadsheetTitles(e.path, e.name, signal);
  if (ext === ".xls") return [];
  if (ext === ".pdf")
    return titlePolicy.titleSuggestions(await pdfOpening(e, signal), e.name);
  if (ext === ".docx") {
    const opening = await titlePolicy.wordOpening(e.path, signal);
    return titlePolicy
      .titleSuggestions(titlePolicy.textPages(opening.text), e.name)
      .map((c) => ({
        ...c,
        evidence: opening.paginated
          ? c.evidence
          : c.evidence.replace(/首页|第2页/g, "Word 开头节选"),
      }));
  }
  if ([".doc", ".rtf"].includes(ext)) {
    if (process.platform !== "win32") return [];
    const text = await runPS(
      `$ErrorActionPreference='Stop';[Console]::OutputEncoding=[Text.Encoding]::UTF8;$w=$null;$d=$null;try{$w=New-Object -ComObject Word.Application;$w.Visible=$false;$w.DisplayAlerts=0;$w.AutomationSecurity=3;$d=$w.Documents.Open($env:GUIYU_DOCUMENT,$false,$true);$r=$d.Range(0,[Math]::Min(300,$d.Content.End));$r.Text}finally{if($d){$d.Close(0)};if($w){$w.Quit()}}`,
      { GUIYU_DOCUMENT: e.path },
    );
    return titlePolicy
      .titleSuggestions(
        titlePolicy.textPages([...text].slice(0, 300).join("")),
        e.name,
      )
      .map((c) => ({
        ...c,
        evidence: c.evidence.replace(/首页|第2页/g, "Word 开头节选"),
      }));
  }
  if ([".txt", ".md"].includes(ext)) {
    const f = await fs.open(e.path);
    let text = "";
    try {
      const buffer = Buffer.alloc(32768),
        read = await f.read(buffer);
      const b = buffer.subarray(0, read.bytesRead);
      text =
        b[0] === 255 && b[1] === 254
          ? b.subarray(2).toString("utf16le")
          : new TextDecoder("utf-8").decode(b);
    } finally {
      await f.close();
    }
    return titlePolicy.titleSuggestions(
      titlePolicy.textPages(
        text
          .split("\f")
          .slice(0, 2)
          .map((p) => [...p].slice(0, 6000).join(""))
          .join("\f"),
      ),
      e.name,
    );
  }
  if ([".png", ".jpg", ".jpeg", ".tiff", ".tif", ".bmp"].includes(ext))
    return titlePolicy.titleSuggestions(
      titlePolicy.textPages(await extract(e, 1)),
      e.name,
    );
  return [];
}
async function naming(e, settings, referenceDate = Date.now(), signal) {
  signal?.throwIfAborted();
  let docs = [e];
  if (e.folder) {
    const all = [],
      queue = [{ path: e.path, depth: 0 }];
    while (queue.length && all.length < 1000) {
      signal?.throwIfAborted();
      const folder = queue.shift();
      for (const item of await list(folder.path)) {
        if (item.folder && folder.depth < 4)
          queue.push({ path: item.path, depth: folder.depth + 1 });
        else if (!item.folder) all.push(item);
        if (all.length >= 1000) break;
      }
    }
    const rank = (n) =>
      /(招标|采购|rfp|rfq)/i.test(n)
        ? 0
        : /(方案|建议书)/.test(n)
          ? 1
          : /(投标|响应)/.test(n)
            ? 3
            : 2;
    docs = [
      ...all.filter((x) => rank(x.name) === 0).slice(0, 5),
      ...all.filter((x) => rank(x.name) === 1).slice(0, 3),
      ...all.filter((x) => rank(x.name) === 2).slice(0, 2),
      ...all.filter((x) => rank(x.name) === 3).slice(0, 2),
    ];
  }
  let candidates = [],
    warnings = [];
  for (const doc of docs) {
    try {
      candidates.push(...(await recognizeTitles(doc, signal)));
    } catch (err) {
      signal?.throwIfAborted();
      warnings.push(doc.name + "：" + err.message);
    }
  }
  signal?.throwIfAborted();
  const seen = new Set();
  candidates = candidates
    .map((c) => ({
      ...c,
      ...formatSuggestion(e, settings, c.name, referenceDate),
    }))
    .filter((c) => c.name && !seen.has(c.name) && seen.add(c.name))
    .slice(0, 12);
  const format = candidates[0] || prefixFor(e, settings, referenceDate),
    ext = e.folder ? "" : path.extname(e.name);
  return {
    entry: e,
    prefix: format.prefix,
    category: format.category,
    format: format.format,
    ext,
    candidates,
    warnings,
    fallback: candidates.length === 0,
    originalName: e.name,
  };
}
module.exports = {
  extract,
  naming,
  titles,
  pdfText,
  pdfOpening,
  recognizeTitles,
};
