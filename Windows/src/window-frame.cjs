"use strict";
const fs = require("node:fs"),
  path = require("node:path");
const minimum = { width: 1060, height: 700 };
function valid(frame) {
  return (
    frame &&
    ["x", "y", "width", "height"].every((k) => Number.isFinite(frame[k])) &&
    frame.width > 0 &&
    frame.height > 0
  );
}
function fit(frame, areas, preferred = areas[0], min = minimum) {
  if (!valid(frame) || !areas.length) return null;
  const overlap = (a) =>
    Math.max(
      0,
      Math.min(frame.x + frame.width, a.x + a.width) - Math.max(frame.x, a.x),
    ) *
    Math.max(
      0,
      Math.min(frame.y + frame.height, a.y + a.height) - Math.max(frame.y, a.y),
    );
  const closest = [...areas].sort((a, b) => overlap(b) - overlap(a))[0],
    screen = overlap(closest) > 0 ? closest : preferred,
    width = Math.max(min.width, Math.min(frame.width, screen.width)),
    height = Math.max(min.height, Math.min(frame.height, screen.height));
  return {
    x: Math.round(
      width <= screen.width
        ? Math.min(Math.max(frame.x, screen.x), screen.x + screen.width - width)
        : screen.x,
    ),
    y: Math.round(
      height <= screen.height
        ? Math.min(
            Math.max(frame.y, screen.y),
            screen.y + screen.height - height,
          )
        : screen.y,
    ),
    width: Math.round(width),
    height: Math.round(height),
  };
}
function restore(file, screen) {
  try {
    const frame = JSON.parse(fs.readFileSync(file, "utf8"));
    return fit(
      frame,
      screen.getAllDisplays().map((d) => d.workArea),
      screen.getPrimaryDisplay().workArea,
    );
  } catch {
    return null;
  }
}
function attach(window, file, screen, app) {
  let timer,
    closed = false;
  const save = () => {
    clearTimeout(timer);
    if (
      closed ||
      window.isDestroyed() ||
      window.isFullScreen() ||
      window.isMinimized() ||
      window.isMaximized()
    )
      return;
    const frame = window.getNormalBounds();
    if (!valid(frame)) return;
    try {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file + ".tmp", JSON.stringify(frame));
      fs.renameSync(file + ".tmp", file);
    } catch (e) {
      console.warn("窗口位置未保存：" + e.message);
    }
  };
  const schedule = () => {
    clearTimeout(timer);
    timer = setTimeout(save, 200);
  };
  const refit = () => {
    if (
      closed ||
      window.isDestroyed() ||
      window.isFullScreen() ||
      window.isMinimized()
    )
      return;
    const bounds = fit(
      window.getNormalBounds(),
      screen.getAllDisplays().map((d) => d.workArea),
      screen.getPrimaryDisplay().workArea,
    );
    if (bounds) window.setBounds(bounds);
    schedule();
  };
  window.on("move", schedule);
  window.on("resize", schedule);
  window.on("resized", save);
  window.on("close", save);
  app.on("before-quit", save);
  screen.on("display-removed", refit);
  screen.on("display-metrics-changed", refit);
  window.once("closed", () => {
    closed = true;
    clearTimeout(timer);
    app.removeListener("before-quit", save);
    screen.removeListener("display-removed", refit);
    screen.removeListener("display-metrics-changed", refit);
  });
  return { save };
}
module.exports = { valid, fit, restore, attach, minimum };
