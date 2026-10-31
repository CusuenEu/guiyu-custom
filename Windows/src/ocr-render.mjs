import * as pdfjs from "../node_modules/pdfjs-dist/build/pdf.mjs";
pdfjs.GlobalWorkerOptions.workerSrc = new URL("../node_modules/pdfjs-dist/build/pdf.worker.mjs", import.meta.url).href;
window.renderOcrPage = async (base64, index, preserveColors = false) => {
  const binary = atob(base64), bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  const task = pdfjs.getDocument({ data: bytes, isEvalSupported: false, disableAutoFetch: true, disableStream: true });
  const doc = await task.promise;
  try {
    if (index < 0 || index >= doc.numPages) throw Error("PDF 页码无效。");
    const page = await doc.getPage(index + 1), initial = page.getViewport({ scale: 1 });
    const scale = Math.min(1600 / initial.width, 2400 / initial.height, 4);
    const viewport = page.getViewport({ scale });
    const canvas = document.createElement("canvas");
    canvas.width = Math.ceil(viewport.width); canvas.height = Math.ceil(viewport.height);
    try {
      const context = canvas.getContext("2d", { alpha: false });
      await page.render({ canvas, canvasContext: context, viewport }).promise;
      if (!preserveColors) {
        const pixels = context.getImageData(0, 0, canvas.width, canvas.height);
        for (let i = 0; i < pixels.data.length; i += 4) {
          const darkest = Math.min(pixels.data[i], pixels.data[i + 1], pixels.data[i + 2]);
          const lightest = Math.max(pixels.data[i], pixels.data[i + 1], pixels.data[i + 2]);
          if (lightest - darkest > 40) pixels.data[i] = pixels.data[i + 1] = pixels.data[i + 2] = darkest;
        }
        context.putImageData(pixels, 0, 0);
      }
      return canvas.toDataURL("image/png").split(",")[1];
    } finally { canvas.width = 0; canvas.height = 0; page.cleanup(); }
  } finally { await task.destroy(); }
};
window.cropOcrImage = async (base64, rect) => {
  const img = new Image();
  img.src = "data:image/png;base64," + base64;
  await img.decode();
  const scale = Math.min(2, 2400 / Math.max(rect.width, rect.height));
  const pad = 20, canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.ceil(rect.width * scale) + pad * 2);
  canvas.height = Math.max(1, Math.ceil(rect.height * scale) + pad * 2);
  const context = canvas.getContext("2d", { alpha: false });
  context.fillStyle = "white";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(img, rect.left, rect.top, rect.width, rect.height, pad, pad, rect.width * scale, rect.height * scale);
  return canvas.toDataURL("image/png").split(",")[1];
};
