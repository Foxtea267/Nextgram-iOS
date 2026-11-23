# 音乐播放器 Canvas

这个专用工程使用独立的 `MusicCanvas` App 宿主，复用 `NextgramMusicUI` 的实际播放器视图。预览提供封面和逐字歌词样例，不连接音乐播放会话。播放按钮可切换界面状态，进度条可拖动，歌词按钮可检查过渡；真实音频、切歌和完整关闭流程需要在 App 内验证。


运行独立 App 后，点击播放器的 **… → 设置** 打开完整演示选项：三种封面布局（默认专辑、全屏、唱片）、封面大小与圆角、唱片旋转、查看页 3D 与底部文字、四种背景、配色与自定义颜色、模糊强度、音量与剩余时间、标题对齐/字号、播放按钮大小，以及十项歌词动效。可以一键开启动效（使用弹性滚动）或恢复原有样式，也可以逐项调整；线性与弹性滚动互斥。设置通过主 App 使用的 `NagramSettingsSignal` 实时更新。独立宿主的设置使用隔离的演示存储，不同步到 iCloud，也不会修改 Telegram App 的设置。

在演示设置的 **歌词来源 → 输入歌曲信息，测试在线来源…** 中填写真实歌曲名称、艺术家和总时长（秒），即可调用主 App 的在线查询与缓存。输入信息仅用于歌词查询，不会播放该歌曲。可选择优先来源（自动模式继续按其他来源回退），或在播放器 **… → 本曲歌词来源** 中指定单一来源；**重新获取歌词** 跳过已有在线缓存。连接失败、无匹配和已有歌词刷新失败分别显示提示。**恢复本地逐字歌词样例** 可返回不需要网络的样例。Blue Dream / ARU（194 秒）已验证能通过网易云的歌曲和艺术家别名取得同步歌词；来源本身没有对应条目时仍会无匹配，不会凭空生成歌词。

`--canvas-motion settings-panel` 自动展示并滚动设置面板；`settings-options` 依次演示三种封面、四种背景及歌词动效。仅用于隔离演示设备录制，不连接账户。系统输出设备弹窗中的播放信息需要真实音乐会话，独立样例不能验证 AirPlay 或蓝牙播放。

`#Preview` 位于 App 目标的 `MusicCanvasPreviews.swift` 中，与 `MusicCanvasApp.swift` 的启动入口分开。`NextgramMusicUI` 是静态库，Xcode 不支持直接渲染属于该目标的预览；在播放器实现文件中打开 Canvas 会找不到这些入口。

在仓库根目录、Xcode 和仓库依赖准备完成后生成工程。这个宿主只生成模拟器目标，不需要 App 签名描述文件：

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion generateProject \
  --configurationPath build-system/appstore-configuration.json \
  --xcodeManagedCodesigning --target Telegram/MusicCanvas --noOpen
```

1. 如果已打开旧工程，点 **File → Close Project**，再通过 **File → Open…** 打开 `Telegram/MusicCanvas/MusicCanvas.xcodeproj`。选择 **MusicCanvas** 方案和 iPhone 模拟器。
2. 在左侧文件列表展开 **Telegram → MusicCanvas**，点击 **MusicCanvasPreviews.swift**。
3. 点菜单 **Editor → Canvas** 显示画布。**Music · Cover / Lyrics** 为播放状态，**Music · Paused / Lyrics Paused** 为暂停状态。
4. 在 **Editor → Canvas** 菜单中取消勾选 **Use Legacy Previews Execution**，然后点击画布的刷新按钮。工程生成后会为 `MusicCanvas` App 单独设置 `ENABLE_PREVIEWS=YES` 和 `ENABLE_DEBUG_DYLIB=YES`。旧工程若缺少这些设置，请重新生成并打开工程。

**Lyrics · All Effects** 演示逐字扫光、逐字上浮、当前行发光、非当前行模糊、焦点缩放、线性或弹性滚动、逐行错峰跟随、间奏呼吸圆点及边缘渐隐开启的效果（互斥的滚动方式采用弹性滚动）。**Lyrics · Original** 播放同一段本地歌词，并关闭这些新效果，便于对比。这是独立选项的组合预览，不增加另一种播放器样式，也不写入用户设置。

**Lyrics · With Translation** 使用原创英文逐字歌词和中文译文，可离线检查双语排版和手动浏览。独立 App 可用 `--canvas-translated-lyrics` 打开同一示例。要测试真实来源，在在线查询中输入 `雪唄 - yukiuta` / `Myuk` / `223.3`，再选择网易云音乐。

在 **Nextgram 设置 → 媒体 → Apple Music 样式** 中可以分别设置十项效果，默认全部关闭以保留原有歌词呈现。线性与弹性滚动二选一；开启其中一种后可设置逐行错峰跟随。逐字扫光使用歌词自身的逐字时间轴；只有逐行时间轴时继续按行高亮。逐字上浮按原歌词的词级时间轴缓慢抬起约 2pt，结束后保持，不生成新的歌词时间戳。弹性模式逐行运动，后续行以 45ms 间隔跟随。系统“减弱动态效果”会停用装饰性的圆点呼吸、上浮和弹性错峰动画。

`--noOpen` 只生成工程，不会关闭或打开已有的 Xcode。预览入口只编译进 Debug 模拟器版本。

**Music · Artwork 3D** 打开独立封面查看页：居中封面、左上角关闭、轻微倾斜和按压回弹。设置中的封面 3D 选项只作用于这个查看页，播放器主页面保持平面封面。圆角裁切位于图像子视图，3D 投影容器不裁切。`--canvas-motion artwork-motion` 与 `artwork-motion-off` 通过实际交互共用的按压处理方法，依次演示查看页四角、中心、松手回正及关闭后主页面保持平面；它们不写入用户设置，也不模拟真实设备传感器。

封面查看页的 3D 效果由指尖位置驱动，松手回正。`--canvas-motion cover-swipe` 和 `fullscreen-swipe` 可分别录制专辑与全屏封面向左右滑动。

“封面查看页底部显示歌曲名称和艺术家”独立于 3D 开关，默认关闭，支持设置同步与备份。开启后在查看页底部居中显示两项信息，长文本最多两行；空间不足时缩小封面的可用区域以避免重叠。**Music · Artwork Title / Artist** 预览开启状态；`--canvas-motion artwork-metadata` 在同一查看页演示默认关闭、开启、关闭与再次开启，不修改真实设置。

**Lyrics · Interlude** 专门演示八秒间奏。开启间奏效果后，等待标记使用三个独立圆形，按间奏进度从左至右点亮，整体缓慢呼吸，下一句前先放大再收缩淡出。短于 2.41 秒的空档不显示圆点；较短间奏简化为淡入、保持和收尾。暂停冻结圆点进度，系统“减弱动态效果”停用缩放。关闭该选项保留原有省略号。录制入口为 `--canvas-motion lyrics-interlude`，暂停恢复检查为 `--canvas-motion lyrics-interlude-pause`。

这个专用工程由 Xcode 原生编译小型预览宿主并生成调试动态库；播放器等静态依赖复用 Bazel 的普通 Debug 产物。主 Telegram App 的构建流程不受影响。

已通过完整 Telegram 模拟器构建（`debug_sim_arm64`）、专用工程重新生成及原生 Debug 构建。已在 Xcode 27.2 的 iPhone 18 Pro Canvas 中实际渲染并检查封面和歌词两个入口。

录制动效时，已安装的独立宿主接受 `--canvas-motion playback`、`--canvas-motion lyrics-playing` 或 `--canvas-motion lyrics-paused`。它会在页面显示后的 1.2 秒和 2.6 秒调用同一个播放器按钮处理方法；普通 Canvas 不会自动触发。`lyrics-effects` 和 `lyrics-original` 演示全开与原有歌词的连续播放，`lyrics-effects-paused` 检查暂停状态，`lyrics-motion-pause` 在词句中暂停 1.5 秒后继续，以检查上浮与扫光能否冻结和恢复。只在隔离的 MusicCanvas 预览设备使用这些参数。

效果参考：[Apple Music Sing](https://www.apple.com/newsroom/2022/12/apple-introduces-apple-music-sing/) 的实时歌词，以及 [AMLL](https://github.com/amll-dev/applemusic-like-lyrics) 的逐行弹性运动与词上浮、[Lyricify](https://github.com/WXRIW/Lyricify-App/blob/main/docs/Lyricify%204/settings.json) 的上浮和拖动选项。本工程使用原生 UIKit 绘制，没有引入网页播放器依赖。

AsyncDisplayKit 的 `ASDisplayNode +load` 带有 `// MARK: NEXTGRAM` 修改：只在模拟器 Canvas 环境中将框架初始化排到主队列，避免预览注入期间同步创建 `UIView` 导致 UIKit 初始化死锁。


专辑封面只保留默认专辑、全屏和唱片三种；旧的宽幅、完整显示与裁剪铺满设置自动回退默认专辑。唱片只在实际播放时旋转，暂停冻结当前角度，再次播放从该角度继续；歌词页的小封面不旋转。背景的缓慢移动也会在暂停时停住。

全屏模式使用一张铺满屏幕的封面。在 **… → 设置 → 背景与配色 → 全屏封面模糊高度** 中，可以选择默认的底部短渐变、覆盖整个控制区，或自定义从屏幕底部起算的高度（10%–50%）。独立的竖向渐变背景参考 [Exteraless PlayerSheet](https://github.com/exteraless/exteraless/blob/main/TMessagesProj/src/main/java/app/exteraless/player/PlayerSheet.java) 的色调在上方覆盖、向屏幕 70% 高度淡出到 surface 的方式，按已有封面/主题/自定义配色生成静态原生渐变。

独立演示使用存流《ARU》中 Blue Dream（あおいゆめ）的真实专辑封面，随 App 打包以便离线预览。[Apple Music 曲目](https://music.apple.com/jp/album/1680864623?i=1680864626)；封面资源来自该曲目的 Apple 公开目录。动效歌词仍是标明的本地原创时间轴样例，并非这首歌的实际歌词；在线查询入口仍可以输入真实歌曲信息取得来源中的歌词。

`--canvas-motion disc-playback` 演示转动、暂停三秒、继续转动及再次暂停；`fullscreen-cover` 与 `gradient-cover` 分别展示全屏封面和静态渐变背景，便于逐帧验证。
