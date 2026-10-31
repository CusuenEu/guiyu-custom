const { test } = require("node:test"),
  assert = require("node:assert/strict");
const fs = require("node:fs/promises"),
  path = require("node:path"),
  os = require("node:os");
const {
  Store,
  entry,
  ruleFor,
  formatSuggestion,
  smartCategory,
} = require("../src/core.cjs");
const { naming } = require("../src/documents.cjs");
const formatter = require("../src/naming-format.cjs");
async function fixture(t) {
  const temp = await fs.realpath(
    await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-name-sync-")),
  );
  t.after(() => fs.rm(temp, { recursive: true, force: true }));
  const inbox = path.join(temp, "inbox");
  await fs.mkdir(inbox);
  const store = await new Store(path.join(temp, "state")).init([
    { id: "inbox", path: inbox },
  ]);
  return { temp, inbox, store };
}
test("fresh, missing, null and partial naming settings use nameOnly without rewriting saved choices", async (t) => {
  const f = await fixture(t);
  assert.deepEqual(f.store.settings.namingRules, {
    folder: "nameOnly",
    document: "nameOnly",
    dateSource: "today",
  });
  for (const value of [
    undefined,
    null,
    {},
    { folder: "month" },
    { document: "category", dateSource: "created" },
  ]) {
    const saved = {
      roots: [],
      sources: [],
      ...(value === undefined ? {} : { namingRules: value }),
    };
    await fs.writeFile(f.store.file, JSON.stringify(saved));
    const before = await fs.readFile(f.store.file, "utf8");
    const loaded = await new Store(f.store.stateDir).init();
    assert.deepEqual(loaded.settings.namingRules, {
      folder: value?.folder ?? "nameOnly",
      document: value?.document ?? "nameOnly",
      dateSource: value?.dateSource ?? "today",
    });
    assert.equal(await fs.readFile(f.store.file, "utf8"), before);
  }
});
test("eight folder/document formats preserve extension, preserve full title words, and freeze Beijing reference date", () => {
  const ref = Date.UTC(2026, 9, 31, 17); // Nov 1 Beijing.
  const base = {
    categories: [{ id: "custom", name: "客户方案", rule: ruleFor("方案") }],
    assignments: {},
  };
  for (const folder of [true, false])
    for (const format of formatter.formats) {
      const e = {
        path: "a",
        name: folder ? "旧项目" : "方案.docx",
        folder,
        identity: "id",
        created: ref,
      };
      const s = {
        ...base,
        namingRules: { folder: format, document: format, dateSource: "today" },
      };
      const c = formatSuggestion(e, s, "1001创新建设项目", ref);
      const prefix = {
        nameOnly: "",
        month: "11月 ",
        monthDay: "1101 ",
        category: "客户方案 ",
      }[format];
      assert.equal(
        c.proposedName,
        prefix + "1001创新建设项目" + (folder ? "" : ".docx"),
      );
      assert(!c.proposedName.startsWith(" "));
    }
});
test("current labels, changed rules, extracted title and identity-checked manual assignments determine suggestions", () => {
  const e = { path: "a", name: "PDF合并.txt", folder: false, identity: "id" };
  const s = {
    categories: [
      { id: "finance", name: "财务材料", rule: ruleFor("财务") },
      {
        id: "other",
        name: "其他",
        rule: { ...ruleFor("其他"), enabled: false },
      },
    ],
    assignments: {},
    namingRules: {
      folder: "category",
      document: "category",
      dateSource: "today",
    },
  };
  assert.equal(smartCategory(e, s, "年度财务报告项目"), "财务材料");
  assert.equal(
    formatSuggestion(e, s, "年度财务报告项目").editableName,
    "财务材料 年度财务报告项目",
  );
  s.categories[0].name = "新财务分类";
  assert.equal(formatSuggestion(e, s, "年度财务报告项目").prefix, "新财务分类");
  s.categories[0].rule = { ...ruleFor("合同"), keywords: ["合同"] };
  assert.equal(smartCategory(e, s, "年度财务报告项目"), "其他");
  s.assignments.a = { identity: "id", categoryID: "finance" };
  assert.equal(smartCategory(e, s, "年度财务报告项目"), "新财务分类");
  s.assignments.a.identity = "stale";
  assert.equal(smartCategory(e, s, "年度财务报告项目"), "其他");
});
test("real text extraction classifies a generic filename from its own title", async (t) => {
  const f = await fixture(t),
    p = path.join(f.inbox, "PDF合并.txt");
  await fs.writeFile(p, "项目名称：年度财务报告项目\n其他正文");
  const s = {
    ...f.store.settings,
    categories: [{ id: "finance", name: "财务材料", rule: ruleFor("财务") }],
    namingRules: {
      folder: "category",
      document: "category",
      dateSource: "today",
    },
  };
  const result = await naming(await entry(p), s, Date.UTC(2026, 9, 31));
  assert.equal(
    result.candidates[0].proposedName,
    "财务材料 年度财务报告项目.txt",
  );
});
test("literal edits and removed category survive real confirmed file/folder and batch renames", async (t) => {
  const f = await fixture(t);
  for (const format of ["nameOnly", "category"]) {
    await f.store.save({
      ...f.store.settings,
      namingRules: { folder: format, document: format, dateSource: "today" },
    });
    const file = path.join(f.inbox, format + ".txt"),
      folder = path.join(f.inbox, format + "folder");
    await fs.writeFile(file, "unchanged");
    await fs.mkdir(folder);
    const plans = [
      {
        entry: await entry(file),
        name: formatter.editedName("10月 2026用户原样输入.txt", ".txt"),
        smart: true,
      },
      { entry: await entry(folder), name: "1031 人工去掉分类", smart: true },
    ];
    // Distinguish each round without normalizing away literal date-like text.
    plans[0].name = format + " " + plans[0].name;
    plans[1].name = format + " " + plans[1].name;
    assert.equal(await f.store.rename(plans), 2);
    assert.equal(
      await fs.readFile(path.join(f.inbox, plans[0].name), "utf8"),
      "unchanged",
    );
    await fs.access(path.join(f.inbox, plans[1].name));
  }
  assert.equal(
    formatter.editedName("自定义 类别 标题.txt", ".txt"),
    "自定义 类别 标题.txt",
  );
  assert.throws(() => formatter.editedName("   ", ".txt"), /名称/);
  assert.throws(() => formatter.editedName(".txt", ".txt"), /名称/);
});
test("month and MMDD folder validation remains enforced before batch operations", async (t) => {
  const f = await fixture(t),
    a = path.join(f.inbox, "A"),
    b = path.join(f.inbox, "B");
  await fs.mkdir(a);
  await fs.mkdir(b);
  for (const format of ["month", "monthDay"]) {
    await f.store.save({
      ...f.store.settings,
      namingRules: { folder: format, document: format, dateSource: "today" },
    });
    await assert.rejects(
      f.store.rename([
        {
          entry: await entry(a),
          name: format === "month" ? "11月 有效" : "0229 有效",
          smart: true,
        },
        {
          entry: await entry(b),
          name: format === "month" ? "13月 无效" : "0230 无效",
          smart: true,
        },
      ]),
      /月份|MMDD/,
    );
    await fs.access(a);
    await fs.access(b);
  }
});
