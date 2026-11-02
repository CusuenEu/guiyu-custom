"use strict";
const fs = require("node:fs/promises"),
  path = require("node:path"),
  crypto = require("node:crypto");
const { execFile } = require("node:child_process");
const namingFormat = require("./naming-format.cjs");
const norm = (s) =>
  String(s).normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase();
const matches = (name, q) =>
  norm(q)
    .trim()
    .split(/\s+/)
    .every((t) => norm(name).includes(t));
const key = (p) =>
  process.platform === "win32"
    ? path.resolve(p).toLowerCase()
    : path.resolve(p);
const inside = (p, root) =>
  key(p) === key(root) || key(p).startsWith(key(root) + path.sep);
const overlap = (a, b) => inside(a, b) || inside(b, a);
async function exists(p) {
  try {
    await fs.lstat(p);
    return true;
  } catch (e) {
    if (e.code === "ENOENT") return false;
    throw e;
  }
}
async function entry(p) {
  let s = await fs.lstat(p);
  if (s.isSymbolicLink())
    throw Error("暂不操作符号链接或目录联接，请在资源管理器中处理。");
  return {
    path: p,
    name: path.basename(p),
    folder: s.isDirectory(),
    size: s.size,
    mtime: s.mtimeMs,
    created: s.birthtimeMs,
    identity: `${s.dev}:${s.ino}`,
    version: `${s.size}:${s.mtimeMs}`,
  };
}
async function list(p) {
  return (
    await Promise.all(
      (await fs.readdir(p, { withFileTypes: true }))
        .filter(
          (d) =>
            !d.name.startsWith(".") &&
            !["desktop.ini", "Thumbs.db"].includes(d.name),
        )
        .map((d) => entry(path.join(p, d.name)).catch(() => null)),
    )
  ).filter(Boolean);
}
function validateName(name) {
  if (
    typeof name !== "string" ||
    !name.trim() ||
    name !== name.trim() ||
    /[<>:"/\\|?*\x00-\x1f]/.test(name) ||
    /[. ]$/.test(name) ||
    /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(name) ||
    name.length > 240
  )
    throw Error("名称为空、过长，或包含 Windows 不允许的字符／保留名称。");
  return name;
}
async function verify(e) {
  let now = await entry(e.path);
  if (now.identity !== e.identity || now.version !== e.version)
    throw Error("文件已更新或被替换，请关闭窗口后重新选择：" + e.name);
  return now;
}
function runPS(script, env = {}, timeout = 90000, signal) {
  return new Promise((resolve, reject) =>
    execFile(
      "powershell.exe",
      [
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-STA",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        script,
      ],
      {
        env: { ...process.env, ...env },
        windowsHide: true,
        timeout,
        signal,
        maxBuffer: 8 * 1024 * 1024,
        encoding: "utf8",
      },
      (err, out, stderr) =>
        err
          ? reject(Error(err.killed ? "Windows 操作超时，请稍后重试。" : (stderr || err.message).trim()))
          : resolve(out.replace(/^\uFEFF/, "")),
    ),
  );
}
async function moveExclusive(src, dst) {
  if (await exists(dst)) throw Error("目标同名，未覆盖：" + path.basename(dst));
  if (process.platform === "win32") {
    try {
      await runPS(
        `$ErrorActionPreference='Stop'; Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class GuiyuMove { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool MoveFileW(string a,string b); }'; if(-not [GuiyuMove]::MoveFileW($env:GUIYU_SRC,$env:GUIYU_DST)){$code=[Runtime.InteropServices.Marshal]::GetLastWin32Error(); [Console]::Error.WriteLine('GUIYU_MOVE_ERROR:'+$code); exit 1}`,
        { GUIYU_SRC: path.toNamespacedPath(src), GUIYU_DST: path.toNamespacedPath(dst) },
      );
    } catch (error) {
      const code = Number(error.message.match(/GUIYU_MOVE_ERROR:(\d+)/)?.[1]);
      const reason = {
        2: "原文件不存在，请刷新后重试。",
        3: "文件所在目录不存在，请刷新后重试。",
        5: "没有权限或文件正被占用，请检查目录权限并关闭占用文件的程序。",
        32: "文件正在被其他程序使用，请关闭占用该文件的程序后重试。",
        33: "文件已被其他程序锁定，请关闭占用该文件的程序后重试。",
        80: "目标名称已存在，未覆盖。",
        183: "目标名称已存在，未覆盖。",
        123: "文件名或路径无效，请检查名称。",
        206: "文件名或路径过长，请缩短名称后重试。",
      }[code];
      if (code) throw Error(reason || `Windows 未能移动文件（错误代码 ${code}）。`);
      throw error;
    }
  } else {
    const s = await fs.lstat(src);
    if (s.isDirectory()) {
      await fs.rename(src, dst);
    } else {
      await fs.link(src, dst);
      await fs.unlink(src);
    }
  }
}
async function moveAcross(src, dst) {
  try {
    await moveExclusive(src, dst);
    return;
  } catch (e) {
    if (await exists(dst)) throw e;
    const a = await fs.stat(src),
      b = await fs.stat(path.dirname(dst));
    if (a.dev === b.dev) throw e;
  }
  // Cross-volume copy: snapshot every entry, create exclusively, validate all sources before removing any.
  const all = [];
  async function walk(p) {
    const e = await entry(p);
    all.push(e);
    if (e.folder)
      for (const name of await fs.readdir(p)) await walk(path.join(p, name));
  }
  await walk(src);
  try {
    for (const e of all) {
      const target = path.join(dst, path.relative(src, e.path));
      if (e.folder) await fs.mkdir(target);
      else
        await fs.copyFile(
          e.path,
          target,
          require("node:fs").constants.COPYFILE_EXCL,
        );
    }
    for (const e of all) await verify(e);
  } catch (e) {
    throw Error(
      "跨磁盘复制未完成，源文件保留。请检查目标目录后重试：" + e.message,
    );
  }
  for (const e of all.reverse()) {
    if (e.folder) {
      if ((await entry(e.path)).identity !== e.identity)
        throw Error("源目录已被替换，未删除。");
      await fs.rmdir(e.path);
    } else {
      await verify(e);
      await fs.unlink(e.path);
    }
  }
}
const split = (s) => [
  ...new Set(
    String(s)
      .split(/[,，、;；\n]/)
      .map((s) => s.trim())
      .filter(Boolean),
  ),
];
const concepts = require("./concepts.json");
function ruleFor(name) {
  let r = {
    keywords: [name],
    excludedKeywords: [],
    extensions: [],
    enabled: true,
    scope: "文件和文件夹",
    priority: 0,
    origin: "automatic",
    generatedFor: name,
  };
  if (!/^(非|不含|排除)/.test(name))
    for (const c of concepts)
      if (c.names.some((n) => norm(name).includes(norm(n)))) {
        r.keywords.push(...c.words);
        r.extensions.push(...c.extensions);
      }
  r.keywords = [...new Set(r.keywords)];
  r.extensions = [...new Set(r.extensions)];
  return r;
}
function termMatch(name, t) {
  t = norm(t);
  if (/^[\x20-\x7f]+$/.test(t)) {
    const esc = t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp("(^|[^a-z0-9])" + esc + "($|[^a-z0-9])", "i").test(
      norm(name),
    );
  }
  return norm(name).includes(t);
}
function categoryFor(e, settings) {
  const cats = settings.categories,
    manual = settings.assignments[e.path];
  if (
    manual?.identity === e.identity &&
    cats.some((c) => c.id === manual.categoryID)
  )
    return manual.categoryID;
  let scores = cats.map((c) => {
    let r = c.rule || ruleFor(c.name);
    if (
      !r.enabled ||
      (r.scope === "仅文件" && e.folder) ||
      (r.scope === "仅文件夹" && !e.folder) ||
      r.excludedKeywords.some((t) => termMatch(e.name, t))
    )
      return [c.id, -1];
    let hits = r.keywords.filter((t) => termMatch(e.name, t));
    return [
      c.id,
      hits.length
        ? r.priority * 1000 +
          200 +
          Math.min(80, Math.max(...hits.map((t) => t.length)))
        : !e.folder &&
            r.extensions.some((x) => norm(e.name).endsWith("." + norm(x)))
          ? r.priority * 1000 + 20
          : -1,
    ];
  });
  let best = Math.max(-1, ...scores.map((x) => x[1])),
    win = scores.filter((x) => x[1] === best);
  return best >= 0 && win.length === 1
    ? win[0][0]
    : (cats.find((c) => c.id === "其他" || c.name === "其他") || cats[0])?.id;
}
function validateRule(r) {
  if (
    !["文件和文件夹", "仅文件", "仅文件夹"].includes(r.scope) ||
    ![0, 1].includes(r.priority) ||
    typeof r.enabled !== "boolean"
  )
    throw Error("规则范围、优先级或启用状态无效。");
  for (const k of ["keywords", "excludedKeywords"])
    if (
      !Array.isArray(r[k]) ||
      r[k].length > 80 ||
      r[k].some(
        (x) =>
          typeof x !== "string" || !x || x.length > 80 || /[\x00-\x1f]/.test(x),
      )
    )
      throw Error("每项最多80个关键词，每词最多80字。");
  if (
    !Array.isArray(r.extensions) ||
    r.extensions.length > 40 ||
    r.extensions.some((x) => !/^[a-z0-9][a-z0-9.-]{0,19}$/.test(x))
  )
    throw Error("扩展名格式无效。");
  if (r.enabled && !r.keywords.length && !r.extensions.length)
    throw Error("请至少填写一个关键词或扩展名。");
  return r;
}
function parseRules(text, cats) {
  if (Buffer.byteLength(text) > 131072) throw Error("规则正文超过128KB。");
  let lines = text
    .trim()
    .replace(/^```(?:text|plaintext)?\s*\n([\s\S]*?)\n```$/, "$1")
    .split(/\r?\n/)
    .map((x) => x.trim())
    .filter(Boolean);
  if (!/^归屿规则[：:]\s*1$/.test(lines.shift()))
    throw Error("首行必须是“归屿规则：1”。");
  let targets = cats.filter((c) => c.id !== "其他"),
    result = new Map();
  if (!lines.length || lines.length % 6)
    throw Error("每类必须包含完整的六行规则。");
  for (let i = 0; i < lines.length; i += 6) {
    let vals = ["分类", "关键词", "排除词", "扩展名", "范围", "优先级"].map(
      (k, j) => {
        let m = lines[i + j].match(/^([^：:]+)[：:]\s*(.+)$/);
        if (!m || m[1] !== k) throw Error("规则字段或顺序错误：" + k);
        return m[2];
      },
    );
    let c = targets.find((c) => c.name === vals[0]);
    if (!c || result.has(c.id)) throw Error("存在未知或重复分类：" + vals[0]);
    if (!["普通", "优先"].includes(vals[5]))
      throw Error("优先级只能是普通或优先。");
    let terms = (v) => (v === "无" ? [] : split(v));
    result.set(
      c.id,
      validateRule({
        ...c.rule,
        keywords: terms(vals[1]),
        excludedKeywords: terms(vals[2]),
        extensions: terms(vals[3]).map((x) =>
          x.replace(/^\./, "").toLowerCase(),
        ),
        scope: vals[4],
        priority: vals[5] === "优先" ? 1 : 0,
        enabled: c.rule?.enabled ?? true,
        origin: "edited",
      }),
    );
  }
  if (result.size !== targets.length)
    throw Error("回复缺少分类，请复制完整内容。");
  return cats.map((c) =>
    result.has(c.id) ? { ...c, rule: result.get(c.id) } : c,
  );
}
function smartCategory(e, s, recognizedName = "") {
  const ext = e.folder ? "" : path.extname(e.name);
  const original = namingFormat.literalStem(e.name, ext);
  const title = namingFormat.literalStem(recognizedName, ext);
  const row = title.trim()
    ? { ...e, name: [...new Set([original, title])].join(" ") + ext }
    : e;
  return s.categories.find((c) => c.id === categoryFor(row, s))?.name || "其他";
}
function prefixFor(e, s, now = Date.now(), recognizedName = "") {
  const rules = namingFormat.settings(s.namingRules);
  const date = new Date(
    rules.dateSource === "created" ? e.created || now : now,
  );
  let parts = Object.fromEntries(
    new Intl.DateTimeFormat("en", {
      timeZone: "Asia/Shanghai",
      month: "2-digit",
      day: "2-digit",
    })
      .formatToParts(date)
      .map((x) => [x.type, x.value]),
  );
  const format = e.folder ? rules.folder : rules.document;
  const category =
    namingFormat.cleanTitle(smartCategory(e, s, recognizedName)) || "其他";
  let month = Number(parts.month);
  if (e.folder && rules.dateSource === "created")
    month = Number(e.name.match(/^(1[0-2]|[1-9])月/)?.[1] || month);
  return {
    prefix:
      format === "nameOnly"
        ? ""
        : format === "month"
          ? month + "月"
          : format === "monthDay"
            ? parts.month + parts.day
            : category,
    format,
    category,
  };
}
function formatSuggestion(e, settings, base, referenceDate = Date.now()) {
  const format = prefixFor(e, settings, referenceDate, base);
  const ext = e.folder ? "" : path.extname(e.name);
  const name = namingFormat.cleanTitle(namingFormat.literalStem(base, ext));
  const proposedStem = [format.prefix, name].filter(Boolean).join(" ");
  return {
    name,
    ...format,
    editableName: ["nameOnly", "category"].includes(format.format)
      ? proposedStem
      : name,
    proposedName: proposedStem + ext,
  };
}
class Store {
  constructor(stateDir) {
    this.stateDir = stateDir;
    this.file = path.join(stateDir, "settings.json");
    this.settings = {
      roots: [],
      sources: [],
      categories: [],
      assignments: {},
      moves: [],
      renames: [],
      directoryOrders: {},
      sidebarFraction: 0.62,
      widths: [240, 390],
      namingRules: namingFormat.settings(),
    };
    this.snapshot = {
      rootEntries: [],
      rootFiles: [],
      directories: [],
      projects: [],
      files: [],
      unavailable: [],
    };
  }
  async init(defaultSources = []) {
    await fs.mkdir(this.stateDir, { recursive: true });
    try {
      this.settings = {
        ...this.settings,
        ...JSON.parse(await fs.readFile(this.file, "utf8")),
      };
      this.settings.namingRules = namingFormat.settings(
        this.settings.namingRules,
      );
    } catch (e) {
      if (e.code !== "ENOENT")
        throw Error("配置文件无法读取，已停止以防覆盖：" + e.message);
      this.settings.sources = defaultSources;
    }
    // Resolve explicitly linked locations once, including redirected Windows
    // Desktop/Downloads paths; missing links remain visible in settings.
    this.settings.roots = await Promise.all(this.settings.roots.map(async p => fs.realpath(p).catch(() => p)));
    this.settings.sources = await Promise.all(this.settings.sources.map(async s => s.path ?
      { ...s, path: await fs.realpath(s.path).catch(() => s.path) } : s));
    return this;
  }
  async save(next) {
    const tmp = this.file + "." + crypto.randomUUID() + ".tmp";
    await fs.writeFile(tmp, JSON.stringify(next, null, 2));
    await fs.rename(tmp, this.file);
    this.settings = next;
    return next;
  }
  async refresh() {
    const snapshot = {
      rootEntries: [],
      rootFiles: [],
      directories: [],
      projects: [],
      files: [],
      unavailable: [],
    };
    for (const root of this.settings.roots) {
      try {
        const rootEntries = await list(root);
        snapshot.rootEntries.push(...rootEntries.map(e => ({ ...e, directory: root })));
        const dirs = rootEntries.filter((e) => e.folder);
        const order = this.settings.directoryOrders[root] || [];
        dirs.sort(
          (a, b) =>
            (order.indexOf(a.path) < 0 ? 9999 : order.indexOf(a.path)) -
              (order.indexOf(b.path) < 0 ? 9999 : order.indexOf(b.path)) ||
            a.name.localeCompare(b.name, "zh"),
        );
        for (const dir of dirs) {
          snapshot.directories.push({ ...dir, root });
          try {
            const projects = await list(dir.path);
            snapshot.rootFiles.push(...projects.map(e => ({ ...e,
              project: dir.path, projectName: dir.name, directory: root })));
            snapshot.projects.push(
              ...projects.map((e) => ({ ...e, directory: dir.path })),
            );
            for (const p of projects.filter((x) => x.folder)) {
              try {
                snapshot.files.push(
                  ...(await list(p.path)).map((e) => ({
                    ...e,
                    project: p.path,
                    projectName: p.name,
                    directory: dir.path,
                  })),
                );
              } catch {
                snapshot.unavailable.push(p.path);
              }
            }
          } catch {
            snapshot.unavailable.push(dir.path);
          }
        }
      } catch {
        snapshot.unavailable.push(root);
      }
    }
    this.snapshot = snapshot;
    return snapshot;
  }
  allowed(p) {
    return (
      this.settings.roots.some((r) => inside(p, r) && key(p) !== key(r)) ||
      this.settings.sources.some(
        (s) => s.path && inside(p, s.path) && key(p) !== key(s.path),
      ) ||
      this.recentAllowed?.has(key(p)) ||
      this.recentBrowseRoots?.some((r) => inside(p, r)) ||
      this.externalAllowed?.has(key(p))
    );
  }
  async guard(p) {
    if (typeof p !== "string" || !this.allowed(p))
      throw Error("文件不在当前关联目录范围内。");
    const real = await fs.realpath(p);
    if (key(real) !== key(p)) throw Error("目录联接或链接目标不在允许范围。");
    return entry(p);
  }
  async browse(p) {
    if (typeof p !== "string" || !(this.allowed(p) ||
        this.settings.roots.some(root => key(root) === key(p)) ||
        this.settings.sources.some(s => s.path && key(s.path) === key(p))))
      throw Error("文件夹不在当前关联目录范围内。");
    const real = await fs.realpath(p);
    if (key(real) !== key(p)) throw Error("目录联接或链接目标不在允许范围。");
    const folder = await entry(p);
    if (!folder.folder) throw Error("请选择文件夹。");
    return folder;
  }
  async addRoots(roots) {
    const next = structuredClone(this.settings);
    for (const root of roots) {
      const p = await fs.realpath(root);
      if (!(await entry(p)).folder) throw Error("请选择文件夹。");
      if (next.roots.some((r) => key(r) === key(p))) continue;
      if (
        p === path.parse(p).root ||
        next.roots.some((r) => overlap(r, p))
      )
        throw Error("项目总目录不能相互嵌套。");
      await fs.readdir(p);
      next.roots.push(p);
    }
    await this.save(next);
    return this.refresh();
  }
  async addSources(paths) {
    const next = structuredClone(this.settings);
    for (const p of paths) {
      const real = await fs.realpath(p), folder = await entry(real);
      if (!folder.folder) throw Error("请选择文件夹。");
      if (!next.sources.some(s => s.path && key(s.path) === key(real)))
        next.sources.push({ id: crypto.randomUUID(), name: folder.name || real, path: real, kind: "folder" });
    }
    await this.save(next);
  }
  async assign(items, id) {
    if (!this.settings.categories.some((c) => c.id === id))
      throw Error("分类不存在。");
    const next = structuredClone(this.settings);
    for (const e of items) {
      await this.guard(e.path);
      await verify(e);
      next.assignments[e.path] = { categoryID: id, identity: e.identity };
    }
    await this.save(next);
  }
  remap(next, src, dst, moves = true) {
    for (const source of next.sources) if (source.path && inside(source.path, src)) {
      if (key(source.path) === key(src) && source.name === path.basename(src)) source.name = path.basename(dst);
      source.path = path.join(dst, path.relative(src, source.path));
    }
    for (const paths of Object.values(next.directoryOrders))
      for (let i = 0; i < paths.length; i++) if (inside(paths[i], src))
        paths[i] = path.join(dst, path.relative(src, paths[i]));
    for (const [p, a] of Object.entries(next.assignments))
      if (inside(p, src)) {
        delete next.assignments[p];
        next.assignments[path.join(dst, path.relative(src, p))] = a;
      }
    for (const m of moves ? next.moves : []) {
      if (inside(m.destination, src))
        m.destination = path.join(dst, path.relative(src, m.destination));
    }
  }
  async rename(plans) {
    if (!plans.length) throw Error("没有勾选需要命名的条目。");
    const targets = new Set();
    for (const { entry: e, name, smart } of plans) {
      if (smart)
        namingFormat.validatePrefix(
          name,
          e.folder
            ? this.settings.namingRules.folder
            : this.settings.namingRules.document,
        );
      await this.guard(e.path);
      await verify(e);
      validateName(name);
      if (this.settings.roots.some(root => key(root) === key(e.path)))
        throw Error("关联的项目总目录本身不能重命名。");
      if (
        !e.folder &&
        path.extname(name).toLowerCase() !== path.extname(e.name).toLowerCase()
      )
        throw Error("文档必须保留原扩展名。");
      let dst = path.join(path.dirname(e.path), name);
      if (plans.some((p) => p.entry !== e && inside(e.path, p.entry.path)))
        throw Error("不能同时重命名父目录与其子项。");
      if (
        targets.has(key(dst)) ||
        (key(dst) !== key(e.path) && (await exists(dst)))
      )
        throw Error("目标名称重复：" + name);
      targets.add(key(dst));
    }
    let completed = 0;
    try {
      for (const { entry: e, name } of plans) {
        const dst = path.join(path.dirname(e.path), name);
        if (dst === e.path) continue;
        if (key(dst) === key(e.path))
          throw Error("仅更改大小写请先更改为临时名称。");
        await verify(e);
        await moveExclusive(e.path, dst);
        if (this.externalAllowed?.has(key(e.path))) {
          this.externalAllowed.delete(key(e.path));
          this.externalAllowed.add(key(dst));
        }
        const next = structuredClone(this.settings);
        this.remap(next, e.path, dst);
        next.renames.push({
          source: e.path,
          destination: dst,
          date: new Date().toISOString(),
        });
        completed++;
        await this.save(next);
      }
    } catch (e) {
      throw Error(`已完成 ${completed} 项，剩余项已停止：${e.message}`);
    }
    return completed;
  }
  async archive(items, destination) {
    if (
      ![...this.snapshot.rootEntries, ...this.snapshot.projects].some(
        (p) => p.folder && key(p.path) === key(destination),
      )
    )
      throw Error("请选择当前项目列表中的目标。");
    await this.guard(destination);
    for (const e of items) {
      if (this.settings.roots.some(root => key(root) === key(e.path)))
        throw Error("关联的项目总目录本身不能归档。");
      await this.guard(e.path);
      await verify(e);
      if (
        inside(destination, e.path) ||
        items.some((o) => o !== e && inside(e.path, o.path))
      )
        throw Error("不能归档到自身，或同时选择父子项。");
    }
    let completed = 0;
    try {
      for (const e of items) {
        await verify(e);
        const ext = e.folder ? "" : path.extname(e.name),
          stem = e.folder ? e.name : path.basename(e.name, ext);
        let dst = path.join(destination, e.name),
          i = 2;
        while (await exists(dst))
          dst = path.join(destination, `${stem} (${i++})${ext}`);
        await moveAcross(e.path, dst);
        const arrived = await entry(dst),
          next = structuredClone(this.settings);
        this.remap(next, e.path, dst);
        if (next.assignments[dst])
          next.assignments[dst].identity = arrived.identity;
        next.moves.unshift({
          id: crypto.randomUUID(),
          source: e.path,
          destination: dst,
          identity: arrived.identity,
          version: arrived.version,
          date: new Date().toISOString(),
          undone: false,
        });
        completed++;
        await this.save(next);
      }
    } catch (e) {
      throw Error(
        `已归档 ${completed} 项，剩余项已停止；请关闭窗口重新选择未完成条目。${e.message}`,
      );
    }
    return completed;
  }
  async undo(id) {
    const m = this.settings.moves.find((m) => m.id === id && !m.undone);
    if (!m) throw Error("记录不存在或已经撤销。");
    const e = await this.guard(m.destination);
    if (e.identity !== m.identity) throw Error("归档文件已被替换，不能撤销。");
    if (await exists(m.source)) throw Error("原位置已被占用，未覆盖。");
    await fs.access(path.dirname(m.source));
    await moveAcross(m.destination, m.source);
    const next = structuredClone(this.settings);
    this.remap(next, m.destination, m.source, false);
    const restored = await entry(m.source);
    if (next.assignments[m.source])
      next.assignments[m.source].identity = restored.identity;
    next.moves.find((x) => x.id === id).undone = true;
    await this.save(next);
  }
}
module.exports = {
  Store,
  norm,
  matches,
  inside,
  overlap,
  list,
  entry,
  verify,
  validateName,
  ruleFor,
  validateRule,
  parseRules,
  categoryFor,
  prefixFor,
  smartCategory,
  formatSuggestion,
  runPS,
  split,
  exists,
};
