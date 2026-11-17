# iPhone 应用的 Xcode 画布

`NextgramAppPreview.swift` 提供 **Nextgram · iPhone App** 画布入口，用于承载应用的真实导航，包括 Telegram 原有界面和 Nextgram 新增界面。目前完整模拟器构建已通过，Canvas 的实际渲染仍待验证。

1. 打开 `Telegram/Telegram.xcodeproj`，选择 **Telegram** scheme 和 iPhone 模拟器。
2. 点击菜单栏 **File → Open Quickly…**，输入 `NextgramAppPreview.swift`，双击匹配的文件。
3. 点击菜单栏 **Editor → Canvas** 显示画布。当前 Bazel 工程不生成 Xcode 的 Debug Dylib；如果提示需要 `ENABLE_DEBUG_DYLIB=YES`，在 **Editor → Canvas** 子菜单勾选 **Use Legacy Previews Execution**，再点 **Refresh Canvas**。菜单中的 **Canvas** 显示开关和 **Canvas** 子菜单是两个不同的项目。
4. 预览渲染成功后，切到画布的 **Live** 模式，再用应用内导航进入要预览的页面。

如果提示 **Active scheme does not build this file**，检查 Telegram 方案的 Build 列表是否包含 **TelegramUI**，并且勾选 Run。Debug 下该文件由 `TelegramUI` 编译；`TelegramUIFramework` 仅在 Release 下合并这部分源码。项目生成流程会自动将 `TelegramUI` 加入 Telegram 方案。修改方案后重新打开工程。

如果工程里找不到该文件，在仓库根目录重新生成项目：

```sh
python3 build-system/Make/Make.py generateProject \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --disableExtensions --noOpen
```

重新打开工程以载入文件。`--noOpen` 在生成时不会关闭或启动已有的 Xcode。

预览入口复用演示模式中的样例私聊、群组、频道、聊天搜索、个人资料以及 Telegram 和 Nextgram 设置。应用界面共享同一个可交互预览；打开某个页面的源码时，Xcode 不会自动跳到该页面。各页面在 Canvas 中的显示尚未逐项验证。依赖真实登录、远程数据、系统授权或服务端功能的界面仍需要普通模拟器会话或真机。

画布预览只用于 Debug 模拟器构建。它复用[演示模式](demo-mode.md)的样例数据，但使用自己的数据库和设置，不需要登录，也不会打开正式账号数据库。
