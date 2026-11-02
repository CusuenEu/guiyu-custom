# 发布归屿

官方仓库：`tiduse1988/guiyu`。GitHub Releases 同时托管安装包和 `appcast.xml`，不需要云服务器。

## 密钥

官方更新签名私钥存放在维护者 Mac 登录钥匙串，Sparkle account 为 `tiduse1988.guiyu`。仓库只有 `Release/update-public-key.txt` 公钥。请备份钥匙串；不要把私钥、证书或登录令牌提交到仓库。没有这把私钥的构建者可以构建应用，但不能为官方更新通道发布有效更新。首次设置需通过 Sparkle `generate_keys --account tiduse1988.guiyu` 生成；已经存在时不会覆盖。

Fork 必须替换公钥、`build.sh` 内的 SUFeedURL、打包脚本中的发布下载地址及签名 account，防止误用官方通道。

## 每次发布

1. 发布新版本前运行 `python3 scripts/version.py --next`（可用 `--date YYYYMMDD` 显式指定北京时间日期），然后更新 README、编写发行说明。`Release/version.json` 是唯一版本来源；同日递增序号、换日回到01，重新构建不会自动增加序号。显示版本例如 `20261031(01)`，内部数字构建号例如 `20261031.1`，GitHub 标签为 `v20261031-01`。
2. 运行 `./build.sh`，自测及签名验证通过后再继续。只发布在目标架构 Mac 上构建的对应安装包；当前脚本的官方发行目标为 arm64。
3. 运行 `./scripts/prepare-release.sh`。这会打包、生成并签名更新清单、验证清单签名和生成 SHA256 校验值。需要本机钥匙串中的发布私钥。
4. 提交公开源码并推送 main，确认源码与构建一致。使用 `gh release create v20261031-01 --draft --title '归屿 20261031(01)' --notes-file 发行说明文件` 创建草稿；上传 `Release/archives/v20261031-01/` 下 ZIP、appcast.xml、SHA256SUMS.txt；核对后执行 `gh release edit v20261031-01 --draft=false --latest`。
5. 从公开发布地址重新下载并检查哈希、签名。使用上一版的隔离测试副本验证检查更新和安装；不要在使用者仍有文件操作窗口时强制结束应用。

macOS 正式版检查地址为 `https://github.com/tiduse1988/guiyu/releases/latest/download/appcast.xml`。每个 macOS 正式 Release 必须包含同名 appcast.xml，不能单独把其他平台 Release 标记 latest。签名清单生成后不得手工修改；任何变化均需重新签名。更新时无需用户 GitHub 账号。

目前采用临时代码签名，尚未 Developer ID 签名/公证。Sparkle Ed25519 签名保证更新真实性，不等于 Apple Gatekeeper 的首次安装认证。未来可升级 Developer ID 分发；需要相应账号、证书和公证过程。

GitHub Actions 只构建和自测，不能在没有发布密钥时自动发布官方更新。自动更新指客户端自动升级，不意味着每次源码提交都会发布。

## Windows 发布

Windows 独立使用 `Windows/version.json`，不要修改 macOS 的 `Release/version.json`。升级该文件的日期和序号后，运行 `node Windows/scripts/version.cjs` 同步程序元数据，更新 `Windows/RELEASE-NOTES.md`。新包名为 `Guiyu-日期-序号-Windows-ia32/x64.zip` 和对应 `-setup.exe`，不带测试标记。

推送代码后，等待 Windows validation 的 x86、x64 测试、安装包集成检查和打包全部成功。安装包检查在临时 Windows runner 安装两种程序，核对桌面图标、文件／文件夹的两项右键菜单及卸载清理。原生文件剪贴板测试在两个架构中运行；完整用户桌面交互仍需设备验收。

发布时手动运行 `Publish Windows` 工作流，传入本次成功的 Windows validation run ID。工作流验证构建来源必须是当前 main 的同一提交，使用该次四个构建产物，不重新构建；生成 SHA256SUMS.txt，先创建草稿、核对资产数，再发布 `windows-日期-序号` 的非预发布版本。Windows Release 始终使用 `--latest=false`，保持 Mac latest 与 Sparkle feed 不变；Windows 程序按发行列表及自身版本检查更新，不使用 Mac latest。

发布完成后将首页“下载与安装”表格的 Windows 安装包、解压包及发行记录链接更新为实际可下载的文件，并核验公开链接。不要把已发布的历史包改名来冒充新构建。
