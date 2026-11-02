"use strict";
// Build a per-user installer from an already packaged Electron directory.
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

async function createInstaller(appDir, output) {
  const compiler = process.env.GUIYU_MAKENSIS || path.join(process.env.LOCALAPPDATA || "", "electron-builder/Cache/nsis/nsis-3.0.4.1/makensis.exe");
  try { await fs.access(compiler); } catch { throw Error("找不到 NSIS makensis.exe；请设置 GUIYU_MAKENSIS 后重新打包。"); }
  const files = [], dirs = [];
  async function walk(relative = "") {
    for (const item of await fs.readdir(path.join(appDir, relative), { withFileTypes: true })) {
      const rel = path.join(relative, item.name);
      if (item.isDirectory()) { await walk(rel); dirs.push(rel); }
      else files.push(rel);
    }
  }
  await walk();
  const escape = s => s.replace(/\$/g, "$$$$").replace(/"/g, '$\\"');
  const deleteFiles = files.map(f => `  Delete "$INSTDIR\\${escape(f)}"`).join("\n");
  const removeDirs = dirs.map(d => `  RMDir "$INSTDIR\\${escape(d)}"`).join("\n");
  const actions = [
    ['GuiyuName', '归屿-智能命名', '--smart-name'],
    ['GuiyuArchive', '归屿-智能归档', '--smart-archive'],
  ];
  const menuInstall = ['*', 'Directory'].flatMap(kind => actions.map(([key, label, flag]) => {
    const registry = `Software\\Classes\\${kind}\\shell\\${key}`;
    return `  WriteRegStr HKCU "${registry}" "" "${label}"
  WriteRegStr HKCU "${registry}" "Icon" '$\\"$INSTDIR\\Guiyu.exe$\\",0'
  WriteRegStr HKCU "${registry}\\command" "" '$\\"$INSTDIR\\Guiyu.exe$\\" ${flag} $\\"%1$\\"'`;
  })).join('\n');
  const menuRemove = ['*', 'Directory'].flatMap(kind => actions.map(([key, , flag]) => {
    const registry = `Software\\Classes\\${kind}\\shell\\${key}`;
    return `  ReadRegStr $0 HKCU "${registry}\\command" ""
  StrCmp $0 '$\\"$INSTDIR\\Guiyu.exe$\\" ${flag} $\\"%1$\\"' 0 +2
  DeleteRegKey HKCU "${registry}"`;
  })).join('\n');
  const script = `Unicode true
!include "MUI2.nsh"
!include "x64.nsh"
Name "归屿"
OutFile "${escape(output)}"
InstallDir "$LOCALAPPDATA\\Programs\\Guiyu"
RequestExecutionLevel user
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"
!macro RegistryView
  \${If} \${RunningX64}
    SetRegView 64
  \${Else}
    SetRegView 32
  \${EndIf}
!macroend
Function .onInit
  !insertmacro RegistryView
FunctionEnd
Function un.onInit
  !insertmacro RegistryView
FunctionEnd
Section "安装"
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  File /r "${escape(appDir)}\\*"
  WriteUninstaller "$INSTDIR\\卸载归屿.exe"
  CreateDirectory "$SMPROGRAMS\\归屿"
  CreateShortcut "$SMPROGRAMS\\归屿\\归屿.lnk" "$INSTDIR\\Guiyu.exe"
  CreateShortcut "$DESKTOP\\归屿.lnk" "$INSTDIR\\Guiyu.exe" "" "$INSTDIR\\Guiyu.exe" 0
${menuInstall}
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Guiyu" "DisplayName" "归屿"
  WriteRegStr HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Guiyu" "UninstallString" '"$INSTDIR\\卸载归屿.exe"'
  WriteRegDWORD HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Guiyu" "NoModify" 1
  WriteRegDWORD HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Guiyu" "NoRepair" 1
SectionEnd
Section "Uninstall"
  SetShellVarContext current
  Delete "$DESKTOP\\归屿.lnk"
  Delete "$SMPROGRAMS\\归屿\\归屿.lnk"
  RMDir "$SMPROGRAMS\\归屿"
${menuRemove}
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
${deleteFiles}
${removeDirs}
  Delete "$INSTDIR\\卸载归屿.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Guiyu"
SectionEnd
`;
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "guiyu-installer-"));
  const nsi = path.join(tmp, "installer.nsi");
  try {
    await fs.writeFile(nsi, "\ufeff" + script, "utf8");
    execFileSync(compiler, ["/V2", nsi], { stdio: "inherit" });
  } finally {
    await fs.unlink(nsi).catch(() => {});
    await fs.rmdir(tmp).catch(() => {});
  }
}
module.exports = { createInstaller };
