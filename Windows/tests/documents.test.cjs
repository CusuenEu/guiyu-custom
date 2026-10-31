const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs/promises"),
  path = require("node:path"),
  os = require("node:os");
const { zipSync, strToU8 } = require("fflate");
const { entry } = require("../src/core.cjs");
const { extract, titles, naming } = require("../src/documents.cjs");
async function folder(t) {
  const p = await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-document-"));
  t.after(() => fs.rm(p, { recursive: true, force: true }));
  return p;
}
test("DOCX uses page markers and preserves explicit project title", async (t) => {
  const dir = await folder(t),
    p = path.join(dir, "方案.docx");
  await fs.writeFile(
    p,
    zipSync({
      "word/document.xml": strToU8(
        '<w:document><w:p><w:t>项目名称：网络安全运维项目</w:t></w:p><w:br w:type="page"/><w:p><w:t>第二页</w:t></w:p><w:br w:type="page"/><w:p><w:t>不得读取第三页</w:t></w:p></w:document>',
      ),
    }),
  );
  const text = await extract(await entry(p), 2);
  assert(text.includes("第二页"));
  assert(!text.includes("第三页"));
  assert.equal(titles(text)[0].name, "网络安全运维项目");
});
test("XLSX reads shared strings and first worksheet only", async (t) => {
  const dir = await folder(t),
    p = path.join(dir, "报价.xlsx");
  await fs.writeFile(
    p,
    zipSync({
      "xl/sharedStrings.xml": strToU8(
        "<sst><si><t>网络安全报价</t></si></sst>",
      ),
      "xl/worksheets/sheet1.xml": strToU8(
        "<worksheet><row><c><v>100</v></c></row></worksheet>",
      ),
      "xl/worksheets/sheet2.xml": strToU8("not loaded"),
    }),
  );
  const text = await extract(await entry(p));
  assert(text.includes("网络安全报价"));
  assert(text.includes("100"));
  assert(!text.includes("not loaded"));
});
test("PDF text layer extracts offline without native canvas", async (t) => {
  const dir = await folder(t),
    p = path.join(dir, "test.pdf");
  let content = "BT /F1 18 Tf 72 720 Td (Guiyu Project Document) Tj ET",
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
    ];
  let pdf = "%PDF-1.4\n",
    offsets = [0];
  for (let i = 0; i < objects.length; i++) {
    offsets.push(Buffer.byteLength(pdf));
    pdf += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`;
  }
  const xref = Buffer.byteLength(pdf);
  pdf +=
    `xref\n0 6\n0000000000 65535 f \n` +
    offsets
      .slice(1)
      .map((x) => String(x).padStart(10, "0") + " 00000 n \n")
      .join("") +
    `trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  await fs.writeFile(p, pdf);
  assert((await extract(await entry(p))).includes("Guiyu Project Document"));
});
