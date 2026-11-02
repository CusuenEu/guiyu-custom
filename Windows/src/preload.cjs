const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("guiyu", {
  onUpdateProgress: callback => ipcRenderer.on("guiyu-update-progress", (event, value) => callback(value)),
  cancelNaming: () => ipcRenderer.send("guiyu-cancel-naming"),
  onCommand: (callback) =>
    ipcRenderer.on("guiyu-command", (event, command) => callback(command)),
  invoke: async (method, arg) => {
    const r = await ipcRenderer.invoke("guiyu", method, arg);
    if (!r.ok) throw Error(r.error);
    return r.data;
  },
});
