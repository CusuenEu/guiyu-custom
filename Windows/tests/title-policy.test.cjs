const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs/promises"),
  path = require("node:path"),
  os = require("node:os");
const { zipSync, strToU8 } = require("fflate"),
  policy = require("../src/title-policy.cjs"),
  { naming, recognizeTitles, pdfOpening } = require("../src/documents.cjs"),
  { entry, Store, formatSuggestion } = require("../src/core.cjs");
async function folder(t) {
  const p = await fs.realpath(
    await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-policy-")),
  );
  t.after(() => fs.rm(p, { recursive: true, force: true }));
  return p;
}
async function zipped(dir, name, items) {
  const p = path.join(dir, name);
  await fs.writeFile(
    p,
    zipSync(
      Object.fromEntries(
        Object.entries(items).map(([k, v]) => [k, strToU8(v)]),
      ),
    ),
  );
  return p;
}
const xml = (text) =>
    '<w:document xmlns:w="w"><w:body>' + text + "</w:body></w:document>",
  p = (text) => "<w:p><w:r><w:t>" + text + "</w:t></w:r></w:p>";
const settings = {
  categories: [],
  assignments: {},
  namingRules: { folder: "month", document: "category", dateSource: "today" },
};
function pdf(strings) {
  let content = [],
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ];
  for (const [i, text] of strings.entries()) {
    const page = objects.length + 1,
      stream = page + 1,
      c = `BT /F1 ${text.startsWith("body") ? 12 : 24} Tf 72 720 Td (${text}) Tj ET`;
    content.push(page);
    objects.push(
      `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents ${stream} 0 R >>`,
      `<< /Length ${c.length} >>\nstream\n${c}\nendstream`,
    );
  }
  objects[1] = `<< /Type /Pages /Kids [${content.map((n) => n + " 0 R").join(" ")}] /Count ${content.length} >>`;
  let out = "%PDF-1.4\n",
    offsets = [];
  for (const [i, obj] of objects.entries()) {
    offsets.push(Buffer.byteLength(out));
    out += `${i + 1} 0 obj\n${obj}\nendobj\n`;
  }
  const offset = Buffer.byteLength(out);
  out +=
    `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n` +
    offsets.map((n) => String(n).padStart(10, "0") + " 00000 n \n").join("") +
    `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${offset}\n%%EOF`;
  return out;
}
test("cover explicit title precedes project field; wrapped prominent title is complete", () => {
  const pages = [
    {
      index: 0,
      lines: [
        { text: "文件标题：云业务安全实施方案" },
        { text: "项目名称：采购项目" },
      ],
    },
    { index: 1, lines: [{ text: "标题：第二页备选名称" }] },
    { index: 2, lines: [{ text: "标题：第三页禁止" }] },
  ];
  const titles = policy.titleSuggestions(pages, "fixture");
  assert.equal(titles[0].name, "云业务安全实施方案");
  assert(titles.some((x) => x.name === "第二页备选名称"));
  assert(!titles.some((x) => x.name.includes("第三页")));
  assert.equal(
    policy.titleSuggestions([
      {
        index: 0,
        lines: [
          { text: "云业务", prominent: true, joinsNext: true },
          { text: "安全服务", prominent: true, joinsNext: true },
          { text: "实施方案", prominent: true },
        ],
      },
    ])[0].name,
    "云业务安全服务实施方案",
  );
});
test("scanned document title wins over referenced filename and quoted section", async (t) => {
  const dir = await folder(t), file = path.join(dir, "scan.pdf");
  await fs.writeFile(file, pdf([""]));
  const pages = await pdfOpening({ path: file, name: "scan.pdf" }, undefined, async () => ({
    text: "文件名称：采购响应文件.pdf\n关于云系统安全的\n原文对照：采购文件要求表",
    titleText: "关于云系统安全的\n审查意见书",
  }));
  const results = policy.titleSuggestions(pages, "scan.pdf");
  assert.equal(results[0].name, "关于云系统安全的审查意见书");
  assert(!results.some(x => x.name.includes("采购响应文件.pdf") || x.name.startsWith("原文对照")));
  const english = await pdfOpening({ path: file, name: "scan.pdf" }, undefined, async () => ({
    text: "Document Name: another.pdf", titleText: "Quarterly\nSecurity Report",
  }));
  assert.equal(policy.titleSuggestions(english, "scan.pdf")[0].name, "Quarterly Security Report");
});
test("title sanitation preserves meaningful words, numeric/category prefixes and book-title punctuation", () => {
  assert.equal(policy.cleanTitle("  云业务\n安全承诺书  "), "云业务安全承诺书");
  assert.equal(
    policy.cleanTitle("《技术方案》  2026：部署/验收"),
    "《技术方案》 2026-部署-验收",
  );
  assert.equal(
    formatSuggestion(
      { name: "a.PDF", folder: false, path: "a" },
      settings,
      "10月 方案 1001创新建设项目",
      Date.now(),
    ).proposedName,
    "其他 10月 方案 1001创新建设项目.PDF",
  );
});
test("real PDF reads two physical pages, never extends the budget after no result", async (t) => {
  const dir = await folder(t),
    file = path.join(dir, "原文档.PDF");
  await fs.writeFile(
    file,
    pdf([
      "First Cover Proposal",
      "Second Choice Report",
      "Forbidden Third Page Report",
    ]),
  );
  let e = await entry(file),
    titles = await recognizeTitles(e);
  assert.equal(titles[0].name, "First Cover Proposal");
  assert(titles.some((c) => c.name === "Second Choice Report"));
  assert(!titles.some((c) => c.name.includes("Forbidden")));
  assert.equal((await pdfOpening(e)).length, 2);
  await fs.writeFile(
    file,
    pdf([
      "body without usable title.",
      "body has no usable title.",
      "Forbidden Third Page Report",
    ]),
  );
  const result = await naming(await entry(file), settings);
  assert(result.fallback);
  assert.deepEqual(result.candidates, []);
  assert.equal(result.originalName, "原文档.PDF");
});
test("Word rendered/paired/blank page boundaries and soft wraps obey the opening budget", async (t) => {
  const dir = await folder(t),
    texts = [
      "标题：第一页原始方案",
      "标题：第二页候选方案",
      "标题：第三页不许出现方案",
    ];
  for (const [label, marker, first] of [
    ["rendered", "<w:lastRenderedPageBreak/>", texts[0]],
    ["paired", '<w:br w:type="page"/><w:lastRenderedPageBreak/>', texts[0]],
    ["blank", "<w:lastRenderedPageBreak/>", ""],
  ]) {
    const file = await zipped(dir, label + ".docx", {
        "word/document.xml": xml(
          [p(first), p(texts[1]), p(texts[2])].join(
            "<w:p><w:r>" + marker + "</w:r></w:p>",
          ),
        ),
      }),
      titles = await recognizeTitles(await entry(file));
    assert(
      titles.some((c) => c.name === "第二页候选方案"),
      label,
    );
    assert(!titles.some((c) => c.name.includes("第三页")), label);
    if (label === "blank") assert.equal(titles[0].name, "第二页候选方案");
  }
  const file = await zipped(dir, "wrapped.docx", {
    "word/document.xml": xml(
      p("标题：智慧园区建设项目</w:t><w:br/><w:t>网络安全实施方案"),
    ),
  });
  assert.equal(
    (await recognizeTitles(await entry(file)))[0].name,
    "智慧园区建设项目网络安全实施方案",
  );
});
test("unpaginated Word stops at 300 characters and labels evidence as an excerpt", async (t) => {
  const dir = await folder(t),
    file = await zipped(dir, "unpaged.docx", {
      "word/document.xml": xml(
        p("标题：安全实施方案") +
          p("正文内容。".repeat(65) + "标题：超过节选上限的标题报告"),
      ),
    });
  const opening = await policy.wordOpening(file),
    titles = await recognizeTitles(await entry(file));
  assert(!opening.paginated);
  assert([...opening.text].length <= 300);
  assert(!opening.text.includes("超过节选"));
  assert(titles.every((c) => c.evidence.includes("Word 开头节选")));
  assert.equal(titles[0].name, "安全实施方案");
});
test("XLSX resolves visible header cells only, including vertical headers through row 30", async (t) => {
  const dir = await folder(t),
    vertical = [..."安全检查记录表"]
      .map(
        (c, i) =>
          `<row r="${i + 1}"><c r="A${i + 1}" t="inlineStr"><is><t>${c}</t></is></c></row>`,
      )
      .join("");
  const file = await zipped(dir, "headers.xlsx", {
    "xl/workbook.xml":
      '<workbook xmlns:r="r"><sheets><sheet name="横向" r:id="r1"/><sheet name="纵向" r:id="r2"/><sheet name="隐藏" state="hidden" r:id="r3"/></sheets></workbook>',
    "xl/_rels/workbook.xml.rels":
      '<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Target="worksheets/sheet2.xml"/><Relationship Id="r3" Target="worksheets/sheet3.xml"/></Relationships>',
    "xl/sharedStrings.xml":
      "<sst><si><t>不许使用的共享字符串报告</t></si><si><t>2026年网络安全预算表</t></si></sst>",
    "xl/styles.xml":
      '<styleSheet><fonts><font><sz val="20"/><b/></font></fonts><cellXfs><xf fontId="0"/></cellXfs></styleSheet>',
    "xl/worksheets/sheet1.xml":
      '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>1</v></c><c r="B1" t="str"><f>EXEC()</f><v>不许使用的公式报告</v></c></row><row r="20"><c r="A20" s="0" t="inlineStr"><is><t>不许使用的正文报告</t></is></c></row><row r="31"><c r="A31" t="inlineStr"><is><t>不许使用的后文标题表</t></is></c></row></sheetData></worksheet>',
    "xl/worksheets/sheet2.xml":
      "<worksheet><sheetData>" + vertical + "</sheetData></worksheet>",
    "xl/worksheets/sheet3.xml":
      '<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>不许使用的隐藏标题表</t></is></c></row></sheetData></worksheet>',
  });
  const titles = await recognizeTitles(await entry(file));
  assert(titles.some((c) => c.name === "2026年网络安全预算表"));
  assert(titles.some((c) => c.name === "安全检查记录表"));
  assert(!titles.some((c) => c.name.includes("不许")));
});
test("single documents never borrow sibling titles; fallback is unchanged and makes no log", async (t) => {
  const dir = await folder(t),
    target = path.join(dir, "10月 方案原名.txt");
  await fs.writeFile(target, "目录\n正文\f目录\f标题：第三页不许出现方案");
  await fs.writeFile(path.join(dir, "招标文件.txt"), "标题：别的文档标题方案");
  const e = await entry(target),
    result = await naming(e, settings);
  assert(result.fallback);
  assert.deepEqual(result.candidates, []);
  assert.equal(result.originalName, e.name);
  const store = await new Store(path.join(dir, "state")).init([
    { id: "source", path: dir },
  ]);
  assert.equal(
    await store.rename([{ entry: e, name: e.name, smart: false }]),
    0,
  );
  assert.equal(store.settings.renames.length, 0);
  await fs.access(target);
  const xls = path.join(dir, "原表格.XLS");
  await fs.writeFile(xls, "标题：不应该解析的旧格式");
  assert((await naming(await entry(xls), settings)).fallback);
});
test("cancelled naming never opens the workbook", async () => {
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(
    recognizeTitles(
      { path: "/does-not-exist.xlsx", name: "no.xlsx", size: 1 },
      controller.signal,
    ),
    { name: "AbortError" },
  );
});

test('a failed cover OCR still permits the second physical page and never page three',async t=>{const dir=await folder(t),file=path.join(dir,'mixed.pdf');await fs.writeFile(file,pdf(['x','Second Page Proposal','Forbidden Third Page Report']));const calls=[],pages=await pdfOpening(await entry(file),undefined,async({page})=>{calls.push(page);throw Error('OCR unavailable');});assert.deepEqual(calls,[0]);assert.equal(pages.length,2);assert(policy.titleSuggestions(pages).some(c=>c.name==='Second Page Proposal'));});
