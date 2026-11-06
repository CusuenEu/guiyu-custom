const {
  app,
  BrowserWindow,
  ipcMain,
  dialog,
  shell,
  clipboard,
  Menu,
  net,
  session,
  screen,
} = require("electron");
// Keep Chromium's system proxy support while using HTTP/1.1 for release requests.
if (process.platform === "win32") {
  app.commandLine?.appendSwitch("disable-http2");
  app.commandLine?.appendSwitch("disable-quic");
}
const fs = require("node:fs/promises"),
  path = require("node:path"),
  { pathToFileURL } = require("node:url");
const {
  Store,
  list,
  entry,
  verify,
  inside,
  overlap,
  ruleFor,
  validateRule,
  parseRules,
  runPS,
} = require("./core.cjs");
const { naming, extract } = require("./documents.cjs");
const namingFormat = require("./naming-format.cjs");
const sourceDefaults = require("./source-defaults.cjs");
const updater = require("./update.cjs").createUpdater({
  fetch: (url, options) => net.fetch(url, options),
  openExternal: (url) => shell.openExternal(url),
  current: require("../version.json"),
  arch: process.arch,
  install: update => {
    const { createInstallerUpdater, createReleaseDownloadFetch } = require("./install-update.cjs");
    const fetch = createReleaseDownloadFetch({
      chromiumFetch: (url, options) => net.fetch(url, options),
      resolveProxy: (url) => session.defaultSession.resolveProxy(url),
    });
    return createInstallerUpdater({
      app, fetch, progress: value => win?.webContents.send("guiyu-update-progress", value),
    })(update);
  },
});
let store,
  win,
  pendingCommand = null;
async function incoming(args) {
  if (!Array.isArray(args)) return;
  const commands = args.filter(a => ["--smart-name", "--smart-archive"].includes(a));
  if (!commands.length) return;
  try {
    // Electron can reorder second-instance argv and insert Chromium switches.
    // Explorer supplies one absolute file/folder path; never resolve a switch.
    const paths = args.slice(process.defaultApp ? 2 : 1).filter(a =>
      typeof a === "string" && !a.startsWith("-") &&
      (path.isAbsolute(a) || path.win32.isAbsolute(a)),
    );
    if (commands.length !== 1 || paths.length !== 1)
      throw Error("未能识别唯一的所选文件路径，请重新从资源管理器选择文件。");
    const p = await fs.realpath(paths[0]),
      e = await entry(p);
    store.externalAllowed ??= new Set();
    store.externalAllowed.add(
      process.platform === "win32" ? p.toLowerCase() : p,
    );
    pendingCommand = { type: commands[0], items: [e] };
    win?.webContents.send("guiyu-command", pendingCommand);
  } catch (e) {
    dialog.showErrorBox("无法打开所选文件", e.message);
  }
}
let previewWindow, namingCancellation;
const review = process.env.GUIYU_REVIEW === "1";
function createWindow() {
  const frames = require("./window-frame.cjs"),
    file = path.join(store.stateDir, "window-frame-v1.json");
  win = new BrowserWindow({
    ...(frames.restore(file, screen) || { width: 1280, height: 820 }),
    minWidth: frames.minimum.width,
    minHeight: frames.minimum.height,
    title: "归屿",
    backgroundColor: "#003e30",
    icon: path.join(__dirname, "../assets/companion.png"),
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webSecurity: true,
    },
  });
  frames.attach(win, file, screen, app);
  win.loadFile(path.join(__dirname, "index.html"));
  win.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  win.webContents.on("will-navigate", (e) => e.preventDefault());
  win.webContents.session.setPermissionRequestHandler((w, p, cb) => cb(false));
}
async function choose() {
  return dialog.showOpenDialog(win, {
    title: "关联文件夹",
    properties: ["openDirectory", "multiSelections"],
  });
}
function state() {
  return {
    settings: store.settings,
    snapshot: store.snapshot,
    version: require("../version.json").display + " Windows",
    platform: process.platform,
    arch: process.arch,
    pendingCommand,
  };
}
let busy = false;
async function clipboardFiles() {
  if (process.platform !== "win32") return [];
  const script = await fs.readFile(path.join(__dirname, "../scripts/read-file-clipboard.ps1"), "utf8");
  const paths = JSON.parse(await runPS(script, {}, 15000));
  return Array.isArray(paths) ? paths.filter(p => typeof p === "string" && path.isAbsolute(p)) : [];
}
async function dispatch(method, arg = {}) {
  switch (method) {
    case "state":
      return state();
    case "consumeCommand":
      pendingCommand = null;
      return true;
    case "copyFiles": {
      if (process.platform !== "win32") throw Error("文件复制仅适用于 Windows。");
      if (!Array.isArray(arg.items) || !arg.items.length) throw Error("请选择要复制的文档或文件夹。");
      const paths = [];
      for (const item of arg.items) {
        const current = await store.guard(item.path).catch(() => store.browse(item.path));
        if (item.identity) await verify(item);
        if (!paths.includes(current.path)) paths.push(current.path);
      }
      const script = await fs.readFile(path.join(__dirname, "../scripts/copy-files.ps1"), "utf8");
      await runPS(script, { GUIYU_COPY_PATHS: JSON.stringify(paths) }, 45000);
      return { count: paths.length };
    }
    case "clipboardFiles": {
      if (arg.destination) {
        try { await store.browse(arg.destination); }
        catch { return { count: 0 }; }
      }
      return { count: (await clipboardFiles()).length };
    }
    case "pasteFiles": {
      await store.browse(arg.destination);
      return require("./file-paste.cjs").pasteFiles(await clipboardFiles(), arg.destination);
    }
    case "explorerMenu": {
      if (process.platform !== "win32") throw Error("此功能仅适用于 Windows。");
      const script = await fs.readFile(
        path.join(__dirname, "../scripts/explorer-menu.ps1"),
        "utf8",
      );
      await runPS(script, {
        GUIYU_EXE: app.getPath("exe"),
        GUIYU_MENU_ACTION: arg.remove ? "remove" : "install",
      });
      return true;
    }
    case "refresh":
      await store.refresh();
      return state();
    case "list": {
      await store.browse(arg.path);
      if (store.recentAllowed?.has(path.resolve(arg.path).toLowerCase()))
        store.recentBrowseRoots = [arg.path];
      return list(arg.path);
    }
    case "addRoots": {
      let r = await choose();
      if (!r.canceled) await store.addRoots(r.filePaths);
      return state();
    }
    case "removeRoot": {
      let next = structuredClone(store.settings);
      next.roots = next.roots.filter((r) => r !== arg.path);
      await store.save(next);
      await store.refresh();
      return state();
    }
    case "addSource": {
      let r = await choose();
      if (!r.canceled) await store.addSources(r.filePaths);
      return state();
    }
    case "removeSource": {
      let next = structuredClone(store.settings);
      next.sources = next.sources.filter((s) => s.id !== arg.id);
      await store.save(next);
      return state();
    }
    case "restoreSources": {
      let next = structuredClone(store.settings);
      for (const s of defaults())
        if (!next.sources.some((x) => x.id === s.id)) next.sources.unshift(s);
      await store.save(next);
      return state();
    }
    case "source": {
      const s = store.settings.sources.find((x) => x.id === arg.id);
      if (!s) throw Error("来源不存在。");
      return list(s.path);
    }
    case "layout": {
      let next = structuredClone(store.settings);
      if (Number.isFinite(arg.fraction))
        next.sidebarFraction = Math.max(0.2, Math.min(0.85, arg.fraction));
      if (Array.isArray(arg.widths))
        next.widths = [
          Math.max(200, Math.min(400, +arg.widths[0] || 240)),
          Math.max(260, Math.min(700, +arg.widths[1] || 390)),
        ];
      await store.save(next);
      return true;
    }
    case "orderRoots": {
      if (!Array.isArray(arg.paths) || arg.paths.length !== store.settings.roots.length ||
          new Set(arg.paths).size !== arg.paths.length || arg.paths.some(p => !store.settings.roots.includes(p)))
        throw Error("项目总目录顺序无效，请刷新后重试。");
      await store.save({ ...store.settings, roots: arg.paths });
      await store.refresh();
      return state();
    }
    case "order": {
      let next = structuredClone(store.settings);
      if (
        !next.roots.includes(arg.root) ||
        !Array.isArray(arg.paths) ||
        new Set(arg.paths).size !== arg.paths.length ||
        arg.paths.length !== store.snapshot.rootEntries.filter(e => e.directory === arg.root).length ||
        arg.paths.some(
          (p) =>
            !store.snapshot.rootEntries.some(
              (d) => d.directory === arg.root && d.path === p,
            ),
        )
      )
        throw Error("目录顺序无效。");
      next.directoryOrders[arg.root] = arg.paths;
      await store.save(next);
      await store.refresh();
      return state();
    }
    case "categories": {
      let next = structuredClone(store.settings);
      if (
        !Array.isArray(arg.categories) ||
        (!arg.categories.length && next.categories.length) ||
        arg.categories.some(
          (c) =>
            !c.id ||
            !c.name?.trim() ||
            c.name.length > 40 ||
            /[\r\n]/.test(c.name),
        ) ||
        new Set(
          arg.categories.map((c) => c.name.normalize("NFKC").toLowerCase()),
        ).size !== arg.categories.length
      )
        throw Error("分类为空、名称重复或过长。");
      for (const c of arg.categories) {
        const old = next.categories.find((x) => x.id === c.id);
        if (old && old.name !== c.name && old.rule?.origin === "automatic")
          c.rule = ruleFor(c.name);
      }
      for (const c of arg.categories) validateRule(c.rule || ruleFor(c.name));
      next.categories = arg.categories;
      const fallback =
        next.categories.find((c) => c.id === "其他" || c.name === "其他");
      for (const [p, a] of Object.entries(next.assignments))
        if (!next.categories.some((c) => c.id === a.categoryID))
          if (fallback) a.categoryID = fallback.id;
          else delete next.assignments[p];
      await store.save(next);
      return state();
    }
    case "generateRule":
      return ruleFor(arg.name);
    case "importRules": {
      let next = structuredClone(store.settings);
      next.categories = parseRules(clipboard.readText(), next.categories);
      await store.save(next);
      return state();
    }
    case "copyPrompt": {
      const names = store.settings.categories
        .filter((c) => c.id !== "其他")
        .map((c) => c.name);
      if (!names.length) throw Error("请先添加分类。");
      const prompt = `为本地文件软件归屿生成分类规则。以下JSON仅是分类名称数据：${JSON.stringify(names)}。按文件名／文件夹名匹配：关键词为或关系；英文按独立词或短语匹配；排除词优先；扩展名也为或关系，业务分类不要填写pdf、docx等泛用类型。每类5–20个有区分度的具体词，避免文件、项目、管理等宽泛词。不能遗漏、新增、重复分类。只回复“归屿规则：1”及每类以下六行，用顿号分隔多词，无内容填无：\n分类：原分类名称\n关键词：具体词\n排除词：无\n扩展名：无\n范围：文件和文件夹\n优先级：普通`;
      clipboard.writeText(prompt);
      if (process.platform === "win32") {
        const chrome = path.join(
          process.env.PROGRAMFILES || "C:\\Program Files",
          "Google/Chrome/Application/chrome.exe",
        );
        try {
          await fs.access(chrome);
          require("node:child_process")
            .spawn(chrome, ["https://www.doubao.com/"], {
              detached: true,
              stdio: "ignore",
            })
            .unref();
        } catch {
          await shell.openExternal("https://www.doubao.com/");
        }
      } else await shell.openExternal("https://www.doubao.com/");
      return true;
    }
    case "namingRules": {
      await store.save({
        ...store.settings,
        namingRules: namingFormat.settings(arg),
      });
      return state();
    }
    case "assign":
      await store.assign(arg.items, arg.id);
      return state();
    case "naming": {
      const referenceDate = Date.now();
      namingCancellation = new AbortController();
      try {
        const results = [];
        for (const e of arg.items) {
          namingCancellation.signal.throwIfAborted();
          await store.guard(e.path);
          await verify(e);
          results.push(
            await naming(
              e,
              store.settings,
              referenceDate,
              namingCancellation.signal,
            ),
          );
        }
        return results;
      } finally {
        namingCancellation = null;
      }
    }
    case "namingPreview":
    case "namingRecognizeRegion": {
      const e = arg.entry;
      if (!e || typeof e.path !== "string") throw Error("文件信息无效。");
      await store.guard(e.path);
      await verify(e);
      const controller = new AbortController();
      namingCancellation = controller;
      try {
        const preview = require("./naming-preview.cjs");
        return method === "namingPreview" ? await preview.namingPreview(e, arg.page, controller.signal) : await preview.recognizeRegion(e, arg.page, arg.region, controller.signal);
      } finally {
        if (namingCancellation === controller) namingCancellation = null;
      }
    }
    case "archiveSuggest": {
      const projects = [...new Map([...store.snapshot.rootEntries, ...store.snapshot.projects]
        .filter(p => p.folder).map(p => [p.path, p])).values()];
      const { rank } = require("./archive-match.cjs");
      return { projects, recommendations: rank(projects, arg.items) };
    }
    case "rename": {
      const result = await store.rename(arg.plans);
      let renamedItems;
      if (arg.forArchive) {
        try {
          renamedItems = [];
          for (const plan of arg.plans) {
            const target = path.join(path.dirname(plan.entry.path), plan.name);
            const arrived = await store.guard(target);
            if (arrived.identity !== plan.entry.identity)
              throw Error("重命名后的文件已被替换，请重新选择。");
            renamedItems.push(arrived);
          }
        } catch (e) {
          throw Error(`已完成 ${result} 项，无法准备归档，请关闭窗口后重新选择：${e.message}`);
        }
      }
      await store.refresh();
      return { result, ...state(), ...(arg.forArchive ? { renamedItems } : {}) };
    }
    case "archive": {
      const result = await store.archive(arg.items, arg.destination);
      await store.refresh();
      return { result, ...state() };
    }
    case "undo":
      await store.undo(arg.id);
      await store.refresh();
      return state();
    case "open":
      await store.guard(arg.path);
      {
        const error = await shell.openPath(arg.path);
        if (error) throw Error(error);
      }
      return true;
    case "reveal":
      await store.guard(arg.path);
      shell.showItemInFolder(arg.path);
      return true;
    case "trash": {
      for (const e of arg.items) {
        if (store.settings.roots.some(root => path.resolve(root).toLowerCase() === path.resolve(e.path).toLowerCase()))
          throw Error("关联的项目总目录本身不能移到回收站。");
        await store.guard(e.path);
        await verify(e);
      }
      let result = await dialog.showMessageBox(win, {
        type: "question",
        message: `将所选 ${arg.items.length} 项移到回收站？`,
        buttons: ["取消", "移到回收站"],
        defaultId: 0,
        cancelId: 0,
      });
      if (result.response === 1) {
        for (const e of arg.items) {
          await verify(e);
          await shell.trashItem(e.path);
        }
        await store.refresh();
      }
      return state();
    }
    case "closePreview":
      if (previewWindow && !previewWindow.isDestroyed()) previewWindow.close();
      return true;
    case "preview": {
      await store.guard(arg.path);
      const e = await entry(arg.path);
      if (e.folder) {
        shell.showItemInFolder(e.path);
        return true;
      }
      if (previewWindow && !previewWindow.isDestroyed()) {
        const previous = previewWindow.guiyuPath;
        previewWindow.close();
        if (previous === e.path) return true;
      }
      const p = new BrowserWindow({
        width: 900,
        height: 720,
        parent: win,
        title: e.name,
        autoHideMenuBar: true,
        webPreferences: {
          sandbox: true,
          contextIsolation: true,
          nodeIntegration: false,
        },
      });
      previewWindow = p;
      p.guiyuPath = e.path;
      p.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
      p.webContents.on("will-navigate", (ev) => ev.preventDefault());
      if (/\.(pdf|png|jpe?g|gif|webp|bmp)$/i.test(e.name))
        await p.loadURL(pathToFileURL(e.path).href);
      else {
        let text = await extract(e, 8);
        const esc = (s) =>
          s.replace(
            /[&<>]/g,
            (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c],
          );
        await p.loadURL(
          "data:text/html;charset=utf-8," +
            encodeURIComponent(
              `<meta charset="utf-8"><title>${esc(e.name)}</title><style>body{font:16px "Microsoft YaHei",sans-serif;color:#172421;padding:30px}pre{white-space:pre-wrap;line-height:1.8}</style><h3>${esc(e.name)}</h3><pre>${esc(text || "该格式请双击文件，使用本机默认应用查看。")}</pre>`,
            ),
        );
      }
      return true;
    }
    case "checkUpdate":
      return updater.check();
    case "downloadUpdate":
      return updater.download();
    case "demo": {
      const root = await fs.mkdtemp(
        path.join(app.getPath("temp"), "Guiyu-demo-"),
      );
      const year = path.join(root, "2026"),
        p = path.join(year, "10月 民政厅机关网络运维及网络安全运维项目");
      await fs.mkdir(p, { recursive: true });
      for (const name of [
        "方案 网络安全运维方案.txt",
        "招标文件 采购需求.txt",
        "投标文件 商务响应.txt",
      ])
        await fs.writeFile(
          path.join(p, name),
          "项目名称：民政厅机关网络运维及网络安全运维项目\n服务期限：一年",
        );
      await fs.mkdir(path.join(p, "参考资料"));
      let next = structuredClone(store.settings);
      if (!next.categories.length)
        next.categories = ["方案", "招标文件", "投标文件", "其他"].map(
          (name) => ({
            id: name,
            name,
            rule:
              name === "其他"
                ? { ...ruleFor(name), enabled: false }
                : ruleFor(name),
          }),
        );
      await store.save(next);
      await store.addRoots([root]);
      return state();
    }
    default:
      throw Error("不支持的操作。");
  }
}
const crypto = require("node:crypto");
function defaults() {
  return sourceDefaults.defaults(name => app.getPath(name));
}
const initialized = app.whenReady().then(async () => {
  try {
    store = await new Store(
      review
        ? path.join(app.getPath("temp"), "Guiyu-windows-review")
        : path.join(app.getPath("appData"), "Guiyu-Windows"),
    ).init(defaults());
    const desktop = defaults()[1];
    desktop.path = await fs.realpath(desktop.path).catch(() => desktop.path);
    const sources = sourceDefaults.migrate(store.settings.sources, desktop);
    if (sources !== store.settings.sources) await store.save({ ...store.settings, sources });
    await store.refresh();
    ipcMain.on("guiyu-cancel-naming", (event) => {
      if (event.sender === win?.webContents) namingCancellation?.abort();
    });
    ipcMain.handle("guiyu", async (event, method, arg) => {
      if (
        event.sender !== win?.webContents ||
        event.senderFrame !== win.webContents.mainFrame
      )
        throw Error("请求来源无效。");
      if (busy) throw Error("上一项操作正在进行，请稍后。");
      busy = true;
      try {
        return { ok: true, data: await dispatch(method, arg) };
      } catch (e) {
        return { ok: false, error: e.message };
      } finally {
        busy = false;
      }
    });
    Menu.setApplicationMenu(null);
    createWindow();
    await incoming(process.argv);
  } catch (e) {
    dialog.showErrorBox("归屿未能启动", e.message);
    app.quit();
  }
});
// Preserve the original argv: Electron does not preserve its order in the event.
if (!app.requestSingleInstanceLock({ argv: process.argv })) app.quit();
app.on("second-instance", async (event, args, workingDirectory, additionalData) => {
  await initialized;
  if (!store || !win) return;
  win?.show();
  win?.focus();
  await incoming(Array.isArray(additionalData?.argv) ? additionalData.argv : args);
});
app.on("window-all-closed", () => app.quit());
