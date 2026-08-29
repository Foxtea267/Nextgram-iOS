Nextgram-iOS

<p align="center">
  <img src="logo.png" width="180" alt="Nextgram Logo">
</p>
<p align="center">
  <strong>基于 Telegram 官方 iOS 客户端与 Nagram-iOS 的第三方增强 Telegram 客户端。</strong>
</p>

Nextgram-iOS 基于 Telegram-iOS 官方源码及 Nagram-iOS 项目开发，在保留 Telegram 原有使用体验的基础上，加入更多消息保留、隐私增强与高级交互功能。

项目说明

Nextgram 面向希望在 iOS 上获得更完整 Telegram 使用体验的用户。

项目基于 Telegram-iOS 官方客户端，并继承 Nagram-iOS 的部分增强功能与项目结构。在此基础上，Nextgram 进一步加入类似 AyuGram 的消息保留、编辑历史与隐私相关功能。

增强功能相关代码尽量集中管理。需要侵入 Telegram 上游源码的修改应使用明确的 Nextgram 标记，方便后续同步 Telegram-iOS 上游版本。

建议统一使用：

// MARK: NEXTGRAM

作为 Nextgram 对上游代码修改的锚点。

设置页面提供独立的 Nextgram 设置入口，用于管理隐私、消息、界面以及其他增强功能。

已实现 / 计划支持功能

功能	说明
反撤回	对方删除消息后，在本地尽可能保留原消息内容
保存机器人消息	Bot 删除或修改消息后，保留之前已经收到的内容
消息编辑历史	保存消息修改前的版本，并允许查看历史编辑内容
幽灵模式	提供类似 AyuGram Ghost Mode 的隐私增强能力
强制复制	在开启内容保护、禁止复制或禁止转发的对话中仍可复制消息文本
Nextgram 设置中心	增强功能集中放置在独立设置页面
自定义应用名称与图标	使用 Nextgram 自有名称、Logo 与应用图标
已读状态控制	提供更细粒度的消息已读行为控制
在线状态隐私	减少部分客户端行为导致的在线状态暴露
消息交互增强	扩展消息上下文菜单、手势及快捷操作
显示 ID / DC	在界面中显示用户、群组、频道 ID 及 Telegram DC 信息
时间戳显秒	消息时间支持显示秒
隐藏手机号	提供额外的手机号显示控制
贴纸尺寸	自定义部分贴纸显示尺寸
翻译	计划加入更多翻译相关能力
LLM / AI	计划加入 LLM / AI 相关功能
正则消息过滤	根据正则表达式过滤或处理消息
盘古之白	自动优化中文与英文、数字之间的排版

部分功能可能仍处于开发阶段，实际可用功能以当前版本为准。

AyuGram 类功能

Nextgram 计划在 iOS 平台提供一组类似 AyuGram 的高级功能，包括但不限于：

* 反撤回
* Bot 消息保留
* 消息编辑历史
* Ghost Mode / 幽灵模式
* 已读状态控制
* 在线状态相关隐私控制
* 更自由的消息复制与保存
* 更多消息上下文菜单操作
* 消息行为与隐私增强

Nextgram 不是 AyuGram 官方 iOS 版本，与 AyuGram 项目不存在官方隶属、授权或背书关系。

这里提及 AyuGram 仅用于描述部分功能方向与使用体验上的相似性。

上游项目

Nextgram-iOS 主要基于以下项目开发：

* Telegram-iOS
    Telegram 官方 iOS 客户端源码。
* Nagram-iOS
    基于 Telegram-iOS 开发的第三方增强客户端项目。

Nextgram 会尽可能保持与 Telegram-iOS 上游的可同步性，同时继承 Nagram-iOS 中适合 Nextgram 的增强实现，并继续加入 Nextgram 自身功能。

Logo

Nextgram Logo 位于仓库根目录：

logo.png

README 顶部直接引用该文件：

<img src="logo.png" width="180" alt="Nextgram Logo">

版权与品牌

* Telegram-iOS： Telegram 官方源码、名称及相关资产版权归其对应权利人所有，并继续适用 Telegram-iOS 原有许可、版权声明及相关政策。
* Nagram-iOS： 来自 Nagram-iOS 的源码、实现及项目素材继续适用 Nagram-iOS 项目自身的许可证、版权声明及品牌政策。
* Nextgram-iOS： Nextgram 新增代码、设计及项目素材版权归其对应作者及贡献者所有。
* Nextgram 品牌： Nextgram 名称、Logo、应用图标及其他项目品牌资产与源码许可相互独立。

修改版、Fork 或第三方发行版本不应使用可能使用户误认为其属于 Nextgram 官方发行版的名称、Logo 或其他品牌资产。

Nextgram 是非官方 Telegram 客户端，与 Telegram Messenger Inc. 不存在官方隶属、授权或背书关系。

⸻

构建

Nextgram-iOS 通过 Bazel 构建，并统一使用 Telegram-iOS 提供的：

build-system/Make/Make.py

包装脚本。

Telegram-iOS 不支持只编译 Nextgram 增强模块，需要整体构建：

Telegram/Telegram

命令末尾的：

--continueOnError

会透传 Bazel 的：

--keep_going

适合在进行大范围修改后一次性暴露更多编译错误。

当前打包问题、Xcode / Bazel 环境约束及相关编译记录见：

docs/build.md

同步 Submodule

每次 rebase / checkout Telegram-iOS 上游后，应首先同步 submodule。

git submodule update --init --recursive
git submodule status --recursive

确认：

git submodule status --recursive

输出中不存在：

+
-
U

前缀。

否则可能出现：

* tgcalls 文件缺失
* WebRTC API 不匹配
* FFmpeg API 不匹配
* 其他与 Nextgram 修改无关的假编译错误

⸻

先选择签名模式

local.bazelrc 是本机配置文件，应保持在 .gitignore 中。

仓库根 .bazelrc 会通过：

try-import %workspace%/local.bazelrc

加载本机 Bazel 配置。

注意：

bazel clean --expunge

以及：

python3 build-system/Make/Make.py clean

可能删除部分本地生成配置。

清理后需要按照当前签名模式重新检查或生成相关文件。

模式	Provisioning 状态	是否允许禁用 Extensions
正式 / 完整签名真机包	主 App + 所需 Extensions 都有 Profile	不允许
免费 Apple ID 自签	通常只有主 App Profile	可以
模拟器免签	不需要 Profile	可以

硬规则

* 使用正式 / 完整 Provisioning Profiles 时必须启用所需 Extensions。
* 真机包不要使用 build --//Telegram:disableProvisioningProfiles。
* Make.py build 不接受 --disableProvisioningProfiles / --disableExtensions 作为普通命令行参数时，应把对应 Bazel Flag 放入 local.bazelrc，或者直接使用 Bazel。

⸻

真机：正式 / 完整 Provisioning

完整签名通常至少需要以下 Provisioning Targets：

* Telegram
* Share
* NotificationContent
* NotificationService
* Intents
* Widget
* BroadcastUpload

使用完整 Provisioning Profiles 时：

local.bazelrc

不能包含：

build --//Telegram:disableExtensions

也不能包含：

build --//Telegram:disableProvisioningProfiles

编译

source ~/.zshrc 2>/dev/null
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-input/local-configuration.json \
  --codesigningInformationPath build-input/codesigning-development \
  --buildNumber=1 \
  --configuration=debug_arm64 \
  --continueOnError

IPA 产物：

bazel-bin/Telegram/Telegram.ipa

安装到真机

查看设备：

xcrun devicectl list devices

解压：

unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-device

安装：

xcrun devicectl device install app \
  --device <DEVICE_UDID> \
  /tmp/tg-device/Payload/Telegram.app

⸻

真机：免费 Apple ID 自签

免费 Apple ID 通常无法为 Telegram 的全部 Extensions 创建 App ID 与 Provisioning Profile，因此这种模式下可以禁用 Extensions。

免费开发证书通常需要定期重新签名。

1. 创建配置文件

创建：

build-input/local-configuration.json

示例：

{
  "bundle_id": "jp.foxtea.nextgram",
  "api_id": "<your_api_id>",
  "api_hash": "<your_api_hash>",
  "team_id": "<your_team_id>",
  "app_center_id": "0",
  "is_internal_build": "true",
  "is_appstore_build": "false",
  "appstore_id": "0",
  "app_specific_url_scheme": "tg",
  "premium_iap_product_id": "",
  "enable_siri": false,
  "enable_icloud": false
}

api_id / api_hash

前往：

https://my.telegram.org/apps

申请自己的 Telegram API 凭据。

team_id

team_id 不是证书名称括号里的序列号。

查询：

security find-certificate -c "Apple Development" -p \
  | openssl x509 -noout -subject

寻找：

OU=XXXXXXXXXX

OU 对应的值即 Team ID。

bundle_id

应该使用 Nextgram 自己的 Bundle Identifier。

不要使用 Telegram 官方 Bundle ID。

例如：

jp.foxtea.nextgram

⸻

2. 生成 Provisioning

免费账号通常需要由 Xcode 自动生成 Provisioning。

在 Xcode 中新建一个空项目。

使 Bundle Identifier 与：

build-input/local-configuration.json

中的：

bundle_id

完全一致。

然后：

1. Team 选择自己的 Personal Team
2. 连接 iPhone
3. Run 到真机一次
4. 完成开发者信任与 Provisioning 生成

⸻

3. 复制 Provisioning Profile

Xcode 16+ 通常把 Provisioning Profiles 放在：

~/Library/Developer/Xcode/UserData/Provisioning Profiles/

而 Bazel 的部分逻辑仍可能从传统目录读取。

复制：

cp ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision \
   ~/Library/MobileDevice/Provisioning\ Profiles/

⸻

4. 配置 local.bazelrc

免费 Apple ID 自签时，可以添加：

build --//Telegram:disableExtensions

不要添加：

build --//Telegram:disableProvisioningProfiles

否则主 App 本身也不会使用 Provisioning Profile。

⸻

5. 编译

source ~/.zshrc 2>/dev/null
python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-input/local-configuration.json \
  --xcodeManagedCodesigning \
  --buildNumber=1 \
  --configuration=debug_arm64 \
  --continueOnError

产物：

bazel-bin/Telegram/Telegram.ipa

⸻

Direct Bazel

如果当前 Make.py Debug Wrapper 把 Swift：

-j <n>

错误地当成输入文件，并且已经成功生成：

build-input/configuration-repository/variables.bzl

可以直接调用 Bazel：

source ~/.zshrc 2>/dev/null
build-input/bazel-8.4.2-darwin-arm64 build Telegram/Telegram \
  --keep_going \
  --announce_rc \
  --features=swift.use_global_module_cache \
  --verbose_failures \
  --remote_cache_async \
  --define=buildNumber=1 \
  --disk_cache="$HOME/telegram-bazel-cache" \
  -c dbg \
  --ios_multi_cpus=arm64 \
  --watchos_cpus=arm64_32

⸻

模拟器：免签

模拟器环境可以临时在：

local.bazelrc

中加入：

build --//Telegram:disableProvisioningProfiles
build --//Telegram:disableExtensions

编译

python3 build-system/Make/Make.py --overrideXcodeVersion \
  --cacheDir ~/telegram-bazel-cache \
  build \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning \
  --buildNumber=1 \
  --configuration=debug_sim_arm64 \
  --continueOnError

产物：

bazel-bin/Telegram/Telegram.ipa

安装到模拟器

解压：

unzip -o bazel-bin/Telegram/Telegram.ipa -d /tmp/tg-sim

如果之前安装过 Telegram / Nextgram 的旧构建，建议先卸载：

xcrun simctl uninstall booted ph.telegra.Telegraph

然后安装：

xcrun simctl install booted \
  /tmp/tg-sim/Payload/Telegram.app

⸻

Telegram iOS Source Code Compilation Guide

以下部分为 Telegram-iOS 上游通用构建说明。

Creating your Telegram Application

1. Obtain your own api_id.
2. Please do not use the name Telegram for your app, or make sure users clearly understand that it is unofficial.
3. Do not use Telegram’s standard application logo as your own application’s logo.
4. Follow Telegram’s security guidelines and protect your users’ data and privacy.
5. Publish your source code where required by the applicable open-source licenses.

Get the Code

git clone --recursive -j8 https://github.com/TelegramMessenger/Telegram-iOS.git

Setup Xcode

Install a compatible Xcode version from Apple.

Adjust Configuration

Generate a random identifier:

openssl rand -hex 8

Create an Xcode project and configure your own：

* Bundle Identifier
* Team ID
* API ID
* API Hash

Generate an Xcode Project

python3 build-system/Make/Make.py \
  --cacheDir="$HOME/telegram-bazel-cache" \
  generateProject \
  --configurationPath=build-system/template_minimal_development_configuration.json \
  --xcodeManagedCodesigning

Advanced Compilation Guide

Xcode

1. Copy and edit build-system/appstore-configuration.json.
2. Prepare the corresponding Provisioning Profiles.
3. Generate the Xcode project:

python3 build-system/Make/Make.py \
  --cacheDir="$HOME/telegram-bazel-cache" \
  generateProject \
  --configurationPath=configuration_from_step_1.json \
  --codesigningInformationPath=directory_from_step_2

IPA

使用 Distribution Provisioning Profiles，然后运行：

python3 build-system/Make/Make.py \
  --cacheDir="$HOME/telegram-bazel-cache" \
  build \
  --configurationPath=<configuration.json> \
  --codesigningInformationPath=<codesigning-directory> \
  --buildNumber=100001 \
  --configuration=release_arm64

FAQ

Xcode 卡在 build-request.json not updated yet

如果构建日志长期显示：

"/Users/xxx/Library/Developer/Xcode/DerivedData/Telegram-xxx/Build/Intermediates.noindex/XCBuildData/xxx.xcbuilddata/build-request.json" not updated yet, waiting...

取消当前构建并重新执行一次即可。

Telegram_xcodeproj: no such package

如果重启系统后自动生成的 Xcode Project 出现：

ERROR: Skipping '@rules_xcodeproj_generated//generator/Telegram/Telegram_xcodeproj:Telegram_xcodeproj':
no such package '@rules_xcodeproj_generated//generator/Telegram/Telegram_xcodeproj'

重新执行：

generateProject

步骤生成项目。

Tips

Simulator-only 构建不需要 Codesigning

对于 Nextgram 当前的 Make.py build，模拟器免签应在：

local.bazelrc

中添加：

build --//Telegram:disableProvisioningProfiles
build --//Telegram:disableExtensions

不要把：

disableProvisioningProfiles

用于真机包。

Xcode Version

每个 Telegram-iOS 版本通常要求特定 Xcode 版本，具体见：

versions.json

如果需要跳过 Xcode 版本检测，可以使用：

python3 build-system/Make/Make.py \
  --overrideXcodeVersion \
  build ...

⸻

Disclaimer

Nextgram is an unofficial Telegram client.

Telegram is a trademark of Telegram Messenger Inc.

Nextgram is not affiliated with, endorsed by, or sponsored by Telegram Messenger Inc., Nagram, or AyuGram.
