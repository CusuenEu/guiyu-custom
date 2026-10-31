---
name: 归屿
description: 森林绿导航与浅色原生文件工作空间
colors:
  primary: "rgb(14% 38% 30%)"
  canvas: "#FFFFFF"
  sidebar: "rgb(0% 24.5% 19%)"
  sidebar-selection: "rgb(0% 41% 31.5%)"
  sidebar-text: "rgb(94% 98% 96%)"
  sidebar-muted: "rgb(77% 88% 82%)"
  project-canvas: "rgb(96.4% 98.6% 97.7%)"
  selection: "rgb(87.6% 95.5% 92.5%)"
  settings-rail: "rgb(95% 97.4% 95.8%)"
  settings-action: "rgb(90% 95% 92%)"
  category-section: "rgb(93.5% 97.8% 96.1%)"
  divider: "rgb(89% 93% 91%)"
  ink: "rgb(9% 14% 13%)"
  secondary-text: "rgb(37% 44% 41%)"
typography:
  brand:
    fontFamily: "macOS system rounded"
    fontSize: "22pt"
    fontWeight: 600
  navigation:
    fontFamily: "macOS system rounded"
    fontSize: "15pt"
    fontWeight: 400
  body:
    fontFamily: "macOS system"
    fontSize: "14pt"
    fontWeight: 400
  category:
    fontFamily: "macOS system"
    fontSize: "14pt"
    fontWeight: 600
  control:
    fontFamily: "macOS system rounded"
    fontSize: "13pt"
    fontWeight: 500
  search:
    fontFamily: "macOS system"
    fontSize: "13pt"
    fontWeight: 400
  date:
    fontFamily: "macOS system monospaced digits"
    fontSize: "11pt"
    fontWeight: 400
rounded:
  control: "8pt"
  table-selection: "9pt"
  settings-entry: "10pt"
  navigation: "12pt"
  settings-container: "14pt"
spacing:
  small: "8pt"
  icon-gap: "12pt"
  rail-padding: "16pt"
  pane-padding: "20pt"
  settings-padding: "28pt"
components:
  button-soft:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.control}"
    padding: "0pt 12pt"
    typography: "{typography.control}"
  button-settings-action:
    backgroundColor: "{colors.settings-action}"
    rounded: "{rounded.control}"
    typography: "{typography.control}"
  navigation-active:
    backgroundColor: "{colors.sidebar-selection}"
    textColor: "{colors.sidebar-text}"
    rounded: "{rounded.navigation}"
    height: "48pt"
  search:
    textColor: "{colors.sidebar-text}"
    rounded: "{rounded.control}"
    height: "36pt"
  project-row:
    backgroundColor: "{colors.project-canvas}"
    textColor: "{colors.ink}"
    height: "44pt"
  project-row-two-line:
    backgroundColor: "{colors.project-canvas}"
    textColor: "{colors.ink}"
    height: "60pt"
  file-mode-group:
    height: "38pt"
    width: "238pt"
    rounded: "9pt"
    padding: "3pt"
  file-mode-selected:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.primary}"
    height: "32pt"
    width: "76pt"
    rounded: "7pt"
  project-sort:
    backgroundColor: "{colors.project-canvas}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0pt 12pt"
    height: "32pt"
  file-row:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    height: "52pt"
  category-header:
    backgroundColor: "{colors.category-section}"
    rounded: "{rounded.control}"
    height: "40pt"
---

# Design System: 归屿

## Overview

**Creative North Star: "Forest workspace"**

A native macOS workspace for local project files: a full-height forest rail anchors a pale mint project list and white file browser. The leaf-hood chick, golden folders and colored document glyphs provide the recognizable details; filenames and native interactions carry the work.

Current visual authority is the user-approved V5 vertical category-list composition at `Design/Reference-Workspace-v4/approved-forest-workspace.png`, implemented for version 0.4.1 (build 7). `Design/SoftWorkspace/approved-workspace.png` records the historical 0.4 cream/mint direction; it is no longer the workspace layout reference. The later dense-table, card and studio explorations are not the approved implementation. The existing transparent chick asset remains current. The user-approved `Design/ProjectRow-Alignment-v1/project-rows-preview.png` refines only project-title alignment and adaptive row height in 0.4.3 (build 9); it does not replace the V5 composition. Version 0.4.4 (build 10) further refines toolbar controls, sidebar logo/search presentation and category-header centering within this same native layout.

**Key Characteristics:**

- Dark forest workspace navigation; a separate light settings rail.
- Three resizable native columns, without a global masthead.
- Pale mint project rows and a white, vertically grouped file list.
- Real file hierarchy, native selection, keyboard access and explicit confirmation for file changes.

## Colors

`Sources/WorkspaceTheme.swift` owns workspace colors; `Sources/main.swift` owns the action accent. The frontmatter preserves their fractional RGB channels as percentage RGB rather than rounding them into replacement hex tokens. The approved mockup's nominal forest is #003E30. Code uses the `sidebar` token for the dark workspace rail and `settings-rail` for the light settings sheet; these are deliberately separate surfaces.

The emerald `sidebar-selection` identifies an active directory or archive source. Light `sidebar-text` and `sidebar-muted` retain legibility on the forest rail. `project-canvas` is the center column, `canvas` is the file pane, `selection` is selected table rows and settings navigation, and `category-section` is category-header fill. `ink`, `secondary-text` and `divider` provide native content hierarchy.

Golden folders use the cached AppKit drawing: tab RGB(100%, 76%, 26%), body gradient RGB(100%, 88%, 43%) to RGB(100%, 73%, 20%), with a fine brown outline and white highlight. Word and PDF glyphs use native system blue/red; Excel uses RGB(2%, 55%, 28%). Other file kinds retain system symbols. Icon rendering does not read document contents.

## Typography

Use native macOS system type for Chinese readability. The brand is 22pt semibold rounded; project-directory labels are 15pt rounded. Filenames are regular 14pt, category headings are 14pt semibold, category counts are 12pt, and trailing dates are 11pt with monospaced digits. Search is native 13pt system text; soft controls use 13pt medium rounded text.

Center project names use a 20pt title region in 44pt single-line rows, or a 38pt title region in 60pt two-line rows. The title region and golden folder share the native cell’s vertical center. Native text measurement chooses the height for the available column width, and resizing recomputes wrapping up to two lines. These are delegate row heights; the table retains its separate 1pt vertical intercell spacing. File names use one line with middle truncation in 52pt rows. Full original titles remain available through tooltips. Category headings have 40pt rows; do not compress all three row types to one density.

## Layout

The hidden-titlebar window defaults to 1280×820pt, with a 1060×700pt minimum. A full-height `HSplitView` carries the rail, project/source list and file pane. Initial split positions are applied once: rail width is 16% clamped to 200–250pt and center width is 30.5% clamped to 340–520pt. Subsequent divider drags win. The rail view has 200/220/280pt minimum/ideal/maximum widths; the center minimum is 340pt, and an active file pane minimum is 430pt. Without an active project the blank right content may shrink to zero width.

The rail has 16pt padding. A 54×56pt chick and the brand precede a 36pt search field, then 项目目录 and 可归档目录. Directory rows are at least 48pt; archive-source and bottom settings rows are at least 44pt. The center 56pt toolbar contains Refresh and project sorting, aligned to the right. Both controls have 32pt height; sorting uses a menu with a custom down chevron and hidden system indicator. There is no duplicate year/directory title or global masthead.

The file pane begins with a 56pt toolbar containing three plain SwiftUI buttons, 按类别 / 按时间 / 源文档. Each button is 76×32pt; 2pt gaps and a 3pt inset make the group 238×38pt. The selected button has a white fill and green semibold 13pt text; unselected buttons have clear fill and medium-weight ink text. The group uses a neutral 95%-white fill. In category mode, sections are vertically stacked lists, with empty categories hidden. A compact Up/breadcrumb row appears only inside a nested folder; it remains available in all three modes. A batch-action row appears only when native selection contains more than one entry. No permanent multiselect toggle or ellipsis is added. The temporary category drop-target bar appears during a valid in-app drag.

Selecting a physical directory shows its direct projects and loose files in the center. Selecting Downloads, Recents or a linked source shows that source in the center and leaves right content blank. File modes and actions appear on the right only after selecting a project. The right footer remains separate: it is 32pt tall with local-workspace/busy state and, only for an active project, an entry count. It reports `sourceRows.count`, the current directory's immediate entries, regardless of search filtering or collapsed sections. When no project is selected or an archive source is active, local/busy status remains and the number is hidden. It does not count descendants or category headers.

The settings sheet remains 820×620pt with its independent 174pt light navigation rail and three 44pt navigation rows: 文件位置, 文件分类, 归档记录. The content scrolls independently with 28pt horizontal padding; the fixed 64pt footer retains local-save status and 完成.

## Elevation & Depth

Flat tonal surfaces and native split dividers establish hierarchy. No decorative workspace shadows are introduced. Table rows have a 0.5pt separator starting 52pt from the left, at 55% divider opacity. Soft buttons use a 1pt divider-colored outline at 70% opacity; folder and document icons use small gradients and highlights. Search focus changes its outline, rather than moving the layout.

## Shapes

Navigation selection uses 12pt rounded rectangles. Search, soft buttons and category backgrounds use 8pt corners. The file-mode group uses 9pt corners and its selected button uses 7pt corners. Table selection uses 9pt corners inset 6pt horizontally and 2pt vertically; category backgrounds are inset 12pt horizontally and 3pt vertically. The bottom settings entrance uses 10pt corners; light settings containers may use 14pt corners. These shapes frame native content without turning file groups into cards.

## Components

- **Logo:** `Design/SoftWorkspace/GuiyuCompanion.png` is the transparent leaf-hood chick used in the forest rail and generated application ICNS. Its historical asset directory does not make the 0.4 workspace layout current. Do not place an old logo beside a second mascot.
- **Search:** `SidebarSearchField` wraps an editable AppKit `NSTextField` with explicit light text, a neutral-gray placeholder (white 0.64) and the accessible label 搜索项目或文件. A black 8%-opacity fill sits over the forest rail. The resting 1pt outline uses muted text at 40% opacity; keyboard or pointer focus produces a 2pt light-text outline through the bound native focus state. The field disables its native exterior focus ring (`focusRingType = .none`), keeping the authored outer focus outline and normal text editing/IME behavior.
- **Soft button:** white surface, 12pt horizontal padding and 32pt minimum height. Its historical `peach` variant now uses the pale green `settings-action` fill for sheet actions such as 完成, 添加 or 保存. Pressed opacity is 0.65; disabled opacity is 0.45. The forest bottom-left settings entrance is instead a plain 44pt navigation row on a white 10%-opacity fill.
- **Project rows:** a single-line title and golden folder are vertically centered in the compact row; a wrapped two-line title is centered as one block in the taller row. Available width includes existing icon, gap, padding and optional date space. Resizing invalidates measured heights without filesystem work; full-title tooltips and full-row native selection remain. File rows retain 52pt and category headers 40pt delegate heights.
- **File modes and sorting:** the three file-mode buttons retain the existing mode values and selected accessibility trait. Their fixed geometry is recorded in Layout. The sort menu retains 月份倒序 / 最近修改, with 12pt horizontal padding, 13pt medium text, a 10pt semibold down chevron, pale mint fill, 1pt outline and 8pt corners. Its 32pt height aligns with Refresh.
- **Native file browser:** reusable AppKit table with immediate selection, Cmd/Shift multiselect and private in-app category drag handling. Category headers can expand/collapse and show their entry count. Their 12×12pt chevron and 18pt title/count region share the cell’s vertical center in the unchanged 40pt delegate row. Folder entries remain intact until double-clicked; all modes show only the current directory's immediate files and folders. Batch tools, 全选 and 取消选择 appear when more than one item is selected. The native table supplies context menus, arrows and Cmd-A.
- **Naming and archiving:** right-click recommended/manual naming opens editable confirmation sheets; generating a suggestion does not rename. Candidate naming confirmation, original extensions, identity/version checks and no-overwrite behavior remain required. Quick Archive reads evidence only when invoked and requires a selected project plus confirmation before moving. Browsing, search and Refresh read metadata only.
- **Settings:** the chick marks the light rail and mint identifies its active section. 文件位置 combines project root and archive sources; older inbox selection stays under 更多目录选项. 文件分类 retains search, add, rename and confirmed delete with at least one category. 归档记录 retains up to 30 moves, guarded undo and 查看 for the existing pending-files dialog. Header, footer and 完成 stay outside scrolling content.
- **Directory order:** the forest project-directory rail uses a native AppKit row for private own-process drag and drop. The visible row stays 48pt; its native 66pt target includes the surrounding 18pt gap, with consecutive targets touching and no dead space. The whole row starts dragging after 4pt pointer movement; click and accessible press retain directory navigation. The target uses its actual midpoint and a light insertion line on the dark rail. A 2pt line previews insertion before/after the target row according to pointer position. Hover does not persist; release atomically persists order before publishing. Saved order is scoped to the absolute project-root path and contains absolute directory paths. Refresh/restart retain it, new directories append and missing directories stay hidden. It changes display order only; Finder hierarchy and center project sorting remain independent.
- **Refresh and native shortcuts:** Refresh updates project metadata and the active source without parsing text, naming or archiving. Space toggles system Quick Look, double-click opens/enters, Cmd-O opens, Return renames, and Cmd-Backspace moves to Trash. These file commands apply only while the native file table has focus and no sheet blocks it; search and naming fields retain ordinary editing. Trash undo keeps existing no-overwrite guards.

## Do's and Don'ts

- Do preserve the forest workspace rail and the separate light settings rail.
- Do retain native Space Quick Look, double-click open, Cmd-Backspace Trash, arrows and text-field editing.
- Do keep immediate folder hierarchy, two-line project names, full-row hit areas, resizable columns and confirmation before file changes.
- Do show nested-folder Up and multiple-selection batch actions only in their applicable states.
- Do keep cartoon character in the chick, golden folders and cached document glyphs.
- Don't use the historical SoftWorkspace 0.4 layout or later dense-table, card or studio explorations as current visual authority.
- Don't restore the removed archive header action, right project-title strip or bottom preview/open buttons.
- Don't parse or move documents as a side effect of browsing, search or global Refresh.
