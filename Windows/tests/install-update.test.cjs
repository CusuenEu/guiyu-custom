"use strict";
const { test } = require("node:test"), assert = require("node:assert/strict");
const fs = require("node:fs/promises"), path = require("node:path"), os = require("node:os"), crypto = require("node:crypto");
const { createInstallerUpdater } = require("../src/install-update.cjs"), { createUpdater } = require("../src/update.cjs");
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
