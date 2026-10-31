# 本地Mac新增功能同步记录

Git基线：fc632a9ea541e7dd5b9b377144ceb75f139fed82。新增功能取自本地尚未提交的Mac源文件；不是宣称Windows已具备全部Mac能力。

| Mac来源 | Windows实现 |
| --- | --- |
| NamingRules.swift：nameOnly、按字段缺省兼容、动态分类 | src/naming-format.cjs、core.cjs、documents.cjs、main.cjs |
| SmartNamingDialog/SmartDialogComponents：字面编辑、扩展名、空值及Return | src/ui.cjs、naming-format.cjs |
| BatchNaming.swift：共用格式和固定批次日期 | src/main.cjs、documents.cjs、ui.cjs |
| DirectoryBreadcrumb/Workspace/ArchiveSources：项目内层级和路径菜单 | src/navigation.cjs、ui.cjs、style.css |

## 本次读取的Mac源文件SHA-256

- `Sources/NamingRules.swift`：`1ecc564e787a447981bf9e350876e5a2919be86bb7fd8d889bc06b98332ae7ac`
- `Sources/SmartNamingDialog.swift`：`53c57e964bd12916c09290dbd0cc1451db9acc2eb013b8e9bb3281152a599fd8`
- `Sources/SmartDialogComponents.swift`：`d35d7cb687ee900ed98e33db51bac7ff828af8cd4e5175fd7eac9bc5cbf635f8`
- `Sources/DirectoryBreadcrumb.swift`：`fac401c9cdaadb3e9bc580b8e46e5a92571c1cd6851349337357c57d5595033a`
- `Sources/Workspace.swift`：`f68a7a0e75191445aea1885f2969a1db0318afb2c22ee8141707df9fe1c49546`
- `Sources/ArchiveSources.swift`：`464080bd93d1f23d111b988f48bc81d8dfe11aaab4df116a20903f4087a641cd`
- `Sources/BatchNaming.swift`：`6622aa747451e66b12a5077f760e209693f1f8fb326761a6e4481a584b3a071c`

## 第2轮同步

- NamingTitles/NamingReading/NamingSpreadsheet/NamingPolicyTests → title-policy.cjs、documents.cjs、naming-format.cjs、对应标题策略测试：封面优先、两页硬预算、Word300字、Excel表头、无标题原名、完整标题不剥词。
- WindowFramePersistence/WindowFrameTests → window-frame.cjs、main.cjs、window-frame.test.cjs：普通窗口尺寸位置记忆与显示器适配。
- DirectoryBreadcrumb → navigation.cjs、ui.cjs、style.css：点组件归一化、透明路径链接及当前层滚动。
- Workspace/ArchiveSources/CategoryDisclosureReview/ArchiveSourceLayoutReview → ui.cjs、index.html、style.css：来源在中栏的普通列表、共享工具栏、右侧空白、12px旋转细箭头。

本轮全部本地Mac源文件和产品文档指纹见Mac-source-manifest.json，便于后续逐文件对比；未覆盖或修改Mac文件。最新验证范围以VALIDATION.md末节为准，不能把这轮隔离检查称为Windows真机验收。
