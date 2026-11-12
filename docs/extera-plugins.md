# Extera 源码插件兼容层

入口为「设置 → Nextgram → Extera 插件」。从「文件」导入 UTF-8 的
`.plugin` 文件（最多 2 MB），确认安装后，在插件详情页单独启用。导入时只分析源码的
元数据，不执行插件。插件文件和设置保存在本机；每次重启 Nextgram 后须重新启用插件。

只运行可信来源的插件。代码在 Nextgram 进程内执行，可能访问应用数据和网络。
这是兼容层，不是 exteraLess 的权限沙箱。卡住的插件会显示超时提示；
如需停止仍在运行的 Python 代码，请重启应用。

## 当前兼容范围

- Python 3.11 源码、`BasePlugin` 加载与卸载、`get_setting` / `set_setting`。
- `create_settings` 的 `Header`、`Text`、`Input`、`Switch` 及修改回调。
- `add_on_send_message_hook` 的优先级和 `DEFAULT`、`CANCEL`、`MODIFY`、
  `MODIFY_FINAL`。首版仅接入聊天界面的未格式化纯文本发送；不会改写转发、带实体的文本、
  媒体说明、秘密聊天或应用扩展中的发送。钩子出错时不会擅自发送原文。
- `MESSAGE_CONTEXT_MENU` 无条件菜单项。回调可读取 `account`、`dialog_id`，
  以及消息的 `getId()` 和 `messageText`。秘密聊天和开启复制保护的消息不提供此菜单。
  账户和会话标识是 Nextgram 的不透明整数，并非 Android 的账号槽位。

不支持 Android/Java/DEX/Xposed、`.elyx` / `.eaf`、请求/更新钩子、插件仓库、
第三方包安装、二进制 Python 扩展、Android 原生设置控件或其他宿主菜单。
不能据此假定支持某个完整 extera SDK 版本。

## 验收

1. 将 [exteraGram 官方 Hello World 源码](https://plugins.exteragram.app/docs/first-plugin)
   保存为 `hello_world.plugin`，不修改源码。
2. 在使用测试服务器的 iOS 构建里导入、安装和启用。发送 `.hello Alice`，
   收到的消息应为 `Hello, Alice!`。
3. 在插件详情页修改模板为 `Welcome, {name}.`，再次发送，确认文本变为
   `Welcome, Alice.`。关闭插件后，`.hello Alice` 应保持原样；重启后仍保持禁用。

在桌面 Python 上可运行兼容逻辑测试：

```sh
python3 -m unittest discover -s Nagram/Plugins/tests -v
```

测试不替代完整 iOS 构建。Bazel 按固定 SHA-256 下载
[BeeWare Python 3.11 iOS XCFramework](https://github.com/beeware/Python-Apple-support/releases/tag/3.11-b9)，
将设备或模拟器切片和纯 Python 标准库资源打包到应用。
