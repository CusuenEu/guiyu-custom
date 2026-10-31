# 归屿 20261031(02) Windows 测试版

解压整个文件夹，双击 `Guiyu.exe`。不需要安装 Node.js，不要只拷贝 exe。

- Windows 10 32位：下载 Windows-ia32 包。
- Windows 10 / Windows 11 64位：下载 Windows-x64 包。
- Windows 11 没有32位系统；未针对 Windows ARM64 验证。
- 主窗口延续森林绿导航、薄荷绿项目栏、白色文件栏及小鸡图标；使用 Windows 系统标题栏和字体。

首次打开通过“＋”关联项目总目录；左栏显示其直接子目录，中间显示项目，右栏显示当前项目的直接子项。首次安装分类为空，点击“请设置文件分类”添加分类。可点“体验示例空间”使用隔离的临时示例。

支持三种视图、名称多关键词搜索、项目月份/修改时间排序、子文件夹导航、Ctrl/Shift多选、分类拖放、手动/智能命名、批量命名、智能归档和撤销、分类规则及豆包剪贴板流程。命名和归档均需明确确认，重名不覆盖；文件仍保留于本机原有目录。刷新只读取文件元数据。

快捷键：空格预览；Enter打开；F2更名；Ctrl+A全选；Delete移入回收站（有确认）；Ctrl+F搜索；Ctrl+R刷新。

设置→文件位置中可安装/移除当前用户的资源管理器右键入口。Win11可能显示在“显示更多选项”中；移动应用目录后需重新安装入口。

## 系统适配与当前限制

这是 Windows 测试版，不代表已完成全部系统验收。本次已在当前 Windows 电脑启动并进行部分界面检查；Win10 x86/x64、Win11 x64 的完整兼容性、OCR、Office、回收站、跨磁盘归档和右键入口仍需分别实测。

- PDF优先读取文字层；扫描PDF/图片按需调用 Windows 本地OCR，需要系统安装相应中文/英文OCR语言组件。OCR失败会提示，可手工输入名称。
- DOCX/XLSX/UTF-8与UTF-16文本本地提取；旧DOC/RTF提取需要安装桌面版Microsoft Word。旧XLS不提取正文。
- PDF/图片使用独立预览窗；Office显示提取文本，双击仍用本机默认软件编辑。尚无与macOS Quick Look完全相同的Office排版预览。图片格式受系统解码器限制。
- Windows“最近使用”来自系统Recent快捷方式，最多500项，不等同于Finder Spotlight范围。
- 目前名称检索使用本地内存元数据，未迁移macOS的SQLite索引；大型目录的搜索响应仍需压力测试。
- 归档推荐和智能命名使用本地规则，候选可能与macOS版本不同；Word分页及复杂表格提取仍有限。
- 检查更新仅查询GitHub Windows包，后续手动下载替换；尚未实现与Sparkle等价的签名自动安装流程。
- 尚未做Windows代码签名；源码提交不等于发布安装包。
- 32位框架固定Electron 43.8.6；后续框架版本不再提供x86，需持续维护兼容分支。
- 配置：`%APPDATA%\Guiyu-Windows\settings.json`，正文不持久化。配置与Mac版独立，不能直接复制含Mac路径的配置。
- 跨磁盘目录归档采用复制、校验、删除；失败时保留源或停止剩余项，可能留下目标副本，请按错误提示核对。批量文件操作不具有事务性。

## 开发

安装 Node.js 22.13+ 或 24+，在本目录运行：

```
npm ci --omit=optional
npm test
npm start
npm run package
```

打包输出 `out/Guiyu-20261031-02-test-Windows-ia32.zip` 和 `out/Guiyu-20261031-02-test-Windows-x64.zip`。生产依赖不含平台原生模块，PDF文字提取不依赖native canvas。`npm run preview` 仅启动内存示例界面，不访问用户项目。

许可证：MIT；Electron、PDF.js、fflate、DOMMatrix及其他依赖保留各自许可证。交付包内附框架LICENSE和依赖许可证。
