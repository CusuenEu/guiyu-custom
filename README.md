# 归屿（定制版）· 让每份文件都有归处

> 本仓库是 [tiduse1988/guiyu](https://github.com/tiduse1988/guiyu) 的定制构建。**原作者：tiduse1988**，许可证同上游（MIT），版权归原作者所有。

一款本地文件整理工具，帮助你给文件命名、归档和快速查找。支持 Mac 与 Windows，免费开源。

方案、招标文件、投标文件和报价表，常常散落在下载文件夹和层层项目目录里。归屿把真实项目目录、文件整理和快速查找放进一个原生 macOS 工作空间，让你更容易给文件起好名字、放对位置、再次找到。全程本地运行，文件不上传。

[下载最新定制版](https://github.com/CusuenEu/guiyu-custom/releases/latest) · [更新日志](https://github.com/CusuenEu/guiyu-custom/releases) · [上游原版与完整文档](https://github.com/tiduse1988/guiyu)

---

## 核心功能

| 能力 | 使用方式 |
| --- | --- |
| 智能命名 | 按需读取本地文档（前两页、双栏预览、本机框选 OCR），推荐文件名并展示依据；由你确认才真正改名 |
| 智能归档 | 从下载、桌面或关联目录选中文件，推荐目标项目；确认后移动，同名自动编号不覆盖，可撤销 |
| 快速搜索 | 本地文件名索引，空格分隔多关键词跨项目查找 |
| Finder 集成 | 右键 →「服务」直接调用智能命名/智能归档；三栏原生文件浏览 |

## 定制内容（在原版之上新增）

| 功能 | 说明 |
| --- | --- |
| **七色 Finder 标签自动写入** | 归档/改名确认后自动打标签（收件箱🟡/个人🟠/工作🔴/学习🟢/项目🔵/媒体🟣/系统⚪），合并写入、不覆盖已有标签 |
| **AI 生成规则** | 文件分类页一键生成分类规则，直连小米 MiMo / Kimi（OpenAI 兼容接口），不依赖任何第三方网页 |
| **NAS 友好** | 自动过滤群晖系统目录（#recycle/@eaDir），目标列表只显示真实目录 |
| **定制更新通道** | 官方更新通道已停用，更新一律走本仓库 [Releases](https://github.com/CusuenEu/guiyu-custom/releases)，不会覆盖丢失定制功能 |
| **侧栏目录正序** | 目录按数字升序排列（0-个人文件 … 9-收件箱），仍支持拖拽自定义 |

## 迭代记录

1. 到 [Releases](https://github.com/CusuenEu/guiyu-custom/releases/latest) 下载 `guiyu-custom-macOS-arm64.zip`（附 `SHA256SUMS.txt` 与 `changelog.md`）
2. 解压后把 **归屿.app** 拖进「应用程序」
3. 首次打开：**系统设置 → 隐私与安全性 → 仍要打开**（本机自签名构建，未 Apple 公证）

要求 macOS 13+ / Apple Silicon。

## 从源码构建

```sh
./build.sh          # 需要 Swift 6 工具链；首次构建联网拉取 GRDB/Sparkle 依赖
open dist/归屿.app
```

构建脚本自动执行隔离自测，不会改动真实文件。

## 更新与更新日志

- 每次稳定构建由 GitHub Actions（macos-15 / Xcode 16）**自动发布到 [Releases](https://github.com/CusuenEu/guiyu-custom/releases)**，附**自动更新日志**（本次变更的提交清单）、SHA256 校验与安装包
- 上游有新版本时自动合并定制改造后重新构建发布；合并冲突转人工处理
- 应用内「检查更新」按钮只指向本发布页

## 隐私

全本地运行：不上传文件、文件名、搜索词或索引。唯一外联是应用内「AI 生成规则」按你自己配置的密钥调用 MiMo/Kimi，以及打开发布页时的普通网络请求。

## 致谢

感谢原作者 **tiduse1988** 开发并开源归屿（[github.com/tiduse1988/guiyu](https://github.com/tiduse1988/guiyu)）。本仓库仅在原版基础上做个人使用层的功能增强，不改动上游核心逻辑；功能细节与完整设计说明见上游文档。

## 许可证

MIT License，与上游一致，详见 [LICENSE](LICENSE)（Copyright (c) 2026 tiduse1988）。GRDB.swift 与 Sparkle 的许可证随安装包附带。
