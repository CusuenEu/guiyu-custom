# 发布归屿

官方仓库：`tiduse1988/guiyu`。GitHub Releases 同时托管安装包和 `appcast.xml`，不需要云服务器。

## 密钥

官方更新签名私钥存放在维护者 Mac 登录钥匙串，Sparkle account 为 `tiduse1988.guiyu`。仓库只有 `Release/update-public-key.txt` 公钥。请备份钥匙串；不要把私钥、证书或登录令牌提交到仓库。没有这把私钥的构建者可以构建应用，但不能为官方更新通道发布有效更新。首次设置需通过 Sparkle `generate_keys --account tiduse1988.guiyu` 生成；已经存在时不会覆盖。

Fork 必须替换公钥、`build.sh` 内的 SUFeedURL、打包脚本中的发布下载地址及签名 account，防止误用官方通道。

## 每次发布

1. 修改 `build.sh` 的显示版本与单调递增的 CFBundleVersion，并更新 README、编写发行说明。
2. 运行 `./build.sh`，自测及签名验证通过后再继续。只发布在目标架构 Mac 上构建的对应安装包；当前脚本的官方发行目标为 arm64。
3. 运行 `./scripts/prepare-release.sh`。这会打包、生成并签名更新清单、验证清单签名和生成 SHA256 校验值。需要本机钥匙串中的发布私钥。
4. 提交公开源码并推送 main，确认源码与构建一致。使用 `gh release create v版本 --draft --title '归屿 版本' --notes-file 发行说明文件` 创建草稿；上传 `Release/archives/v版本/` 下 ZIP、appcast.xml、SHA256SUMS.txt；核对后执行 `gh release edit v版本 --draft=false --latest`。
5. 从公开发布地址重新下载并检查哈希、签名。使用上一版的隔离测试副本验证检查更新和安装；不要在使用者仍有文件操作窗口时强制结束应用。

正式版检查地址为 `https://github.com/tiduse1988/guiyu/releases/latest/download/appcast.xml`。每个正式 Release 必须包含同名 appcast.xml，不能单独把其他实验 Release 标记 latest。签名清单生成后不得手工修改；任何变化均需重新签名。更新时无需用户 GitHub 账号。

目前采用临时代码签名，尚未 Developer ID 签名/公证。Sparkle Ed25519 签名保证更新真实性，不等于 Apple Gatekeeper 的首次安装认证。未来可升级 Developer ID 分发；需要相应账号、证书和公证过程。

GitHub Actions 只构建和自测，不能在没有发布密钥时自动发布官方更新。自动更新指客户端自动升级，不意味着每次源码提交都会发布。
