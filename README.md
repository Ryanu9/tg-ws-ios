# TG-WS for iOS

基于 [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) 的非官方修改版，内置 WebSocket / webhook 订阅（tgpush 中转）。功能对应 Android 版 Telegram-FOSS-WS：

- **本地模式**：首次启动自动进入，不需要登录 Telegram 账号，也不会连接 Telegram 服务器。
- **WebSocket 订阅**：可添加多个订阅，每个订阅设置地址、Token、Token 发送方式（请求头 / URL 参数 / 两者 / 不发送）和额外请求头。
- 每个订阅（开启「按博主拆分频道」时为每个博主）显示为聊天列表里的一个**原生频道**。未读数、App 角标、图片查看器、静音都按 Telegram 原生方式工作。
- 支持 tgpush 的 `seq` / `?since=` 断线补发，按消息 id 去重，最多保留 1500 条去重记录。
- 断线自动重连，退避间隔 0.5s 到 30s；遇到 HTTP 429 会遵守服务端的 `Retry-After`。
- 收到消息立即弹本地通知，同一频道的消息合并为一条。
- 可选**后台保活**：切到后台后循环播放静音音频，保持连接和即时通知。

## 仓库内容

| 路径 | 说明 |
|---|---|
| `UPSTREAM_COMMIT` | 补丁对应的 Telegram-iOS 上游 commit |
| `telegram-ios-ws.patch` | 全部改动，包括新增的 `submodules/WsBridge` 模块 |
| `tests/main.swift` | 解析、路由、请求构造、去重的单元测试，CI 在 Linux 上运行 |
| `.github/workflows/build.yml` | GitHub Actions：先跑单元测试，再在 macOS 27 / Xcode 27.1 上编译 IPA |
| `scripts/apply-patch.sh` | 在自己的 Mac 上准备好源码，并打印编译命令 |

## 编译（GitHub Actions）

1. 把本仓库推到 GitHub。公开仓库的 macOS 构建免费；私有仓库的 macOS 分钟数按 10 倍计费，一次完整编译约需 2–4 小时。
2. Actions 页面会在 push 后自动开始构建，也可以选 **Build TG-WS iOS → Run workflow** 手动触发。手动触发时可选：
   - `configuration`：默认 `release_arm64`。如果出现内存不足，改用 `debug_arm64`。
   - `bundle_id` / `display_name`：写入 IPA 的包名和桌面显示名称。
3. 构建完成后，在该次运行的 **Artifacts** 里下载 `TG-WS-ipa-<编号>`，里面有：
   - `TG-WS.ipa`：已删除扩展，bundle id 改为 `org.tgws.app`，**用这个重签**。
   - `Telegram-original-fake-signed.ipa`：未做后处理的原始包，仅作备用。
4. 可选：在仓库 Settings → Secrets 中添加 `TG_API_ID` / `TG_API_HASH`（在 my.telegram.org 申请），构建时会替换掉默认的 api_id。本地模式不登录 Telegram，所以不配置也能用。

编译失败时，在 Artifacts 的 `build-log` 里查看完整日志和汇总后的 `errors.txt`。

## 安装（全能签等重签工具）

1. 把 `TG-WS.ipa` 导入全能签，用你的证书签名后安装。
2. 包名可以保留 `org.tgws.app`，也可以在全能签里改成别的。**不要**改成 `ph.telegra.Telegraph`，否则会和官方 Telegram 冲突。
3. 重签后的证书一般没有 App Group 权限。本版本已经处理：拿不到 App Group 时，数据自动存到 App 自己的沙盒里。

## 使用

1. 首次打开 App 会直接进入聊天列表（本地模式），并请求通知权限，请允许。
2. 添加订阅，有两个入口：
   - 聊天列表右上角的「撰写」按钮。本地模式下撰写没有意义，这个按钮改为打开订阅管理。
   - **设置 → WebSocket 订阅**。
3. 添加订阅时填写地址（`ws://` 或 `wss://`）、Token 和发送方式，可以先点「测试连接」验证。
4. 订阅管理页还提供：
   - 「立即重连」
   - 「测试通知」
   - 「后台保活」开关
   - 每个订阅的实时连接状态

## 与 Android 版的差异（iOS 系统限制）

- iOS 没有前台服务。不开后台保活时，App 切到后台约 30 秒后系统会暂停连接，期间不会收到通知。回到前台后会通过 `since` 自动补收离线期间的消息，消息不会丢。
- 开启后台保活后，后台也能实时收消息、弹通知，代价是耗电增加。如果系统内存紧张，App 仍可能被杀掉。
- 真正的锁屏推送需要 Apple 付费开发者账号，并在 tgpush 服务端接入 APNs，本版本没有实现。
- App 在前台时，补发的旧消息（超过 2 分钟）不弹横幅，只进聊天列表；实时消息照常提醒。

## 实现概要

- `submodules/TelegramCore/Sources/WsBridge/WsLocalAccount.swift`：
  - 创建本地账号（伪造自己的用户，跳过登录）。
  - 清除需要从服务器补全的聊天列表和历史"空洞"。
  - 把帖子作为本地频道消息写入 Postbox。
- `submodules/TelegramCore/Sources/Account/Account.swift`：本地账号的 MTProto 永不恢复连接，忽略服务器登出，聊天列表标题的连接状态改由 WebSocket 状态驱动。
- `submodules/WsBridge`：
  - WebSocket 连接与重连
  - 消息解析（移植自 Android `WsParser`）
  - 路由（频道 id 算法与 Android 一致）
  - 图片下载与压缩
  - 本地通知
  - 后台保活
  - 订阅管理界面（UIKit）
- `AppDelegate.swift`：
  - 首次启动自动激活本地模式。
  - App Group 不可写时回退到 App 自己的目录。
  - App 在前台时也显示 WebSocket 通知。

本项目基于 GPL v2 授权的 Telegram-iOS，修改后的源码即本仓库中的补丁。
