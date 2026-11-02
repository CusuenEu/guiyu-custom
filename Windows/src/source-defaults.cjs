"use strict";
function defaults(getPath) {
  return [
    { id: "downloads", name: "下载", kind: "folder", path: getPath("downloads") },
    { id: "desktop", name: "桌面", kind: "folder", path: getPath("desktop") },
  ];
}
function migrate(sources, desktop) {
  let changed = false, inserted = sources.some(s => s.id === "desktop");
  const next = sources.flatMap(s => {
    if (s.id === "recent" || s.kind === "recent") {
      changed = true;
      if (inserted) return [];
      inserted = true;
      return [desktop];
    }
    if (s.id === "desktop" && (s.path !== desktop.path || s.name !== desktop.name || s.kind !== "folder")) {
      changed = true;
      return [{ ...s, ...desktop }];
    }
    return [s];
  });
  return changed ? next : sources;
}
module.exports = { defaults, migrate };
