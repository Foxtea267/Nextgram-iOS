# 上游同步记录

## Nagram / Telegram 13.0

- 上游仓库：<https://github.com/NextAlone/Nagram-iOS>
- 同步至 `71206814ecbe42844a060f5c0253d370f7ada65a`（2026-10-10）。
- 初始源码对应的上游基线为 `cb7f8462aec9733301eb73caa6be3d68f2780acf`（12.9.3）。Nextgram 最初整包上传，未保留上游历史；此次以该基线进行三方集成，并接回上游历史，供后续正常合并。
- 上游基础版本 `13.0` 在 Nextgram 中规范为 `13.0.0`；本轮 Nextgram 版本从 `13.0.0.1` 开始，后续发布递增第四段。
- 同步 Xcode 27、Bazel 9.2、依赖修订及上游功能和修复；Actions 使用 `xcode-27` 镜像。
- 保留 Nextgram 品牌、设置分组、聊天筛选、删除消息拦截与编辑历史、音乐搜索、使用协议和四种兼容包发布流程。
- 不引入上游 TestFlight 或 Telegram 频道自动发布流程；API hash 继续仅通过仓库 Actions Secrets 注入。

Windows 环境不能执行 iOS 全量编译或真机安装。静态检查不等同于 app 构建成功；IPA 是否可用须以 macOS Actions 构建和重签后实测为准。
