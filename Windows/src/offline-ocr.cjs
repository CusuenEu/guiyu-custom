"use strict";
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const { runPS } = require("./core.cjs");

async function rasterPdf(file, page, signal, preserveColors = false) {
  const { BrowserWindow, session } = require("electron");
  if (!BrowserWindow) throw Error("PDF 图片识别需要从归屿应用启动。");
  const bytes = await fs.readFile(file);
  if (bytes.length > 30 * 1024 * 1024) throw Error("扫描 PDF 超过 30MB，请手工填写名称。");
  signal?.throwIfAborted();
  const isolated = session.fromPartition("guiyu-offline-ocr");
  isolated.webRequest.onBeforeRequest((details, callback) => callback({ cancel: !/^(file|data|blob):/i.test(details.url) }));
  const win = new BrowserWindow({ show: false, webPreferences: { session: isolated, sandbox: true, contextIsolation: true, nodeIntegration: false, webSecurity: true } });
  const abort = () => { if (!win.isDestroyed()) win.destroy(); };
  signal?.addEventListener("abort", abort, { once: true });
  try {
    await win.loadFile(path.join(__dirname, "ocr-render.html"));
    signal?.throwIfAborted();
    const encoded = await win.webContents.executeJavaScript(`window.renderOcrPage(${JSON.stringify(bytes.toString("base64"))}, ${Number(page)}, ${!!preserveColors})`);
    signal?.throwIfAborted();
    if (typeof encoded !== "string" || encoded.length > 8 * 1024 * 1024) throw Error("PDF 页面过大，请手工填写名称。");
    return Buffer.from(encoded, "base64");
  } finally {
    signal?.removeEventListener("abort", abort);
    if (!win.isDestroyed()) win.destroy();
  }
}

// Always pass local model bytes: Tesseract's default otherwise downloads models.
async function rasterImage(file, signal) {
  const script = await fs.readFile(path.join(__dirname, "../scripts/raster-document.ps1"), "utf8");
  return Buffer.from((await runPS(script, { GUIYU_DOCUMENT: file }, 120000, signal)).trim(), "base64");
}
async function cropImage(image, rect, signal) {
  const { BrowserWindow, session } = require("electron");
  if (!BrowserWindow) throw Error("框选识别需要从归屿应用启动。");
  signal?.throwIfAborted();
  const isolated = session.fromPartition("guiyu-offline-ocr");
  isolated.webRequest.onBeforeRequest((details, callback) => callback({ cancel: !/^(file|data|blob):/i.test(details.url) }));
  const win = new BrowserWindow({ show: false, webPreferences: { session: isolated, sandbox: true, contextIsolation: true, nodeIntegration: false, webSecurity: true } });
  const abort = () => { if (!win.isDestroyed()) win.destroy(); };
  signal?.addEventListener("abort", abort, { once: true });
  try {
    await win.loadFile(path.join(__dirname, "ocr-render.html"));
    signal?.throwIfAborted();
    const encoded = await win.webContents.executeJavaScript(`window.cropOcrImage(${JSON.stringify(image.toString("base64"))}, ${JSON.stringify(rect)})`);
    signal?.throwIfAborted();
    if (typeof encoded !== "string" || encoded.length > 8 * 1024 * 1024) throw Error("框选区域过大，请缩小范围。");
    return Buffer.from(encoded, "base64");
  } finally {
    signal?.removeEventListener("abort", abort);
    if (!win.isDestroyed()) win.destroy();
  }
}
async function recognize(file, page = 0, signal, options = {}) {
  signal?.throwIfAborted();
  if (process.platform !== "win32") throw Error("本地图片识别需要 Windows。");
  let image;
  if (options.image) image = options.image;
  else if (path.extname(file).toLowerCase() === ".pdf") image = await rasterPdf(file, page, signal);
  else image = await rasterImage(file, signal);
  signal?.throwIfAborted();
  if (!image.length) throw Error("图片无法解码，请手动输入名称。");
  const { createWorker } = require("tesseract.js");
  const modelDir = await fs.mkdtemp(path.join(os.tmpdir(), "Guiyu-ocr-model-"));
  let worker;
  try {
    for (const code of ["chi_sim", "eng"]) {
      const root = path.dirname(require.resolve(`@tesseract.js-data/${code}`));
      await fs.copyFile(path.join(root, "4.0.0_best_int", `${code}.traineddata.gz`), path.join(modelDir, `${code}.traineddata.gz`));
    }
    signal?.throwIfAborted();
    // Electron workers need a real file path when dependencies are unpacked from ASAR.
    const workerPath = require.resolve("tesseract.js/src/worker-script/node/index.js").replace(/app\.asar(?=[\\/])/, "app.asar.unpacked");
    worker = await createWorker("chi_sim+eng", 1, { workerPath, langPath: modelDir, cacheMethod: "none", errorHandler: () => {} });
    signal?.throwIfAborted();
    let abort;
    const cancellation = new Promise((_, reject) => {
      abort = () => { void worker.terminate(); reject(signal.reason || new Error("识别已取消。")); };
      signal?.addEventListener("abort", abort, { once: true });
    });
    try {
      if (options.singleBlock) await worker.setParameters({ tessedit_pageseg_mode: "6" });
      const result = await Promise.race([worker.recognize(image, {}, { text: true, blocks: !!options.layout }), cancellation]);
      signal?.throwIfAborted();
      const normalize = text => (text || "").replace(/(?<=\p{Script=Han})[ \t]+(?=\p{Script=Han})/gu, "");
      if (!options.layout) return normalize(result.data.text);
      const blocks = result.data.blocks || [];
      const lines = blocks.flatMap(b => b.paragraphs || []).flatMap(p => p.lines || []);
      const sizes = lines.map(l => l.bbox.y1 - l.bbox.y0).filter(n => n > 0).sort((a, b) => a - b);
      const median = sizes[Math.floor(sizes.length / 2)] || 0;
      const width = image.readUInt32BE(16), height = image.readUInt32BE(20);
      const candidates = lines.filter(l => {
        const box = l.bbox, h = box.y1 - box.y0;
        return l.confidence >= 60 && (l.text.match(/\p{Script=Han}/gu) || []).length >= 4 && h >= median * 1.45 &&
          box.y0 < height * 0.4 && Math.abs((box.x0 + box.x1) / 2 - width / 2) < width * 0.2;
      }).sort((a, b) => a.bbox.y0 - b.bbox.y0);
      let titleText = "";
      if (candidates.length) {
        const box = candidates[0].bbox, h = box.y1 - box.y0;
        const left = Math.max(0, Math.floor(box.x0 - width * 0.12)), right = Math.min(width, Math.ceil(box.x1 + width * 0.12));
        const top = Math.max(0, Math.floor(box.y0 - h * 0.3)), bottom = Math.min(height, Math.ceil(box.y0 + h * 3.2));
        await worker.setParameters({ tessedit_pageseg_mode: "6" });
        const cropped = await Promise.race([worker.recognize(image, { rectangle: { left, top, width: right - left, height: bottom - top } }, { text: true }), cancellation]);
        signal?.throwIfAborted();
        titleText = normalize(cropped.data.text).trim();
      }
      return { text: normalize(result.data.text), blocks, titleText };
    } finally { signal?.removeEventListener("abort", abort); }
  } finally {
    if (worker) await worker.terminate();
    await Promise.all(["chi_sim", "eng"].map((code) => fs.unlink(path.join(modelDir, `${code}.traineddata.gz`)).catch(() => {})));
    await fs.rmdir(modelDir).catch(() => {});
  }
}
module.exports = { recognize, rasterPdf, rasterImage, cropImage };
