const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs/promises"),
  os = require("node:os"),
  path = require("node:path");
const {
  Store,
  entry,
  list,
  validateName,
  ruleFor,
  parseRules,
  categoryFor,
  prefixFor,
  cleanStem,
  matches,
} = require("../src/core.cjs");
async function fixture(t) {
  const temp = await fs.realpath(
    await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-win-test-")),
  );
  t.after(() => fs.rm(temp, { recursive: true, force: true }));
  const root = path.join(temp, "root"),
    nav = path.join(root, "2026"),
    project = path.join(nav, "10月 测试项目"),
    inbox = path.join(temp, "inbox");
  await fs.mkdir(project, { recursive: true });
  await fs.mkdir(inbox);
  const store = await new Store(path.join(temp, "state")).init([
    { id: "inbox", name: "收件", path: inbox },
  ]);
  await store.addRoots([root]);
  return { temp, root, nav, project, inbox, store };
}
test("Windows name constraints and Unicode AND matching", () => {
  for (const n of ["CON.txt", "a.", "a/b", "NUL", "LPT1.doc", "a?b", ""])
    assert.throws(() => validateName(n));
  assert.equal(validateName("1001创新.docx"), "1001创新.docx");
  assert(matches("民政厅网络运维方案", "民政 运维"));
  assert(matches("ＣＡＦÉ Report", "cafe report"));
  assert(!matches("民政方案", "民政 运维"));
});
test("recent folder browsing stays within the selected directory", async (t) => {
  const f = await fixture(t);
  const recent = path.join(f.temp, "recent-folder");
  const nested = path.join(recent, "nested");
  const sibling = path.join(f.temp, "recent-folder-other");
  await fs.mkdir(nested, { recursive: true });
  await fs.mkdir(sibling);
  await fs.writeFile(path.join(nested, "document.txt"), "example");
  f.store.recentBrowseRoots = [recent];
  assert.equal((await f.store.guard(path.join(nested, "document.txt"))).folder, false);
  await assert.rejects(f.store.guard(sibling), /范围/);
});
test("metadata remains shallow and scope excludes deeper descendants", async (t) => {
  const f = await fixture(t);
  await fs.mkdir(path.join(f.project, "资料"));
  await fs.writeFile(path.join(f.project, "资料", "深层.txt"), "x");
  await fs.writeFile(path.join(f.project, "采购.txt"), "x");
  const s = await f.store.refresh();
  assert.equal(s.directories.length, 1);
  assert.equal(s.projects.length, 1);
  assert.deepEqual(
    s.files.map((e) => e.name).sort(),
    ["采购.txt", "资料"].sort(),
  );
  assert(!s.files.some((e) => e.name === "深层.txt"));
});
test("rename preserves extension, rejects stale/replaced and collision; batch preflight changes nothing", async (t) => {
  const f = await fixture(t),
    a = path.join(f.project, "a.txt"),
    b = path.join(f.project, "b.txt");
  await fs.writeFile(a, "a");
  await fs.writeFile(b, "b");
  let ae = await entry(a),
    be = await entry(b);
  await assert.rejects(
    f.store.rename([{ entry: ae, name: "a.pdf" }]),
    /扩展名/,
  );
  await assert.rejects(f.store.rename([{ entry: ae, name: "b.txt" }]), /重复/);
  await assert.rejects(
    f.store.rename([
      { entry: ae, name: "c.txt" },
      { entry: be, name: "c.txt" },
    ]),
    /重复/,
  );
  assert.equal(await fs.readFile(a, "utf8"), "a");
  await fs.writeFile(a, "new content");
  await assert.rejects(
    f.store.rename([{ entry: ae, name: "safe.txt" }]),
    /更新/,
  );
  ae = await entry(a);
  await f.store.rename([{ entry: ae, name: "safe.txt" }]);
  assert.equal(
    await fs.readFile(path.join(f.project, "safe.txt"), "utf8"),
    "new content",
  );
});
test("archive numbers collisions, preserves category, supports guarded undo", async (t) => {
  const f = await fixture(t);
  await fs.writeFile(path.join(f.inbox, "a.txt"), "incoming");
  await fs.writeFile(path.join(f.project, "a.txt"), "original");
  const item = await entry(path.join(f.inbox, "a.txt"));
  await f.store.save({
    ...f.store.settings,
    categories: [{ id: "方案", name: "方案", rule: ruleFor("方案") }],
  });
  await f.store.assign([item], "方案");
  await f.store.archive([item], f.project);
  const m = f.store.settings.moves[0];
  assert.equal(path.basename(m.destination), "a (2).txt");
  assert.equal(
    await fs.readFile(path.join(f.project, "a.txt"), "utf8"),
    "original",
  );
  assert.equal(
    categoryFor(await entry(m.destination), f.store.settings),
    "方案",
  );
  await f.store.undo(m.id);
  assert.equal(await fs.readFile(item.path, "utf8"), "incoming");
  assert(f.store.settings.moves[0].undone);
  assert.equal(
    path.basename(f.store.settings.moves[0].destination),
    "a (2).txt",
  );
});
test("undo rejects occupied original and substituted destination", async (t) => {
  const f = await fixture(t),
    p = path.join(f.inbox, "a.txt");
  await fs.writeFile(p, "original");
  await f.store.archive([await entry(p)], f.project);
  let m = f.store.settings.moves[0];
  await fs.writeFile(p, "other");
  await assert.rejects(f.store.undo(m.id), /占用/);
  await fs.unlink(p);
  await fs.rename(m.destination, m.destination + ".old");
  await fs.writeFile(m.destination, "replacement");
  await assert.rejects(f.store.undo(m.id), /替换/);
});
test("root overlap, symbolic links and self/parent-child archive blocked", async (t) => {
  const f = await fixture(t);
  await assert.rejects(f.store.addRoots([f.project]), /嵌套/);
  const folder = path.join(f.project, "子目录");
  await fs.mkdir(folder);
  await fs.writeFile(path.join(folder, "x.txt"), "x");
  await assert.rejects(
    f.store.archive([await entry(f.project)], f.project),
    /自身/,
  );
  await assert.rejects(
    f.store.archive(
      [await entry(folder), await entry(path.join(folder, "x.txt"))],
      f.project,
    ),
    /父子/,
  );
  if (process.platform !== "win32") {
    await fs.symlink(f.inbox, path.join(f.project, "link"));
    await assert.rejects(
      f.store.guard(path.join(f.project, "link")),
      /联接|链接/,
    );
  }
});
test("category specificity, exclusions, manual identity and tie fallback", () => {
  const settings = {
    categories: [
      { id: "合同", name: "合同", rule: ruleFor("合同") },
      {
        id: "方案",
        name: "方案",
        rule: { ...ruleFor("方案"), excludedKeywords: ["废弃"] },
      },
      {
        id: "其他",
        name: "其他",
        rule: { ...ruleFor("其他"), enabled: false },
      },
    ],
    assignments: {},
  };
  const e = { path: "a", name: "技术方案.docx", identity: "id", folder: false };
  assert.equal(categoryFor(e, settings), "方案");
  assert.equal(
    categoryFor({ ...e, name: "废弃技术方案.docx" }, settings),
    "其他",
  );
  settings.assignments.a = { categoryID: "合同", identity: "id" };
  assert.equal(categoryFor(e, settings), "合同");
  assert.equal(categoryFor({ ...e, identity: "new" }, settings), "方案");
});
test("rule import validates all blocks atomically", () => {
  const cats = ["合同", "方案"].map((name) => ({
    id: name,
    name,
    rule: ruleFor(name),
  }));
  const text =
    "归屿规则：1\n" +
    cats
      .map(
        (c) =>
          `分类：${c.name}\n关键词：${c.name}、测试\n排除词：无\n扩展名：无\n范围：文件和文件夹\n优先级：普通`,
      )
      .join("\n");
  assert.equal(parseRules(text, cats).length, 2);
  assert.throws(
    () => parseRules(text.replace("分类：方案", "分类：合同"), cats),
    /重复/,
  );
  assert.throws(() => parseRules(text.split("分类：方案")[0], cats), /缺少/);
  assert.equal(cats[0].rule.origin, "automatic");
});
test("Beijing naming date, existing folder month and prefix cleanup", () => {
  let s = {
    categories: [],
    assignments: {},
    namingRules: { folder: "month", document: "category", dateSource: "today" },
  };
  let e = {
    name: "10月 1001创新",
    path: "a",
    folder: true,
    created: Date.UTC(2026, 2, 3),
  };
  assert.equal(prefixFor(e, s, Date.UTC(2026, 9, 31, 17)).prefix, "11月");
  s.namingRules.dateSource = "created";
  assert.equal(prefixFor(e, s).prefix, "10月");
  assert.equal(cleanStem("10月 方案 1001创新", "方案"), "1001创新");
});
test("settings persist and corrupted state is never overwritten", async (t) => {
  const f = await fixture(t);
  await f.store.save({ ...f.store.settings, sidebarFraction: 0.4 });
  const reload = await new Store(f.store.stateDir).init();
  assert.equal(reload.settings.sidebarFraction, 0.4);
  await fs.writeFile(f.store.file, "broken");
  await assert.rejects(new Store(f.store.stateDir).init(), /防覆盖/);
  assert.equal(await fs.readFile(f.store.file, "utf8"), "broken");
});
