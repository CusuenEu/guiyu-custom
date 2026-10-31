const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path"),
  { EventEmitter } = require("node:events"),
  { execFileSync } = require("node:child_process");
const { fit, restore, attach } = require("../src/window-frame.cjs");
test("normal bounds fit available displays, keep minimum size and reachable top on tiny screens", () => {
  const main = { x: 0, y: 0, width: 1600, height: 1000 },
    second = { x: -1440, y: 0, width: 1440, height: 900 },
    saved = { x: -1300, y: 100, width: 1200, height: 750 };
  assert.deepEqual(fit(saved, [main, second], main), saved);
  assert.deepEqual(
    fit({ x: 9000, y: 3000, width: 1800, height: 1200 }, [main]),
    main,
  );
  assert.deepEqual(fit({ x: 100, y: 100, width: 200, height: 100 }, [main]), {
    x: 100,
    y: 100,
    width: 1060,
    height: 700,
  });
  assert.deepEqual(fit(saved, [{ x: 0, y: 0, width: 1024, height: 600 }]), {
    x: 0,
    y: 0,
    width: 1060,
    height: 700,
  });
  assert.equal(fit({ x: NaN, y: 0, width: 100, height: 200 }, [main]), null);
});
test("close flush persists normal geometry across a new process; minimized/fullscreen geometry never overwrites it", (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "guiyu-frame-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const file = path.join(dir, "frame.json"),
    screen = new EventEmitter(),
    app = new EventEmitter(),
    window = new EventEmitter();
  let bounds = { x: 25, y: 40, width: 1200, height: 780 },
    excluded = false;
  Object.assign(window, {
    isDestroyed: () => false,
    isFullScreen: () => excluded,
    isMinimized: () => false,
    isMaximized: () => false,
    getNormalBounds: () => bounds,
    setBounds: (b) => (bounds = b),
  });
  screen.getAllDisplays = () => [
    { workArea: { x: 0, y: 0, width: 1600, height: 1000 } },
  ];
  screen.getPrimaryDisplay = () => screen.getAllDisplays()[0];
  assert.equal(restore(file, screen), null);
  attach(window, file, screen, app);
  window.emit("resize");
  window.emit("close");
  assert.deepEqual(JSON.parse(fs.readFileSync(file)), bounds);
  bounds = { x: 9000, y: 9000, width: 3000, height: 2000 };
  excluded = true;
  window.emit("resize");
  window.emit("close");
  assert.equal(JSON.parse(fs.readFileSync(file)).width, 1200);
  const read = JSON.parse(
    execFileSync(
      process.execPath,
      [
        "-e",
        `console.log(require('fs').readFileSync(${JSON.stringify(file)},'utf8'))`,
      ],
      { encoding: "utf8" },
    ),
  );
  assert.equal(read.x, 25);
  window.emit("closed");
  assert.equal(screen.listenerCount("display-removed"), 0);
});
