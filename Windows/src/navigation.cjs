(function (host) {
  "use strict";
  function normalized(path) {
    if (typeof path !== "string" || !path) return null;
    const drive = /^[a-z]:[\\/]/i.test(path),
      unc = /^(?:\\\\|\/\/)/.test(path),
      absolute = /^[\\/]/.test(path);
    if (!drive && !absolute) return null;
    const parts = [],
      floor = drive ? 1 : unc ? 2 : 0;
    for (const part of path.split(/[\\/]+/).filter(Boolean)) {
      if (part === ".") continue;
      if (part === "..") {
        if (parts.length <= floor) return null;
        parts.pop();
      } else parts.push(part);
    }
    return {
      parts,
      prefix: drive ? "" : unc ? "//" : "/",
      windows: drive || unc,
    };
  }
  function breadcrumbs(root, current, rootTitle) {
    const base = normalized(root),
      location = normalized(current);
    if (!base || !location) return [];
    const eq = (a, b) =>
      base.windows ? a.toLowerCase() === b.toLowerCase() : a === b;
    if (
      location.parts.length < base.parts.length ||
      base.parts.some((part, i) => !eq(part, location.parts[i]))
    )
      return [];
    const separator = root.includes("\\") ? "\\" : "/",
      pathFor = (parts) => {
        const value = (base.prefix + parts.join("/")).replace(/\//g, separator);
        return base.windows && parts.length === 1 && /^[a-z]:$/i.test(parts[0]) ? value + separator : value;
      };
    const result = [
      {
        name: rootTitle || base.parts.at(-1) || root,
        path: pathFor(base.parts),
      },
    ];
    for (let i = base.parts.length; i < location.parts.length; i++)
      result.push({
        name: location.parts[i],
        path: pathFor(location.parts.slice(0, i + 1)),
      });
    return result;
  }
  function destination(path, root, current) {
    const value = normalized(path);
    if (!value) return null;
    const key = value.prefix + value.parts.join("/");
    return (
      breadcrumbs(root, current).find((p) => {
        const n = normalized(p.path),
          candidate = n.prefix + n.parts.join("/");
        return value.windows
          ? candidate.toLowerCase() === key.toLowerCase()
          : candidate === key;
      })?.path ?? null
    );
  }
  const api = Object.freeze({ breadcrumbs, destination });
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else host.GuiyuNavigation = api;
})(globalThis);
