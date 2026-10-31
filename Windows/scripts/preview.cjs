// Isolated, in-memory visual fixtures. Never reads or writes user project folders.
const http = require("node:http"),
  fs = require("node:fs/promises"),
  path = require("node:path");
const { ruleFor } = require("../src/core.cjs");
const root = path.resolve(__dirname, ".."),
  base = "C:\\GuiyuDemo",
  directory = base + "\\2026";
const names = [
  "10月 民政厅机关网络运维及网络安全运维项目",
  "9月 企业数字化转型诊断",
  "8月 贵州黔程慧通科技发展有限责任公司网络安全升级建设项目",
  "7月 中共贵州省委组织部2026年度运维项目采购公告",
  "7月 贵州省自然资源厅2026年贵州省政务信息化运维项目",
  "6月 地震大数据贵州中心非通用办公设备、资产采购",
];
const make = (name, parent, folder = true) => ({
  path: parent + "\\" + name,
  name,
  folder,
  mtime: 1793376000000,
  created: 1793376000000,
  identity: "fixture:" + name,
  version: "1",
});
let projects = names.map((name) => ({ ...make(name, directory), directory })),
  files = [
    "民政厅网络运维服务方案.docx",
    "网络安全保障方案.pdf",
    "民政厅机关网络运维采购文件.pdf",
    "采购需求与技术规范.docx",
    "投标文件-民政厅网络安全运维项目.docx",
    "分项报价表.xlsx",
    "参考资料",
  ].map((name, i) => ({
    ...make(name, projects[0].path, i === 6),
    project: projects[0].path,
    projectName: projects[0].name,
    directory,
  }));
let settings = {
  roots: [base],
  sources: [
    { id: "downloads", name: "下载", path: "C:\\Downloads", kind: "folder" },
    { id: "recent", name: "最近使用", kind: "recent" },
  ],
  categories: ["方案", "招标文件", "投标文件", "其他"].map((name) => ({
    id: name,
    name,
    rule:
      name === "其他" ? { ...ruleFor(name), enabled: false } : ruleFor(name),
  })),
  assignments: {},
  moves: [],
  directoryOrders: {},
  sidebarFraction: 0.62,
  widths: [240, 390],
  namingRules: { folder: "month", document: "category", dateSource: "today" },
};
const state = () => ({
  version: "20261031(02) Windows 测试版",
  platform: "win32",
  arch: "x64",
  settings,
  snapshot: {
    directories: [
      { ...make("2026", base), root: base },
      { ...make("2025", base), root: base },
    ],
    projects,
    files,
    unavailable: [],
  },
});
const server = http.createServer(async (req, res) => {
  try {
    if (req.url === "/fixture-api") {
      let input = "";
      for await (const c of req) input += c;
      const { method, arg } = JSON.parse(input);
      let result;
      switch (method) {
        case "state":
        case "refresh":
          result = state();
          break;
        case "list":
          if (process.env.GUIYU_PREVIEW_SLOW_LIST === "1") await new Promise((resolve) => setTimeout(resolve, 400));
          result = arg.path === "C:\\Downloads\\示例文件夹"
            ? [make("示例文档.txt", arg.path, false), make("子文件夹", arg.path)]
            : arg.path === "C:\\Downloads\\第二个文件夹"
              ? [make("另一个文件.txt", arg.path, false)]
            : arg.path === "C:\\Downloads\\示例文件夹\\子文件夹"
              ? [make("子目录文件.txt", arg.path, false)]
              : files.filter((e) => e.project === arg.path);
          break;
        case "source":
          result = process.env.GUIYU_PREVIEW_MANY_FILES === "1"
            ? Array.from({ length: 100 }, (_, i) => make(`示例下载文件 ${i + 1}.txt`, "C:\\Downloads", false))
            : [make("示例文件夹", "C:\\Downloads"), make("第二个文件夹", "C:\\Downloads"), ...files.slice(0, 2)];
          break;
        case "open":
          console.log("Fixture open:", arg.path);
          result = true;
          break;
        case "layout":
          settings.sidebarFraction = arg.fraction;
          settings.widths = arg.widths;
          result = true;
          break;
        case "generateRule":
          result = ruleFor(arg.name);
          break;
        case "categories":
          settings.categories = arg.categories;
          result = state();
          break;
        case "namingRules":
          settings.namingRules = arg;
          result = state();
          break;
        case "assign":
          for (const e of arg.items)
            settings.assignments[e.path] = {
              identity: e.identity,
              categoryID: arg.id,
            };
          result = state();
          break;
        case "naming":
          result = arg.items.map((e) => ({
            entry: e,
            prefix: e.folder ? "10月" : "方案",
            category: "方案",
            format: e.folder ? "month" : "category",
            ext: e.folder ? "" : path.win32.extname(e.name),
            candidates: [
              {
                name: "民政厅机关网络运维及网络安全运维项目",
                evidence: "隔离示例标题",
              },
            ],
            warnings: [],
          }));
          break;
        case "archiveSuggest":
          result = {
            projects: projects.map((p, i) => ({
              ...p,
              score: i === 0 ? 10 : 0,
              evidence: "隔离示例名称匹配",
            })),
            warnings: [],
          };
          break;
        case "checkUpdate":
          result = { message: "隔离预览，不访问更新服务。" };
          break;
        default:
          throw Error("此操作请在桌面应用中验证。");
      }
      res.setHeader("content-type", "application/json");
      res.end(JSON.stringify({ ok: true, data: result }));
      return;
    }
    if (req.url === "/fixture-bridge.js") {
      res.setHeader("content-type", "text/javascript");
      res.end(
        `window.guiyu={invoke:async(method,arg)=>{const r=await(await fetch('/fixture-api',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({method,arg})})).json();if(!r.ok)throw Error(r.error);return r.data;}};`,
      );
      return;
    }
    let p = path.resolve(root, "." + decodeURIComponent(req.url.split("?")[0]));
    if (!p.startsWith(root + path.sep)) {
      res.writeHead(403);
      res.end();
      return;
    }
    let body = await fs.readFile(p);
    res.setHeader(
      "content-type",
      p.endsWith(".html")
        ? "text/html"
        : p.endsWith(".cjs") || p.endsWith(".js")
          ? "text/javascript"
          : p.endsWith(".css")
            ? "text/css"
            : p.endsWith(".png")
              ? "image/png"
              : "application/octet-stream",
    );
    if (p.endsWith("index.html"))
      body = Buffer.from(
        body
          .toString()
          .replace(
            '<script src="ui.cjs">',
            '<script src="/fixture-bridge.js"></script><script src="ui.cjs">',
          ),
      );
    res.end(body);
  } catch (e) {
    res.writeHead(req.url === "/fixture-api" ? 200 : 500, {
      "content-type": "application/json",
    });
    res.end(JSON.stringify({ ok: false, error: e.message }));
  }
});
server.listen(48321, "127.0.0.1", () =>
  console.log("Fixture preview http://127.0.0.1:48321/src/index.html"),
);
