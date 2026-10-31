const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("guiyu", {
  onCommand: (callback) =>
    ipcRenderer.on("guiyu-command", (event, command) => callback(command)),
  invoke: async (method, arg) => {
    const r = await ipcRenderer.invoke("guiyu", method, arg);
    if (!r.ok) throw Error(r.error);
    return r.data;
  },
});
