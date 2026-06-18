# iOS 版智能工牌

本目录为 [Android 版智能工牌](../README.md) 的 iOS 同等功能翻译版，保持与 Android 版一致的功能、架构和用户体验。

## 与 Android 版的对应关系

| Android | iOS |
|---|---|
| Kotlin | Swift |
| Jetpack Compose | SwiftUI |
| MVVM + Clean Architecture | MVVM + Clean Architecture |
| Hilt | 手动 DI（AppContainer） |
| Room + DataStore | Core Data + UserDefaults |
| OkHttp (REST + WebSocket) | URLSession (REST + WebSocket) |
| AudioRecord 16kHz/16bit/PCM | AVAudioEngine 16kHz/16bit/PCM |
| Foreground Service + WakeLock | Background Modes (audio) + AVAudioSession |
| LocationManager | Core Location |
| FunASR WebSocket 实时流式 | FunASR WebSocket 实时流式 |
| OpenAI 兼容 LLM 接口 | OpenAI 兼容 LLM 接口 |

## 功能清单

- [x] 首页仪表盘（今日拜访统计、最近记录）
- [x] 新建拜访（客户名称、公司、目的、参与人员）
- [x] 长时间录音（前台 + 后台音频模式）
- [x] 实时语音转写（WebSocket 流式 FunASR）
- [x] 拜访结束后 LLM 自动生成结构化总结
- [x] 拜访详情（完整转写文本 + AI 总结）
- [x] 历史记录（按客户名称/公司搜索）
- [x] 设置页面（FunASR 地址、LLM 配置、自定义 Prompt）
- [x] GPS 位置追踪

## 项目结构

```
ios/
├── README.md
├── project.yml                         # XcodeGen 工程描述
└── SmartBadge/
    ├── SmartBadgeApp.swift             # @main App 入口 + 根导航
    ├── Info.plist                      # 权限、后台模式、Bundle 配置
    ├── Core/
    │   ├── Audio/AudioCapture.swift    # AVAudioEngine PCM 采集
    │   ├── ASR/FunASRClient.swift      # FunASR WebSocket 客户端
    │   ├── LLM/LLMClient.swift         # OpenAI 兼容 LLM 客户端
    │   ├── Location/LocationTracker.swift # GPS 位置追踪
    │   ├── Service/RecordingManager.swift # 前台+后台录音编排
    │   ├── Database/PersistenceController.swift # Core Data 栈
    │   └── DI/AppContainer.swift       # 手动 DI 容器
    ├── Domain/
    │   ├── Model/                      # Visit, VisitSummary, LocationPoint
    │   └── Repository/VisitRepository.swift  # Repository 协议
    ├── Data/Repository/VisitRepositoryImpl.swift  # Core Data 实现
    └── UI/
        ├── Home/                       # 首页仪表盘
        ├── Recording/                  # 新建拜访 + 实时转写
        ├── Detail/                     # 拜访详情 + AI 总结
        ├── History/                    # 历史记录
        ├── Settings/                   # API 配置
        └── Theme/AppTheme.swift        # 主题常量
```

## 构建方法

### 方式一：XcodeGen（推荐）

```bash
# 安装 XcodeGen
brew install xcodegen

# 在 ios 目录生成 .xcodeproj
cd ios
xcodegen generate

# 打开工程
open SmartBadge.xcodeproj
```

### 方式二：手动创建 Xcode 工程

1. 打开 Xcode → File → New → Project → iOS → App
2. Product Name: `SmartBadge`, Interface: SwiftUI, Language: Swift
3. 删掉自动生成的文件，将 `SmartBadge/` 下所有源文件拖入工程

## 最低要求

- macOS 12+（安装 Xcode 14.x）
- Xcode 14.2+（自带 iOS 16.2 SDK + Swift 5.7）
- iOS 16.0+

## 权限

| 权限 | Info.plist Key | 用途 |
|---|---|---|
| 麦克风 | NSMicrophoneUsageDescription | 录音 |
| 定位 | NSLocationWhenInUseUsageDescription | 记录拜访位置 |
| 后台音频 | UIBackgroundModes → audio | 锁屏/后台持续录音 |
| 后台定位 | UIBackgroundModes → location | 后台位置追踪 |

## 注意事项

- iOS 后台录音需配置 `UIBackgroundModes` 中的 `audio` 模式（已在 Info.plist 中配置）
- 通过 `AVAudioSession.setCategory(.playAndRecord)` 确保后台音频不中断
- FunASR WebSocket 在 App 进入后台时可能断开，已内置自动重连（最多 3 次，间隔 2/4/8 秒）
- Core Data 数据模型为程序化构建，无需 `.xcdatamodeld` 文件
- 设置项存储在 `UserDefaults`，首次使用需在 App 设置页面配置
