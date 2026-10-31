"use strict";
const fs = require("node:fs/promises");
const path = require("node:path");
const { rasterPdf, rasterImage, cropImage, recognize } = require("./offline-ocr.cjs");

// A preview is generated only for the already-authorized, verified file.
async function namingPreview(entry, index, signal) {
  if (!Number.isInteger(index) || index < 0 || index > 1) throw Error("页码无效。");
  const ext = path.extname(entry.name).toLowerCase();
  const isPdf = ext === ".pdf";
  if (entry.folder || (!isPdf && ![".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff"].includes(ext)))
    return { supported: false, message: "此类型暂不支持页面预览，您仍可选择推荐名称或手动输入。" };
  let pageCount = 1, image;
  if (isPdf) {
    if (entry.size > 30 * 1024 * 1024) throw Error("PDF 超过 30 MB，暂无法预览；仍可手动修改名称。");
    if (!global.DOMMatrix) global.DOMMatrix = (await import("@thednp/dommatrix")).default;
    const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
    const task = pdfjs.getDocument({ data: new Uint8Array(await fs.readFile(entry.path)), useSystemFonts: true, disableFontFace: true, isEvalSupported: false });
    const doc = await task.promise;
    try {
      pageCount = Math.min(2, doc.numPages);
      if (index >= pageCount) throw Error("该文件没有这一页。");
    } finally { await task.destroy(); }
    image = await rasterPdf(entry.path, index, signal, true);
  } else {
    if (index !== 0) throw Error("图片只有一页。");
    image = await rasterImage(entry.path, signal);
  }
  signal?.throwIfAborted();
  return { supported: true, index, pageCount, image: image.toString("base64") };
}

async function recognizeRegion(entry, index, region, signal) {
  if (!Number.isInteger(index) || index < 0 || index > 1) throw Error("页码无效。");
  const ext = path.extname(entry.name).toLowerCase(), isPdf = ext === ".pdf";
  if (entry.folder || (!isPdf && ![".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff"].includes(ext))) throw Error("此类型暂不支持框选识别。");
  if (!isPdf && index !== 0) throw Error("图片只有一页。");
  if (!region || ![region.x, region.y, region.w, region.h].every(Number.isFinite) || region.x < 0 || region.y < 0 || region.w <= 0 || region.h <= 0 || region.x + region.w > 1.001 || region.y + region.h > 1.001) throw Error("框选区域无效，请重新框选。");
  const image = isPdf ? await rasterPdf(entry.path, index, signal) : await rasterImage(entry.path, signal);
  const width = image.readUInt32BE(16), height = image.readUInt32BE(20);
  const left = Math.max(0, Math.floor(region.x * width)), top = Math.max(0, Math.floor(region.y * height));
  const right = Math.min(width, Math.ceil((region.x + region.w) * width)), bottom = Math.min(height, Math.ceil((region.y + region.h) * height));
  if (right - left < 8 || bottom - top < 8) throw Error("框选区域太小，请重新框选。");
  const cropped = await cropImage(image, { left, top, width: right - left, height: bottom - top }, signal);
  const text = await recognize(entry.path, index, signal, { image: cropped, singleBlock: true });
  return text.trim().slice(0, 30000);
}
module.exports = { namingPreview, recognizeRegion };
