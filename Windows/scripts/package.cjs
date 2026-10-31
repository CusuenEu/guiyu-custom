const fs = require("node:fs/promises"),
  path = require("node:path"),
  { packager } = require("@electron/packager"),
  { execFileSync } = require("node:child_process");
(async () => {
  const root = path.resolve(__dirname, ".."),
    out = path.join(root, "out"),
    version = require("../package.json").devDependencies.electron;
  const release = require("./version.cjs").sync();
  await fs.mkdir(out, { recursive: true });
  for (const arch of ["ia32", "x64"]) {
    const dirs = await packager({
      dir: root,
      out,
      name: "Guiyu",
      platform: "win32",
      arch,
      electronVersion: version,
      overwrite: true,
      prune: true,
      asar: { unpackDir: "node_modules" },
      appVersion: release.packageVersion,
      buildVersion: release.packageVersion + ".0",
      icon: path.join(root, "assets/AppIcon.ico"),
      appCopyright: "Copyright © 2026 Guiyu",
      win32metadata: {
        CompanyName: "Guiyu",
        FileDescription: "归屿 · 本地项目文件工作空间",
        ProductName: "归屿",
        InternalName: "Guiyu",
      },
      ignore: [
        /^\/out($|\/)/,
        /^\/tests($|\/)/,
        /^\/review($|\/)/,
        /^\/README\.md$/,
        /^\/VALIDATION\.md$/,
        /^\/COMPATIBILITY\.md$/,
        /^\/out-[^/]+\.png$/,
        /^\/scripts\/(package|preview)\.cjs$/,
      ],
      electronZipDir: process.env.GUIYU_ELECTRON_ZIP_DIR,
      download: {},
    });
    for (const dir of dirs) {
      await fs.copyFile(
        path.join(root, "README.md"),
        path.join(dir, "使用说明.md"),
      );
      await fs.copyFile(path.join(root, 'VALIDATION.md'), path.join(dir, '验证范围.md'));
      const zip = path.join(out, `${release.assetPrefix}-test-Windows-${arch}.zip`);
      if (process.platform === "win32") {
        const { zipSync } = require("fflate");
        async function collect(d, base, files = {}) {
          for (const item of await fs.readdir(d, { withFileTypes: true })) {
            let p = path.join(d, item.name),
              n = base + "/" + item.name;
            if (item.isDirectory()) await collect(p, n, files);
            else files[n] = new Uint8Array(await fs.readFile(p));
          }
          return files;
        }
        await fs.writeFile(
          zip,
          zipSync(await collect(dir, path.basename(dir))),
        );
      } else
        execFileSync("/usr/bin/ditto", ["-c", "-k", "--keepParent", dir, zip]);
      console.log(zip);
      if (process.platform === "win32") {
        const installer = path.join(out, `${release.assetPrefix}-test-Windows-${arch}-setup.exe`);
        await require("./installer.cjs").createInstaller(dir, installer);
        console.log(installer);
      }
    }
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
