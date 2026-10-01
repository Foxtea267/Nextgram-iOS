<p align="center">
  <img src="logo.png" width="160" alt="Nextgram Logo">
</p>

<h1 align="center">Nextgram-iOS</h1>

<p align="center">
  An enhanced third-party Telegram client for iOS.
</p>

<p align="center">
  Based on <a href="https://github.com/TelegramMessenger/Telegram-iOS">Telegram-iOS</a>
  and <a href="https://github.com/NextAlone/Nagram-iOS">Nagram-iOS</a>.
</p>

<p align="center">
  <a href="https://t.me/Nextgram_Chat">
    <img src="https://img.shields.io/badge/Telegram-加入群组-26A5E4?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram">
  </a>
</p>

---

## About

Nextgram-iOS 是一个基于 Telegram 官方 iOS 客户端与 Nagram-iOS 开发的第三方增强客户端。在尽量保持 Telegram 原有体验和上游可同步性的基础上，加入消息保留、隐私增强和客户端自定义功能。

## Features

### Message

- 删除消息拦截：在服务端删除更新落库前保留本地消息，并以半透明样式显示“已删除”标记；支持聊天/发送者黑白名单与关键词排除。
- 已删除消息标识可选文字、小垃圾桶或两者同时显示，并支持十六进制自定义颜色。
- 已删除消息归档：可按账号导入、导出保留消息的数据库记录（媒体文件仍依赖本机缓存）。
- 保存机器人消息：保留 Bot 私聊或 Bot 作者被远程删除的消息。
- 消息编辑历史：最多保存 20 个文本版本，可从消息长按菜单查看。
- 强制复制受保护消息。
- 可配置消息上下文菜单和双击消息动作。
- 正则消息过滤。
- 发送消息默认格式：普通、粗体、斜体、等宽、下划线、删除线或剧透；保留手动格式，不改动转发。等宽格式遇到链接、提及或自定义表情时保留原样，避免实体重叠。

### Privacy

- 幽灵模式：统一阻止已读、输入中和在线状态上报。
- 已读、输入状态和在线状态也可以分别控制。
- 隐藏手机号及其他隐私增强选项。
- 可选解除 Nextgram 本地的 iOS 频道与消息显示限制；Telegram 未下发、地区封禁或已移除的内容不在此范围内。

### Interface

- 独立 Nextgram 设置页面，直接展示全部设置并支持搜索。
- 点击聊天页顶部“聊天”可打开玻璃风格的组合筛选页；已读状态单选、会话类型多选，支持私聊及群组＋频道快捷组合，也可选择排序。点击“完成”才应用，“取消”保留原结果，“重置”恢复默认显示和排序。
- 聊天搜索页可在显示顶部最近联系人时隐藏下方重复的最近搜索列表。
- 会话支持未读优先或最旧优先排序，同时保持置顶顺序。
- 显示用户、群组和频道 ID，以及 Telegram DC。
- 消息时间戳显示秒、自定义贴纸尺寸等界面选项。
- 自动删除时长默认显示在聊天头像右下角；点击可选择时长，无管理权限时显示说明，也可在设置中恢复原生输入框样式。
- 独立 Nextgram 应用名称与图标。

### More

- 可在“其他”中开启账号登录数量无上限；默认沿用 Nagram 的 10 个账号上限。
- 本地大会员：解锁客户端 Premium 界面与本地额度判断；服务器额度、付费功能及账号真实 Premium 状态仍由 Telegram 校验。
- 本地通知兜底：无需 APNs，使用后台定位尽量保持消息连接并生成本地通知；需要允许“始终”访问位置，会增加耗电，强制结束或被 iOS 挂起后无法保证通知。
- 通知诊断与五秒测试通知：查看系统通知、始终定位、APNs 设备注册和本地通知状态。企业签名的推送配置与排查步骤见 [通知说明](docs/notifications.md)。
- Telegram 服务器延迟测试：测量当前连接的真实 RPC 往返时间（包含当前代理和网络连接延迟），十秒超时报错。
- 后台定位胶囊可选择始终显示、所有场景关闭、仅主页关闭或仅聊天页面关闭。
- 翻译增强与 LLM / AI 集成。
- 音乐播放列表支持搜索，并可配置文件大小和封面右下角下载状态提示。
- 盘古之白。
- 更多功能持续开发中。

> [!NOTE]
> 消息保留和编辑历史从对应开关启用后开始生效。媒体能否继续查看取决于本地缓存。

## 使用协议

首次打开 Nextgram 时会提示阅读使用协议。继续使用前，请阅读 [Nextgram 使用协议](USAGE_AGREEMENT.md)。

## AyuGram-like Features

Nextgram 提供部分与 AyuGram 类似的功能体验，包括 Anti-Delete Messages、Bot Message Preservation、Message Edit History、Ghost Mode、Read Status Control 和 Online Status Privacy。

> [!NOTE]
> Nextgram **不是** AyuGram 的官方 iOS 版本，与 AyuGram 项目不存在官方隶属、授权或背书关系。

## Development

Nextgram 自身的增强代码应尽可能放在仓库根目录的 `Nagram/` 中。内部 `Nagram*` 模块名和设置键保持稳定，以降低同步 Nagram-iOS 与 Telegram-iOS 上游时的冲突。

必须修改 Telegram 上游代码时，在修改位置同时保留以下锚点：

```swift
// MARK: NAGRAM
// MARK: NEXTGRAM
```

同步或切换上游代码后应先同步 Submodule，并确认输出中没有 `+`、`-` 或 `U` 前缀：

```sh
git submodule update --init --recursive
git submodule status --recursive
```

### Build IPA with GitHub Actions

推送到 `main`，或在 GitHub 的 Actions 页面手动运行 **Build Nextgram IPA**。工作流使用 [`build-system/nextgram-variants.json`](build-system/nextgram-variants.json) 生成四种兼容包。构建前必须在仓库的 **Settings → Secrets and variables → Actions** 中保存各 API ID 配套的 Hash：

| 独立安装包 | Bundle ID | API ID | Actions Secret |
| --- | --- | --- | --- |
| `Nextgram-Nagram.ipa` | `xyz.nextalone.nagram` | `37425841` | `NAGRAM_API_HASH` |
| `Nextgram-Nicegram.ipa` | `app.nicegram` | `23697447` | `NICEGRAM_API_HASH` |
| `Nextgram-OLAI.ipa` | `com.olcorporation.olai` | `2033156` | `OLAI_API_HASH` |
| `Nextgram-Turrit.ipa` | `com.seastar.turrit` | `27626847` | `TURRIT_API_HASH` |

API ID 已在变体配置中指定，不再读取旧的 `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` Secrets。Hash 仅保存在对应 Secret 中，不写入源码；缺失或格式错误会终止该变体构建，不会回退到其他客户端配置。

四种包全部构建并校验成功后，统一上传到一个 **Release**，每种 IPA 均可单独下载。运行页面同时保留 `Nextgram-<variant>-<commit>` artifact，包含该 IPA 和可用时生成的 dSYM 压缩包。

四种包的功能、名称、图标和 URL Scheme 均为 Nextgram，仅兼容身份不同；App Group 由各 Bundle ID 生成 `group.<bundle_id>`。请选择手机未安装对应原版的包，例如已安装 Nagram 时选择其他三种。安装同包名应用可能覆盖原版或发生冲突，请先备份重要数据。这些包不是旧包名 `jp.foxtea.nextgram` 的原位更新，账号与本地缓存不会自动迁移；不同兼容包也不共享账号和缓存。

兼容身份来自维护者指定的配置，不代表相关客户端的授权或背书。企业重签后的通知效果仍需真机验证，不保证通知恢复；详见[通知排查](docs/notifications.md)。Release 版本号使用 `YYYYMMDDNNN` 格式，例如 `20260907001`；IPA 内的应用版本使用对应的 `YYYY.MMDD.N` 格式。四种包共用同一版本号，并随每次 Actions 构建更新。Release 说明会列出上一个发布版本以来的提交、版本信息与安装包选择表。

> [!WARNING]
> GitHub Actions 产物只包含主应用；打包时会移除临时签名与 provisioning profile，仅用于后续重签，不能直接安装。请使用自己的证书或签名工具重签 IPA。

### Local builds

Nextgram 使用 Telegram-iOS 的 Bazel 构建系统，统一通过 `build-system/Make/Make.py` 调用。完整签名、免费 Apple ID、模拟器构建和安装说明见 [`docs/build.md`](docs/build.md)。

## Credits

- [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS)
- [Nagram-iOS](https://github.com/NextAlone/Nagram-iOS)

感谢上述项目的开发者与贡献者。

## License & Branding

Telegram-iOS 及其相关代码、资源与商标归对应权利人所有，并继续适用其原有许可证及版权声明。来自 Nagram-iOS 的代码和实现继续适用 Nagram-iOS 自身的许可证及版权声明。

Nextgram 新增代码、设计和项目素材的版权归其对应作者及贡献者所有。Nextgram 名称、Logo、应用图标及其他品牌资产与源码许可相互独立。Fork、修改版或第三方发行版本不应使用可能使用户误认为其属于 Nextgram 官方发行版的名称、Logo 或其他品牌资产。

## Disclaimer

Nextgram is an unofficial Telegram client. Telegram is a trademark of Telegram Messenger Inc.

Nextgram is not affiliated with, endorsed by, or sponsored by Telegram Messenger Inc., Nagram, or AyuGram.
