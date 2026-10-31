# Product
<!-- impeccable:product-schema 1 -->
## Platform
macOS native desktop
## Stack
Delegated by user: SwiftUI, AppKit, PDFKit, local file system. No cloud dependencies.
## Users
Single local user doing project-based work in Chinese.
## Product Purpose
Find, preview and open files for editing; classify downloaded files into existing project folders.
## Capabilities and Constraints
User confirmed Word, Excel, PDF, images and text. Keep original folders. Offline. No overwrite. No timed polling or startup Downloads scan. Archive sources are read on explicit browsing or refresh. Quick Archive reads document evidence only when invoked; the user chooses a project and confirms before moving files. Arrival/modified/name sorting and navigable archive timeline are required. Project directory chosen in app; no production data supplied.
## Brand Commitments
User approved the V5 forest native Mac workspace: full-height dark forest navigation, pale mint center project list and white file pane with vertical category lists. The transparent leaf-hood chick remains the rail and application logo. Settings retains its separate light rail.

## Lightweight browsing requirement
User clarified: app is a Finder-style presentation layer; naming and archiving are its core. Browsing reads metadata only. No automatic whole-library text extraction/OCR. Parse documents only on explicit naming or archive actions. Search defaults to names/paths. Native immediate selection and guarded preview reloads.

## Workspace and naming invariants
Physical directories left, project folders center (no location), files right grouped into proposal/tender/bid/other, switch to time or original hierarchy. No format-text column. Candidate naming confirmation is mandatory before physical rename. Folder names require x月 + tender project name, else proposal title, else unit + key proposal; document filenames prefer own heading and preserve extension. Month remains editable. All parsing is on demand.

## Current-directory invariant
User explicitly requires ALL three right-pane modes to operate on exactly the current directory’s immediate files and folders. Never flatten B to its descendants. Double-click B to enter in every mode; up navigation in every mode. Empty categories hidden. Project sort confirmed: month prefix descending, then folder modification date descending within month.

## Physical-directory navigation
The sidebar reads actual direct child folders of the selected project root, regardless of names; there is no year classifier or synthetic ungrouped bucket. CD类项目 must appear as CD类项目. Center lists the selected directory's direct project folders and loose documents. Right shows only a selected project's immediate entries. Reuse text caches without retaining an outdated project owner.

## Approved forest workspace · 0.4.1 (7)
Current visual authority: `Design/Reference-Workspace-v4/approved-forest-workspace.png` (the user-selected V5 vertical category-list composition). The cream/mint `Design/SoftWorkspace/approved-workspace.png` is historical 0.4; later dense-table, cards and studio explorations are not the implementation reference. The chick-only logo `Design/SoftWorkspace/GuiyuCompanion.png` remains current.

The native three-column layout is resizable. The forest rail contains branding, native project/file-name search with visible keyboard focus, real project directories, archive sources and bottom-left Settings. Center project names support two lines. Refresh and project sorting share the 56pt center toolbar. Right starts with the three file modes and vertically stacked lists; Up appears only inside nested folders, and batch tools appear only after multiple native selections. Right content stays blank when selecting an archive source or before selecting a project. The right footer retains local/busy status and, for an active project, the count of its current directory's immediate entries; search/collapse does not change that count. With no selected project or an active archive source, the footer retains local/busy status and hides the count.

Project root selection remains inside Settings, whose three sections and light navigation rail stay independent of the dark workspace rail. Do not restore Check Downloads/Archive in a global header, the right project-title/recommended-name strip, or preview/open footer buttons. Native Space preview, double-click open and existing Finder-style keyboard operations remain. Refresh reads metadata and reloads the active source; it must not trigger archiving or text extraction. Directory drag ordering changes only the local display order, persists per absolute project-root path and leaves physical folders and project month sorting intact.

## Indexed filename search · 0.4.2 (8)
GRDB.swift 7.6.1 is statically packaged, with no runtime service or network requirement. The disposable search-index-v1.sqlite holds normalized names, paths, ownership and 2/3-scalar postings only, never document bodies. Metadata publications update the index in a background queue, replacing old roots and deleting obsolete entries. No filesystem watcher or scheduled scan is added. Search stays within the selected physical directory. Whitespace-separated terms use AND substring matching, including short Chinese terms; project/loose-document relevance tiers preserve existing sort order within a tier. The right pane only filters its explicit immediate entries and keeps its existing presentation mode. Downloads/Recents remain outside this project index scope.

Typing is coalesced for 50ms, obsolete requests are cancelled and generation-checked before publishing. Matching, grouping and sorting use immutable background snapshots; ordinary empty-query browsing bypasses index work. Native IME marked text remains editable until committed. The cache may rebuild after corruption; disk failure uses a background name-only memory fallback. There is no pinyin, typo correction or body search.

## Project-title alignment refinement · 0.4.3 (9)
User approved `Design/ProjectRow-Alignment-v1/project-rows-preview.png` as a scoped refinement of the existing forest workspace. Single-line project titles and their golden folder share a vertical center; two-line titles are centered as a block. Native measured text selects 44pt/60pt delegate row heights with 20pt/38pt title regions, recomputed when the project column is resized. The existing 1pt table intercell spacing remains separate. File rows remain 52pt and category headers 40pt. This changes presentation only; native interactions, directory structure, indexed filename search, sorting, naming and archiving rules remain as specified above.

## Workspace control refinement · 0.4.4 (10)
The same native workspace uses three plain 76×32pt file-mode buttons with 2pt gaps and 3pt inset (238×38pt group) inside the existing 56pt toolbar. Selection is white with green semibold text; mode values and behavior remain unchanged. The project-sort menu uses a custom down chevron and 32pt control height aligned with Refresh. The rail chick is 54×56pt. Search retains its authored focus outline and native editing/IME, disables the exterior native focus ring and uses a neutral-gray placeholder (white 0.64). Category headers retain 40pt delegate rows, with centered 12×12pt chevrons and 18pt title regions. Project-row measurement remains 44pt/60pt with 20pt/38pt title regions. Search logic, file hierarchy, sorting rules and all naming/archive guards remain as specified above.

## GitHub distribution and updates · 0.5.0 (12)
Public MIT source and Apple Silicon macOS releases are hosted at tiduse1988/guiyu. Sparkle 2.10.1 checks the signed GitHub Releases appcast daily by default and can download/install updates automatically. The app menu exposes manual checking and both automatic preferences. Runtime preference changes are owned by Sparkle. Both the feed and archives require Ed25519 verification, and anonymous system profiling is disabled. Keys remain in the maintainer's local Keychain; only the public key ships. No file contents, names, queries or index are sent in update checks; normal network metadata and compatibility versions reach GitHub. File management remains local/offline; update retrieval requires network. Current distribution uses ad-hoc code signing, without Developer ID/notarization; initial installation may require macOS approval. Pre-0.5 versions need one manual upgrade. Source/asset commits exclude local project data, caches, review captures and unrelated video work.
