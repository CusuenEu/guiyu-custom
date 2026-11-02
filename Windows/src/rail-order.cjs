(function (host) {
  "use strict";
  function moved(paths, from, target, after) {
    if (from === target || !paths.includes(from) || !paths.includes(target)) return null;
    const result = paths.filter(p => p !== from);
    result.splice(result.indexOf(target) + Number(Boolean(after)), 0, from);
    return result;
  }
  const api = Object.freeze({ moved });
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else host.GuiyuRailOrder = api;
})(globalThis);
