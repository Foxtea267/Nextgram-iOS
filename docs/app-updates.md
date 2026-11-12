# Nextgram 更新

在「设置 → Nextgram → 更新与签名证书」检查新版。更新页读取 [Nextgram 的 GitHub Releases](https://github.com/Foxtea267/Nextgram-iOS/releases)，根据当前 Bundle ID 选择 Nagram、Nicegram、OLAI 或 Turrit 兼容包。可以开启自动检查，每六小时最多在进入前台时检查一次。手动检查无需证书。

下载要求正式发布的四段版本号和 GitHub 提供的 SHA-256。校验文件大小和摘要后，更新器读取 IPA 内的主应用信息，核对 Bundle ID、Nextgram 版本和基础版本。早期单包和改过 Bundle ID 的安装版需要手动选择安装包。

1. 点「导入证书与描述文件」，在「文件」里选一份 `.p12` 或 `.pfx` 和所需的 `.mobileprovision`，然后输入证书密码。当前安装包含匹配的描述文件时，可以只选证书。签名材料存入本机非同步钥匙串。
2. 下载后点「签名更新包」。签名器核对已安装应用及扩展的证书、Bundle ID、URL Scheme 和权限，并沿用已装版本的权限签署新包。身份不符会停止，签名失败可以用同一份原始 IPA 重试。
3. 点「安装更新」。确认后向 LCSign 请求安装清单，发送应用标识、构建号和仅本机可访问的临时地址。签名 IPA 通过 `127.0.0.1` 交给 iOS。证书、密码、描述文件和 IPA 留在设备上。安装器收到 IPA 后，最终结果由 iOS 决定。

校验过的原始 IPA 在重启后可从更新页复用。也可以导出原始 IPA 或已经签名的 IPA。后台下载、签名包跨重启缓存、TrollStore 和灵动岛进度尚未接入。

更新流程参考 [Regram 的更新文档](https://github.com/RegramDev/Regram-ios/blob/master/docs/app-updates.md)。签名使用 Regram 集成的 MIT 授权 [zsign 核心](../Nagram/UpdateSigner/Vendor/zsign/UPSTREAM.md)。签名用 OpenSSL 与 Telegram 的 BoringSSL 通过独立符号隔离。
