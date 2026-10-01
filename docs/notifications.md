# Nextgram 通知排查

## 企业签名不等于推送已配置

企业证书允许安装应用，但不能自动获得 Telegram 官方客户端的推送配置。

远程通知需要同时满足：

1. 签名后的应用、描述文件允许 Push Notifications，并具有有效的 `aps-environment` entitlement。
2. 描述文件、签名及 APNs topic 与实际 Bundle ID 匹配。兼容包使用各自的 Bundle ID 与 `group.<bundle_id>`；签名平台改包名会改变推送目标。
3. Nextgram 使用的 Telegram `api_id` 在应用后台配置了匹配的 APNs 凭据。不要把 `.p12`、私钥或密码提交到仓库。

## 当前通知兼容测试配置

维护者指定了 Nagram、Nicegram、OLAI、Turrit 四种 Bundle ID 与配套 Telegram API 配置，详见 [README 安装包选择表](../README.md#build-ipa-with-github-actions)。Actions 从 `build-system/nextgram-variants.json` 读取每种包的 API ID，并从独立的 `NAGRAM_API_HASH`、`NICEGRAM_API_HASH`、`OLAI_API_HASH`、`TURRIT_API_HASH` Secrets 读取配套 Hash；不再使用旧的 `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` Secrets。

App Group 已由 `Telegram/BUILD` 中的 `group.{telegram_bundle_id}` 模板生成，无需修改所有共享容器调用。企业重签后仍需核对最终描述文件和签名权限；源 IPA 的声明不代表重签工具保留了对应能力。这些配置尚未证明适用于任意企业证书，不保证通知恢复，也不代表相关客户端的授权或背书。

每种兼容包与对应原版使用同一 Bundle ID，安装时可能覆盖原版或发生冲突；请选择未安装对应原版的包。请保留旧应用与重要本地数据；这些包不是 `jp.foxtea.nextgram` 的原位更新，不同包名也不会自动迁移账号与缓存。四种包都保留 Nextgram 名称、图标与功能，变体名称仅用于区分兼容配置。

本仓库发布的是供重签的主应用 IPA，不包含通知扩展。没有扩展主要影响通知解密及丰富内容，并非系统横幅的唯一前提。客户端代码无法替代服务器端 APNs 配置。

参考：[Telegram 推送文档](https://core.telegram.org/api/push-updates)、[Apple 注册远程通知](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)。

## 不依赖 APNs 的本地通知兜底

在 Nextgram 设置 → 其他中开启“本地通知兜底”，允许系统通知，并在系统设置中允许 Nextgram **始终**访问位置。Nextgram 使用后台定位尽量保持所有登录账号的消息连接，再按聊天静音、预览隐私和锁定状态生成本地通知。

这不是远程推送的等价替代：会增加耗电，强制结束应用、定位被拒绝、网络中断或 iOS 挂起进程后均无法保证收到通知。有正常 APNs 推送时建议关闭兜底，以免重复提醒。

## 诊断顺序

1. 打开 Nextgram 设置 → 其他 → 通知诊断，发送测试通知。五秒后应出现系统通知；通知摘要、专注模式、静音设置也会影响显示和声音。
2. 测试通知都不出现时，检查系统通知权限、横幅、锁屏通知和专注模式。测试成功只证明系统本地通知可用，不证明远程 APNs 已配置。
3. 开启兜底并确认始终定位权限，将应用留在后台，不要从多任务界面划掉。用其他账号发送一条未静音私聊消息，再分别测试锁屏和其他已登录账号。
4. 本地测试正常、后台消息仍无提醒时，记录诊断页状态、系统版本、签名工具和实际包名反馈。无需提供证书或私钥。
