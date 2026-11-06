"use strict";
const { test } = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs/promises"), path = require("node:path"), os = require("node:os"), crypto = require("node:crypto");
const { createInstallerUpdater, createReleaseDownloadFetch } = require("../src/install-update.cjs"), { createUpdater } = require("../src/update.cjs");
const bytes = Buffer.from("verified installer test fixture");
const update = { kind:"installer", url:"https://github.com/tiduse1988/guiyu/releases/download/windows-20261102-06/Guiyu-20261102-06-Windows-x64-setup.exe",
  digest:"sha256:" + crypto.createHash("sha256").update(bytes).digest("hex"), size:bytes.length, packageVersion:"2026.1102.6" };
async function fixture(t, overrides = {}) {
  const dir = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-update-unit-")));
  t.after(() => fs.rm(dir, { recursive:true, force:true }));
  const exe = path.join(dir, "Guiyu.exe"), calls = [], progress = [];
  await fs.writeFile(exe, "old app");
  let quit;
  const exited = new Promise(resolve => { quit = resolve; });
  const app = { isPackaged:true, getPath:name=>name === "exe" ? exe : dir, quit:()=>{calls.push("quit");quit();} };
  const install = createInstallerUpdater({ app, platform:"win32", fetch:async()=>new Response(bytes), progress:p=>progress.push(p),
    launch:async(helper, manifestFile)=>{ const manifest=JSON.parse(await fs.readFile(manifestFile,"utf8")); assert.equal(await fs.readFile(manifest.installer,"utf8"),bytes.toString()); assert.equal(manifest.installDir,dir); assert.match(await fs.readFile(helper,"utf8"),/Wait-Process/); calls.push(manifest); }, ...overrides });
  return { dir, exe, install, calls, progress, exited };
}
test("verified streaming download prepares the real helper before graceful exit and never opens a browser", async t => {
  const f=await fixture(t); const result=await f.install(update);
  assert.equal(result.automatic,true); assert.equal(f.calls.length,1); assert.equal(await fs.readFile(f.exe,"utf8"),"old app");
  assert(f.progress.some(p=>p.phase==='verifying')); await f.exited; assert.equal(f.calls.at(-1),'quit');
});
function brokenDownload(prefix) {
  let sent = false;
  return new Response(new ReadableStream({
    pull(controller) {
      if (sent) controller.error(Error("net::ERR_HTTP2_PROTOCOL_ERROR"));
      else {
        sent = true;
        controller.enqueue(prefix);
      }
    },
  }));
}
test("HTTP 400 then a broken stream retries with a fresh URL and resumes the verified package", async t => {
  const requests = [];
  const split = 9;
  const f = await fixture(t, { fetch: async (url, options) => {
    requests.push({ url, range: options.headers.Range });
    if (requests.length === 1) return new Response(null, { status: 400 });
    if (requests.length === 2) return brokenDownload(bytes.subarray(0, split));
    return new Response(bytes.subarray(split), {
      status: 206, headers: { "Content-Range": `bytes ${split}-${bytes.length - 1}/${bytes.length}` },
    });
  } });
  await f.install(update);
  await f.exited;
  assert.deepEqual(requests.map(request => request.range), [undefined, undefined, "bytes=9-"]);
  assert.equal(requests[0].url, update.url);
  for (const { url } of requests.slice(1)) {
    const retry = new URL(url);
    assert(retry.searchParams.has("guiyu-retry"));
    retry.search = "";
    assert.equal(retry.href, update.url);
  }
  assert(f.progress.some(value => value.phase === "retrying" && value.percent > 0));
});
test("an ignored range restarts cleanly and an inconsistent partial response never installs", async t => {
  const split = 9;
  for (const valid of [true, false]) {
    let requests = 0;
    const f = await fixture(t, { fetch: async (_url, options) => {
      if (++requests === 1) return brokenDownload(bytes.subarray(0, split));
      assert.equal(options.headers.Range, "bytes=9-");
      return valid ? new Response(bytes) : new Response(bytes.subarray(split), {
        status: 206, headers: { "Content-Range": `bytes 0-${bytes.length - 1}/${bytes.length}` },
      });
    } });
    if (valid) {
      await f.install(update);
      await f.exited;
    } else {
      await assert.rejects(f.install(update), /续传范围异常/);
      assert.equal(f.calls.length, 0);
      assert.deepEqual((await fs.readdir(f.dir)).filter(name => name.startsWith("Guiyu-update-")), []);
    }
    assert.equal(requests, 2);
  }
});
test("direct installer redirects keep Range and a proxy on either hop uses Chromium", async () => {
  const cdn = "https://release-assets.githubusercontent.com/verified-package";
  const options = { headers: { Range: "bytes=9-" } };
  for (const proxyAt of [null, update.url, cdn]) {
    const direct = [], chromium = [];
    const download = createReleaseDownloadFetch({
      resolveProxy: async url => url === proxyAt ? "PROXY gateway:8080" : "DIRECT",
      chromiumFetch: async (url, request) => { chromium.push([url, request]); return new Response(bytes); },
      directFetch: async (url, request) => {
        direct.push([url, request.headers.Range, request.redirect]);
        return url === update.url ? Response.redirect(cdn) : new Response(bytes);
      },
    });
    const response = await download(update.url, options);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), bytes);
    assert.deepEqual(chromium, proxyAt ? [[update.url, options]] : []);
    const expectedDirect = proxyAt === update.url ? [] : proxyAt === cdn ? [update.url] : [update.url, cdn];
    assert.deepEqual(direct, expectedDirect.map(url => [url, "bytes=9-", "manual"]));
  }
});
test("bad hash, size, source and download failure keep the old app running and clean temporary installers", async t => {
  for(const bad of [{...update,digest:'sha256:'+'0'.repeat(64)}, {...update,size:bytes.length-1}, {...update,url:'https://example.com/setup.exe'}]) {
    const f=await fixture(t); await assert.rejects(f.install(bad),/校验|大小|来源/); assert.equal(f.calls.length,0);
    assert.equal(await fs.readFile(f.exe,"utf8"),'old app'); assert.deepEqual((await fs.readdir(f.dir)).filter(n=>n.startsWith('Guiyu-update-')),[]);
  }
  const f=await fixture(t,{fetch:async()=>{throw Error('offline')}});await assert.rejects(f.install(update),/offline/);assert.equal(f.calls.length,0);
});
test("automatic updater hands off only the matching architecture and exact selected official asset", async()=>{
  const calls=[];const asset={name:'Guiyu-20261102-06-Windows-x64-setup.exe',state:'uploaded',browser_download_url:update.url,digest:update.digest,size:update.size};
  const updater=createUpdater({current:{date:'20261102',sequence:5},arch:'x64',fetch:async()=>({ok:true,json:async()=>[{tag_name:'windows-20261102-06',prerelease:false,assets:[asset]}]}),
    openExternal:()=>{throw Error('Unexpected browser download')},install:async p=>{calls.push(p);return{automatic:true}}});
  assert.equal((await updater.check()).automatic,true); assert.equal((await updater.download()).automatic,true); assert.equal(calls[0].url,update.url);assert.equal(calls[0].packageVersion,'2026.1102.6');
});
test("the real Windows PowerShell helper verifies the package and acknowledges readiness before exit", {skip:process.platform!=="win32"||process.env.CI!=="true"}, async t=>{
  const f=await fixture(t,{launch:undefined});
  let helperPid;
  try {
    const result=await f.install(update); assert.equal(result.automatic,true);
    const name=(await fs.readdir(f.dir)).find(n=>n.startsWith('Guiyu-update-'));
    const ready=JSON.parse((await fs.readFile(path.join(f.dir,name,'ready.json'),'utf8')).replace(/^\uFEFF/,''));
    helperPid=ready.pid; assert(helperPid>0); await f.exited;
  } finally {
    if(helperPid) try{require('node:child_process').execFileSync('taskkill',['/PID',String(helperPid),'/T','/F'],{stdio:'ignore'});}catch{}
  }
});
