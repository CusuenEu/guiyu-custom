"use strict";

const repository = "https://github.com/tiduse1988/guiyu";
const releasesAPI = "https://api.github.com/repos/tiduse1988/guiyu/releases";

function version(value) {
  if (!/^\d{8}$/.test(value?.date) || !Number.isInteger(value.sequence) ||
      value.sequence < 1 || value.sequence > 99) throw Error("Windows 版本信息无效。");
  return { number: Number(value.date) * 100 + value.sequence,
    display: `${value.date}(${String(value.sequence).padStart(2, "0")})` };
}

function selectUpdate(releases, current, arch) {
  if (!["ia32", "x64"].includes(arch))
    throw Error("当前架构尚无 Windows 更新包，请查看下载页面。");
  const installed = version(current);
  const candidates = [];
  for (const release of releases) {
    if (release.draft || !release.tag_name) continue;
    // Keep legacy asset names readable; derive Windows versions from their
    // assets, never from a Mac release tag.
    for (const asset of release.assets || []) {
      const match = /^Guiyu-(\d{8})-(\d{2})-(?:test-)?Windows-(ia32|x64)(-setup\.exe|\.zip)$/.exec(asset.name);
      if (!match || match[3] !== arch || asset.state !== "uploaded") continue;
      let candidate;
      try { candidate = version({ date: match[1], sequence: Number(match[2]) }); }
      catch { continue; }
      const url = `${repository}/releases/download/${encodeURIComponent(release.tag_name)}/${encodeURIComponent(asset.name)}`;
      if (asset.browser_download_url !== url) continue;
      candidates.push({ ...candidate, url, prerelease: Boolean(release.prerelease),
        kind: match[4] === ".zip" ? "zip" : "installer" });
    }
  }
  const stable = candidates.filter(candidate => !candidate.prerelease);
  const eligible = stable.length ? stable : candidates;
  eligible.sort((a, b) => b.number - a.number ||
    Number(b.kind === "installer") - Number(a.kind === "installer"));
  const latest = eligible[0];
  if (!latest) return { status: "unavailable",
    message: `暂未发布适用于当前 ${arch === "x64" ? "64" : "32"} 位程序的 Windows 更新包。` };
  if (latest.number <= installed.number) return { status: "current",
    message: `当前 Windows 版本 ${installed.display} 已是最新发布版本。` };
  return { status: "available", url: latest.url, version: latest.display,
    kind: latest.kind,
    message: `发现 Windows 新版本 ${latest.display}（当前 ${installed.display}）。${latest.kind === "installer" ? "下载后关闭归屿，再运行安装包更新。" : "下载后关闭归屿，解压到新文件夹并运行。"}` };
}

function createUpdater({ fetch, openExternal, current, arch, timeout = 15000 }) {
  let pending;
  return {
    async check() {
      pending = undefined;
      const signal = AbortSignal.timeout(timeout);
      const releases = [];
      for (let page = 1; page <= 10; page++) {
        let response, batch;
        try {
          response = await fetch(`${releasesAPI}?per_page=100&page=${page}`, {
            headers: { Accept: "application/vnd.github+json" }, signal,
          });
          if (response.ok) batch = await response.json();
        } catch {
          throw Error(signal.aborted ? "检查更新超时，请检查网络后重试。" :
            "无法连接更新服务，请检查网络后重试。");
        }
        if (!response.ok) throw Error([403, 429].includes(response.status) ?
          "GitHub 更新服务访问受限，请稍后重试。" :
          `更新服务暂不可用（${response.status}），请稍后重试。`);
        if (!Array.isArray(batch)) throw Error("更新服务返回格式异常，请稍后重试。");
        releases.push(...batch);
        if (batch.length < 100) {
          const result = selectUpdate(releases, current, arch);
          if (result.status === "available") pending = result;
          return result;
        }
      }
      throw Error("发行记录较多，未能完成更新检查，请查看下载页面。");
    },
    async download() {
      if (!pending) throw Error("请先检查更新，确认有可用的 Windows 新版本。");
      // Only open the exact official asset selected in the main process.
      await openExternal(pending.url);
      return true;
    },
  };
}

module.exports = { createUpdater, selectUpdate };
