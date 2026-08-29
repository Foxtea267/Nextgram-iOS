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

<div align="center">
<p align="center">
  <a href="https://t.me/Nextgram_Chat">
    <img src="https://img.shields.io/badge/Telegram-加入群组-26A5E4?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram">
  </a>
</p>
</div>

---

## About

Nextgram-iOS 是一个基于 Telegram 官方 iOS 客户端与 Nagram-iOS 开发的第三方增强客户端。

项目在尽量保持 Telegram 原有体验以及上游可同步性的基础上，加入更多消息保留、隐私增强和客户端自定义功能。

Nextgram 同时计划实现一系列类似 AyuGram 的高级功能，例如反撤回、机器人消息保留、消息编辑历史与幽灵模式等。

## Features

### Message

- 反撤回
- 保存机器人消息
- 保存消息编辑历史
- 强制复制受保护消息
- 更多消息上下文菜单操作
- 自定义双击消息动作
- 正则消息过滤

### Privacy

- 幽灵模式
- 已读状态控制
- 在线状态相关隐私控制
- 隐藏手机号
- 更多隐私增强选项

### Interface

- 独立 Nextgram 设置页面
- 显示用户 / 群组 / 频道 ID
- 显示 Telegram DC
- 消息时间戳显示秒
- 自定义贴纸尺寸
- Nextgram 自定义应用名称与图标

### More

- 翻译增强
- LLM / AI 集成
- 盘古之白
- 更多功能持续开发中

> ⚠️ 部分功能仍处于开发阶段，实际功能以当前版本为准。

## AyuGram-like Features

Nextgram 计划为 iOS 提供部分与 AyuGram 类似的功能体验，包括：

- Anti-Delete Messages
- Bot Message Preservation
- Message Edit History
- Ghost Mode
- Read Status Control
- Online Status Privacy
- Extended Message Actions

> [!NOTE]
> Nextgram **不是** AyuGram 的官方 iOS 版本，与 AyuGram 项目不存在官方隶属、授权或背书关系。

---

## Development

### 代码结构

Nextgram 基于以下两个上游项目：

- [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS)
- [Nagram-iOS](https://github.com/NextAlone/Nagram-iOS)

Nextgram 自身的增强代码应**尽可能与 Telegram 上游代码分离**，减少未来同步上游时的冲突。

当必须修改 Telegram 上游代码时，请使用以下锚点标记修改位置，便于后续同步 Telegram-iOS 上游：

```swift
// MARK: NEXTGRAM
// 你的增强代码放在这里
// MARK: NEXTGRAM
```

### 上游同步

每次 `rebase` 或 `checkout` Telegram-iOS 上游后，**先同步 Submodule**，否则可能出现 `tgcalls` 缺文件、WebRTC / FFmpeg API 不匹配等"假错误"：

```sh
git submodule update --init --recursive
git submodule status --recursive
```

> 📌 确认 `git submodule status` 输出中**没有** `+`、`-` 或 `U` 前缀。

---

### 构建说明

Nextgram-iOS 使用 Telegram-iOS 原有的 **Bazel** 构建系统，统一通过 `build-system/Make/Make.py` 调用。

构建的目标（Target）为：

```
Telegram/Telegram
```

#### 选择签名模式

`local.bazelrc` 是本机配置（已被 gitignore）。不同构建目标对应不同的签名配置：

| 模式 | Provisioning 状态 | `local.bazelrc` 是否允许禁用扩展 |
| --- | --- | --- |
| 完整签名真机包 | 主 App + 6 个扩展都有 Profile | ❌ 不允许 `disableExtensions` |
| 免费 Apple ID 自签 | 通常只有主 App Profile | ✅ 可写 `disableExtensions` |
| 模拟器（免签） | 不需要 Profile | ✅ 可同时写 `disableExtensions` 与 `disableProvisioningProfiles` |

> [!WARNING]
> - 真机构建**不要**加入 `build --//Telegram:disableProvisioningProfiles`，否则主 App 签名会走 `None` 分支。
> - 完整签名环境下应保持 Telegram 的所有扩展启用，包括：
>   `Share`、`NotificationContent`、`NotificationService`、`Intents`、`Widget`、`BroadcastUpload`

---

#### ① 真机构建（完整签名 / Full Provisioning）

`local.bazelrc` 中不应包含任何 `disableExtensions` / `disableProvisioningProfiles`。

构建：

```sh
source ~/.zshrc 2>/dev/null
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-input/local-configuration.json \
  --codesigningInformationPath build-input/codesigning-development \
  --buildNumber=1 \
  --configuration=debug_arm64 \
  --continueOnError
```

IPA 输出路径：

```
bazel-bin/Telegram/Telegram.ipa
```

---

#### ② 真机构建（免费 Apple ID 自签）

免费 Apple ID 通常无法为 Telegram 的所有扩展创建 Provisioning Profile，因此可以在 `local.bazelrc` 中加入：

```
build --//Telegram:disableExtensions
```

> [!WARNING]
> 真机构建**不要**加入 `build --//Telegram:disableProvisioningProfiles`。

构建命令：

```bash
source ~/.zshrc 2>/dev/null
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-input/local-configuration.json \
  --codesigningInformationPath build-input/codesigning-development \
  --xcodeManagedCodesigning \
  --buildNumber=1 \
  --configuration=debug_arm64 \
  --continueOnError
```

---

#### ③ 模拟器构建（Simulator）

模拟器可以在 `local.bazelrc` 中同时使用：

```sh
build --//Telegram:disableProvisioningProfiles
build --//Telegram:disableExtensions
```

构建命令：

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning \
  --buildNumber=1 \
  --configuration=debug_sim_arm64 \
  --continueOnError
```

---

> 📖 更多构建、签名以及 Bazel 相关问题请查看 [`docs/build.md`](docs/build.md)。

---

## Credits

Nextgram-iOS is based on the following projects:

- [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS)
- [Nagram-iOS](https://github.com/NextAlone/Nagram-iOS)

Thanks to their developers and contributors.

## License & Branding

Telegram-iOS 及其相关代码、资源与商标归对应权利人所有，并继续适用其原有许可证及版权声明。

来自 Nagram-iOS 的代码和实现继续适用 Nagram-iOS 自身的许可证及版权声明。

Nextgram 新增代码、设计和项目素材的版权归其对应作者及贡献者所有。

Nextgram 名称、Logo、应用图标及其他品牌资产与源码许可相互独立。

Fork、修改版或第三方发行版本不应使用可能使用户误认为其属于 Nextgram 官方发行版的名称、Logo 或其他品牌资产。

## Disclaimer

Nextgram is an unofficial Telegram client.

Telegram is a trademark of Telegram Messenger Inc.

Nextgram is not affiliated with, endorsed by, or sponsored by Telegram Messenger Inc., Nagram, or AyuGram.
```

---

I've restructured the README, with the main improvements centered on the **Development** section:

## Key changes made

**Structure & clarity in Development section:**
- Broke the "一坨" (single dense blob) into clear sub-sections: **代码结构 → 上游同步 → 构建说明 → 三种签名模式**
- Turned the three messy build scenarios (Full provisioning / Free Apple ID / Simulator) into numbered, separated blocks (`① ② ③`) with their own headers

**More markdown formatting:**
- Added a **table** comparing the three signing modes (provisioning status vs whether extensions can be disabled)
- Put all commands in proper **fenced code blocks** with `sh`/`bash` language hints
- Used markdown **admonitions** (`> [!NOTE]`, `> [!WARNING]`, `> ⚠️`) for the important caveats that were previously just plain text, making them stand out
- Used a bulleted list + `// MARK: NEXTGRAM` code block for the anchoring convention
- Replaced loose plain lines with clearer lists and separators (`---`)

**Minor cleanup elsewhere:**
- Added `[!NOTE]` callout for the AyuGram non-affiliation disclaimer
- Standardized list markers (`*` → `-`)
- Made credit/feature lists slightly cleaner

⚠️ One thing to check on your end: I noticed a possible typo in the original — `--configurationPath build-input/local-configuration.json` appeared in both the full provisioning and free Apple ID builds, but these likely differ (full provisioning typically uses a different config path). I kept them as you provided, but you may want to verify the correct `--configurationPath` for each build scenario.

**Note on citations:** All the technical content above came directly from your own README and the upstream reference material, so I didn't attach external source citations — the markdown restructuring is based on the content you provided and the Standard GitHub-flavored markdown conventions.
