# Nextgram 更新

在「设置 → Nextgram → 其他 → Nextgram 更新」手动检查新版。更新页读取 [Nextgram 的 GitHub Releases](https://github.com/Foxtea267/Nextgram-iOS/releases)，根据当前 Bundle ID 选择 Nagram、Nicegram、OLAI 或 Turrit 兼容包。

下载要求正式发布的四段版本号和 GitHub 提供的 SHA-256。校验文件大小和摘要后，更新器读取 IPA 内的主应用信息，核对 Bundle ID、Nextgram 版本和基础版本。早期单包和改过 Bundle ID 的安装版需要手动选择安装包。

下载完成后可以把 IPA 保存到「文件」，交给已有的签名工具处理。应用内证书导入、重签和覆盖安装尚未接入。

更新流程参考 [Regram 的更新文档](https://github.com/RegramDev/Regram-ios/blob/master/docs/app-updates.md)。
