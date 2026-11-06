"use strict";
// Run the real public-upgrade test with Chromium's diagnostic logging enabled.
// Only the launch arguments and cleanup of the disposable old process differ.
const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const logPath = path.join(process.env.RUNNER_TEMP, "guiyu-update-netlog.json");
const spawn = childProcess.spawn;
const execFileSync = childProcess.execFileSync;
let oldPid;
childProcess.spawn = function (file, args, options) {
  if (path.basename(file) !== "Guiyu.exe" || !args.some(arg => arg.startsWith("--remote-debugging-port=")))
    return spawn(file, args, options);
  const process = spawn(file, [...args, "--log-net-log=" + logPath], options);
  oldPid = process.pid;
  return process;
};
childProcess.execFileSync = function (file, args, options) {
  if (file === "taskkill.exe" && Number(args[1]) === oldPid) {
    try {
      const close = "$p=Get-Process -Id " + oldPid + " -ErrorAction SilentlyContinue; if($p){[void]$p.CloseMainWindow();$p|Wait-Process -Timeout 4 -ErrorAction Stop}";
      return execFileSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", close],
        { stdio: "ignore", timeout: 7000 });
    } catch {}
  }
  return execFileSync(file, args, options);
};

function safeURL(value) {
  try {
    const url = new URL(value);
    return url.origin + url.pathname;
  } catch {
    return undefined;
  }
}

process.once("beforeExit", () => {
  try {
    const raw = fs.readFileSync(logPath, "utf8");
    const marker = /"events"\s*:\s*\[/.exec(raw);
    const constants = JSON.parse(raw.slice(0, marker.index).trim().replace(/,$/, "") + "}").constants;
    const names = new Map(Object.entries(constants.logEventTypes).map(([name, value]) => [value, name]));
    const lines = raw.slice(marker.index + marker[0].length).split("\n");
    for (const line of lines) {
      let event;
      try { event = JSON.parse(line.trim().replace(/,$/, "")); } catch { continue; }
      const name = names.get(event.type), p = event.params || {};
      if (/^URL_REQUEST_(START_JOB|REDIRECTED)$/.test(name)) {
        const url = safeURL(p.url || p.location);
        if (url) console.log("NET", event.source.id, name, url, p.method || "");
      }
      if (/^(HTTP_TRANSACTION_READ_RESPONSE_HEADERS|HTTP2_SESSION_RECV_HEADERS)$/.test(name)) {
        const headers = (p.headers || []).filter(header => /^(HTTP\/|:status:|server:|x-ms-error-code:|x-cache:|via:|content-type:|location:)/i.test(header));
        if (headers.length) console.log("NET", event.source.id, name,
          headers.map(header => /^location:/i.test(header) ? "location: " + safeURL(header.slice(9).trim()) : header));
      }
    }
  } catch (error) {
    console.error("Unable to read Chromium diagnostic log:", error.message);
  } finally {
    fs.rmSync(logPath, { force: true });
  }
});
require("../../Windows/tests/published-update.cjs");
