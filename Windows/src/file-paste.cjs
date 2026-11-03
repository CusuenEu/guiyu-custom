"use strict";
const fs = require("node:fs/promises"), path = require("node:path");
const { constants } = require("node:fs");
const { entry, inside } = require("./core.cjs");

// Copy asynchronously. Each new file/directory is exclusively created; a failed
// top-level item is rolled back and is never reported as a completed copy.
async function copyTree(source, target, io = fs) {
  const before = await io.lstat(source);
  if (before.isSymbolicLink()) throw Error("暂不复制符号链接或目录联接。");
  if (before.isDirectory()) {
    await io.mkdir(target);
    try {
      for (const name of await io.readdir(source))
        await copyTree(path.join(source, name), path.join(target, name), io);
    } catch (error) {
      await io.rm(target, { recursive: true, force: true });
      throw error;
    }
  } else if (before.isFile()) {
    // An EEXIST error belongs to another file and must never be cleaned up.
    let owned = false;
    try {
      const handle = await io.open(target, "wx");
      owned = true;
      await handle.close();
      await io.copyFile(source, target, constants.COPYFILE_FICLONE);
      const after = await io.lstat(source);
      if (after.size !== before.size || after.mtimeMs !== before.mtimeMs || after.ino !== before.ino)
        throw Error("复制期间源文件发生变化，请重试。");
      await io.utimes(target, before.atime, before.mtime);
    } catch (error) {
      if (owned) await io.rm(target, { force: true });
      throw error;
    }
  } else throw Error("暂不复制此类型的文件。");
}
function numbered(name, folder, n) {
  if (n === 1) return name;
  const ext = folder ? "" : path.extname(name);
  return name.slice(0, name.length - ext.length) + ` (${n})` + ext;
}
async function pasteFiles(paths, destination, { io = fs } = {}) {
  if (!Array.isArray(paths) || !paths.length || paths.some(p => typeof p !== "string" || !path.isAbsolute(p)))
    throw Error("剪贴板中没有可粘贴的文件。");
  const realDestination = await io.realpath(destination);
  if (!(await io.lstat(realDestination)).isDirectory()) throw Error("粘贴目标不是文件夹。");
  const candidates = [], errors = [], copied = [];
  for (const source of [...new Set(paths)]) {
    try {
      const stat = await io.lstat(source);
      if (stat.isSymbolicLink()) throw Error("暂不复制符号链接或目录联接。");
      const real = await io.realpath(source);
      if (stat.isDirectory() && inside(realDestination, real)) throw Error("不能把文件夹复制到自身或其内部。");
      candidates.push({ path: real, folder: stat.isDirectory() });
    } catch (error) { errors.push({ path: source, message: error.message }); }
  }
  const unique = candidates.filter((item, i) => !candidates.some((parent, j) =>
    i !== j && parent.folder && inside(item.path, parent.path) &&
    (item.path !== parent.path || j < i)));
  for (const item of unique) {
    try {
      for (let n = 1; ; n++) {
        const target = path.join(realDestination, numbered(path.basename(item.path), item.folder, n));
        try {
          await copyTree(item.path, target, io);
          copied.push(await entry(target));
          break;
        } catch (error) {
          // Only a collision at this top-level destination is a naming retry.
          if (error.code === "EEXIST" && error.path === target) continue;
          throw error;
        }
      }
    } catch (error) { errors.push({ path: item.path, message: error.message }); }
  }
  return { copied, errors };
}
module.exports = { pasteFiles, numbered };
