"use strict";
const { app, BrowserWindow } = require("electron");
const fs = require("node:fs");
const path = require("node:path");
const root = process.env.GUIYU_TEST_APP_ROOT || path.resolve(__dirname, "../..");
const { pdfOpening } = require(path.join(root, "src/documents.cjs"));
const { titleSuggestions } = require(path.join(root, "src/title-policy.cjs"));
app.whenReady().then(async () => {
  const anchor = new BrowserWindow({ show: false });
  const file = process.env.GUIYU_TEST_PDF;
  const entry = { path: file, name: path.basename(file), size: fs.statSync(file).size };
  try {
    if (process.env.GUIYU_TEST_REGION) {
      const { recognizeRegion } = require(path.join(root, "src/naming-preview.cjs"));
      console.log(await recognizeRegion(entry, 0, JSON.parse(process.env.GUIYU_TEST_REGION)));
      return;
    }
    if (process.env.GUIYU_TEST_LAYOUT) {
      const result = await require(path.join(root, "src/offline-ocr.cjs")).recognize(file, 0, undefined, { layout: true });
      console.log("TITLE:", result.titleText);
      console.log(JSON.stringify(result.blocks.slice(0, 10).map(b => ({ bbox: b.bbox, paragraphs: b.paragraphs.map(p => p.lines.map(l => ({ text: l.text, bbox: l.bbox, confidence: l.confidence }))) })), null, 2));
      return;
    }
    const warnings = [];
    const pages = await pdfOpening(entry, undefined, undefined, warnings);
    const titles = titleSuggestions(pages, entry.name);
    console.log(JSON.stringify({ pages: pages.map(p => ({ index: p.index, lines: p.lines.slice(0, 18) })), titles, warnings }, null, 2));
  } finally { anchor.destroy(); }
}).then(() => app.exit(0), error => { console.error(error); app.exit(1); });
