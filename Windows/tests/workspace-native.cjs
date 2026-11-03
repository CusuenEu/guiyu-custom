"use strict";
// Run the real packaged renderer/preload/main process against real temporary
// folders. The test shim lives only in a temporary copy, never in the release.
const fs = require("node:fs/promises"), path = require("node:path"), os = require("node:os");
const { spawn } = require("node:child_process");
async function run() {
  if (process.platform !== "win32" || process.env.CI !== "true") throw Error("Native workspace checks require a disposable Windows CI runner.");
  const { createPackage } = await import("@electron/asar");
  const out = path.resolve(__dirname, "../out");
  for (const arch of ["ia32", "x64"]) {
    const temp = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), `guiyu-workspace-${arch}-`)));
    try {
      const runtime = path.join(temp, "runtime"), shim = path.join(temp, "shim");
      await fs.cp(path.join(out, `Guiyu-win32-${arch}`), runtime, { recursive: true });
      await fs.rename(path.join(runtime, "resources/app.asar"), path.join(runtime, "resources/production.asar"));
      await fs.rename(path.join(runtime, "resources/app.asar.unpacked"), path.join(runtime, "resources/production.asar.unpacked"));
      await fs.mkdir(shim);
      await fs.writeFile(path.join(shim, "package.json"), JSON.stringify({ name: `guiyu-workspace-test-${arch}`, version: "1.0.0", main: "runner.cjs" }));
      await fs.copyFile(path.join(__dirname, "workspace-native-runner.cjs"), path.join(shim, "runner.cjs"));
      await createPackage(shim, path.join(runtime, "resources/app.asar"));
      await new Promise((resolve, reject) => {
        const child = spawn(path.join(runtime, "Guiyu.exe"), [], {
          env: { ...process.env, GUIYU_REVIEW: "1", GUIYU_WORKSPACE_TEST: temp }, stdio: ["ignore", "pipe", "pipe"], windowsHide: true,
        });
        const timer = setTimeout(() => { child.kill(); reject(Error(`${arch} native workspace check timed out`)); }, 240000);
        child.stdout.on("data", data => process.stdout.write(data));
        child.stderr.on("data", data => process.stderr.write(data));
        child.once("error", error => { clearTimeout(timer); reject(error); });
        child.once("exit", code => { clearTimeout(timer); code === 0 ? resolve() : reject(Error(`${arch} native workspace exit ${code}`)); });
      });
      console.log(`PASS ${arch}: real packaged workspace/IPC/filesystem regression`);
    } finally { await fs.rm(temp, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }); }
  }
}
run().catch(error => { console.error(error); process.exitCode = 1; });
