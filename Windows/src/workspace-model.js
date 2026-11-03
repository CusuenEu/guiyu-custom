(function (root) {
  "use strict";
  const fallbackID = "__guiyu_display_other__";
  const norm = value => String(value).normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase();
  function term(name, value) {
    value = norm(value);
    return /^[\x20-\x7f]+$/.test(value)
      ? new RegExp("(^|[^a-z0-9])" + value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "($|[^a-z0-9])").test(norm(name))
      : norm(name).includes(value);
  }
  function category(item, settings) {
    const assigned = settings.assignments[item.path];
    if (assigned?.identity === item.identity && settings.categories.some(c => c.id === assigned.categoryID))
      return assigned.categoryID;
    const fallback = settings.categories.find(c => c.name === "其他" || c.id === "其他");
    const scores = settings.categories.filter(c => c !== fallback).map(c => {
      const r = c.rule;
      if (!r?.enabled || (r.scope === "仅文件" && item.folder) || (r.scope === "仅文件夹" && !item.folder) || r.excludedKeywords.some(t => term(item.name, t))) return [c.id, -1];
      const hits = r.keywords.filter(t => term(item.name, t));
      return [c.id, hits.length ? r.priority * 1000 + 200 + Math.min(80, Math.max(...hits.map(t => t.length)))
        : !item.folder && r.extensions.some(ext => norm(item.name).endsWith("." + norm(ext))) ? r.priority * 1000 + 20 : -1];
    });
    const max = Math.max(-1, ...scores.map(s => s[1])), wins = scores.filter(s => s[1] === max);
    return max >= 0 && wins.length === 1 ? wins[0][0] : fallback?.id || fallbackID;
  }
  function pasteTarget({ pane, source, dir, current, sourcePreviewCurrent, active, selected, middleRows }) {
    if (pane === "files") return active ? (source ? sourcePreviewCurrent : current) : "";
    if (pane === "directories") return dir || "";
    const selectedFolder = [...middleRows].reverse().find(e => e.folder && selected.has(e.path));
    if (selectedFolder) return selectedFolder.path;
    return source ? (source.kind === "folder" ? current || source.path : "") : dir || "";
  }
  const api = { category, fallbackID, pasteTarget };
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.GuiyuWorkspace = api;
})(typeof globalThis === "object" ? globalThis : this);
