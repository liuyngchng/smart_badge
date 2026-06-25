# 语音笔记

语音笔记是一款 Android 应用，支持在线/离线语音转写（ASR）与 AI 总结（LLM）。录制或导入音频后，自动生成结构化录音记录：议题、结论、待办事项和跟进计划。

## 功能

- **录音与导入** — 实时录音（前台服务 + WakeLock 保活），支持从本地导入音频文件
- **在线语音转写** — WebSocket 实时流式连接私有化 FunASR 服务
- **离线语音转写** — 本地 Sherpa-ONNX + SenseVoice 模型（INT8 / FP32），无需网络
- **在线 AI 总结** — OpenAI 兼容 API（支持 DeepSeek、GPT 等），长文本自动分段合并
- **离线 AI 总结** — llama.cpp + Qwen2.5 GGUF 本地推理（1.5B / 0.5B），无需网络
- **音频回放** — 播放/暂停、快进快退 15s、进度拖动、分享导出
- **历史记录** — 按标题/备注/内容搜索，侧滑删除，批量清空
- **连接测试** — ASR WebSocket / LLM API 连通性一键检测

## 技术栈

| 项 | 选型 |
|---|---|
| 语言 | Kotlin 2.0 |
| UI | Jetpack Compose + Material 3 |
| 架构 | MVVM + Clean Architecture |
| DI | Hilt |
| 本地存储 | Room + DataStore |
| 网络 | OkHttp (REST + WebSocket) |
| 录音 | AudioRecord 16kHz/16bit/PCM |
| 在线 ASR | 私有化 FunASR (WebSocket 实时流式) |
| 离线 ASR | Sherpa-ONNX JNI + SenseVoice (INT8/FP32 ONNX) |
| 在线 LLM | OpenAI 兼容接口 (分段总结 + 带退避重试) |
| 离线 LLM | llama.cpp JNI + Qwen2.5 GGUF (0.5B/1.5B) |
| 原生构建 | CMake + NDK (arm64-v8a) |

## 快速开始

1. 用 Android Studio 打开项目目录
2. 等待 Gradle Sync 完成
3. 连接 Android 设备或启动模拟器（API ≥ 26）
4. 运行 App

## 配置

首次使用可在 App 内 **设置** 页面配置：

| 配置项 | 说明 | 默认值 |
|---|---|---|
| ASR 模式 | 在线 (FunASR) / 离线 (SenseVoice) | 离线 |
| FunASR WebSocket 地址 | 在线模式下的私有化 FunASR 服务地址 | `ws://192.168.240.29:10095` |
| 离线 ASR 模型质量 | INT8 (~170MB) / FP32 (~860MB) | INT8 |
| LLM 模式 | 在线 (API) / 离线 (本地模型) | 离线 |
| LLM API 地址 | OpenAI 兼容的 base_url 端点 | `https://api.deepseek.com` |
| LLM API Key | API 密钥 | — |
| LLM 模型 | 在线模式下的模型名称 | `deepseek-v4-pro` |
| 离线 LLM 模型 | Qwen2.5-1.5B / Qwen2.5-0.5B / 自定义 | Qwen2.5-0.5B |
| 自定义 Prompt | 总结 Prompt 模板（可选） | 留空使用默认 |

### 离线模型下载

**ASR 模型**从 GitHub Releases 自动下载 `.tar.bz2` 归档并解压。

**LLM 模型**（GGUF 格式）从 ModelScope 自动下载，也支持从本地文件导入。

| 模型 | 文件 | 大小 | 下载地址 |
|---|---|---|---|
| ASR INT8 | `model.int8.onnx` + `tokens.txt` | ~170 MB | [`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2`](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2) |
| ASR FP32 | `model.onnx` + `tokens.txt` | ~860 MB | [`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2025-09-09.tar.bz2`](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2025-09-09.tar.bz2) |
| LLM Qwen2.5-0.5B | `qwen2.5-0.5b-instruct-q4_k_m.gguf` | ~352 MB | [ModelScope](https://modelscope.cn/models/qwen/Qwen2.5-0.5B-Instruct-gguf/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf) |
| LLM Qwen2.5-1.5B | `qwen2.5-1.5b-instruct-q4_k_m.gguf` | ~986 MB | [ModelScope](https://modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/master/qwen2.5-1.5b-instruct-q4_k_m.gguf) |

> 低内存设备（< 3GB RAM）：离线 LLM 自动切换 CPU-only 推理。
> 收到系统内存警告时，模型会在当前推理完成后自动释放。
>
> 开发者也可用脚本预先下载模型，再传输到手机用「上传」按钮导入：
> ```bash
> bash scripts/download_models.sh          # 下载两种 ASR 精度
> bash scripts/download_models.sh int8     # 仅 INT8
> bash scripts/download_models.sh fp32     # 仅 FP32
> ```

## 使用流程

1. **首页** — 查看今日录音统计、最近录音列表
2. **新建录音**（点击 +）— 填写标题、备注、说话人（均可选），点击「开始录音」；或点击「导入音频」从本地选取音频文件
3. **录音中** — 前台服务持续录音，界面实时显示语音转写文本，支持在线/离线双模式
4. **结束录音** — 自动调用 LLM 生成结构化总结（议题 / 结论 / 待办 / 跟进计划），失败时自动重试
5. **查看详情** — 三个 Tab 页切换：音频回放 / 完整转写 / AI 总结，支持重新转写、重新总结、导出分享
6. **历史记录** — 按标题/备注/内容搜索，侧滑删除单条，右上角清空全部

## 项目结构

```
app/src/main/java/com/voicenote/app/
├── VoiceNoteApp.kt                    # Application
├── MainActivity.kt                    # 入口 Activity
├── core/
│   ├── audio/
│   │   ├── AudioCapture.kt            # AudioRecord PCM 采集
│   │   ├── AudioFileManager.kt        # WAV 文件写入（PCM → WAV 头）
│   │   └── AudioImporter.kt           # 外部音频导入 + 后台 ASR/LLM
│   ├── asr/
│   │   ├── ASRMode.kt                 # 在线/离线模式枚举
│   │   ├── ModelQuality.kt            # SenseVoice 模型精度（INT8/FP32）
│   │   ├── FunASRClient.kt            # FunASR WebSocket 客户端（在线）
│   │   ├── OfflineASRClient.kt        # Sherpa-ONNX JNI 客户端（离线）
│   │   └── ASRModelManager.kt         # 离线 ASR 模型下载/上传/删除
│   ├── llm/
│   │   ├── LLMMode.kt                 # 在线/离线模式枚举
│   │   ├── LLMModelInfo.kt            # 离线 LLM 模型信息
│   │   ├── LLMClient.kt              # OpenAI 兼容 LLM 客户端（在线）
│   │   ├── OfflineLLMClient.kt       # llama.cpp JNI 客户端（离线）
│   │   ├── LlamaBridge.kt            # llama.cpp JNI 桥接
│   │   └── LLMModelManager.kt        # 离线 LLM 模型下载/上传/删除
│   ├── service/RecordingService.kt    # 前台服务（录音 + ASR + LLM 编排）
│   ├── network/ConnectivityChecker.kt # ASR/LLM 连接测试
│   ├── common/MemoryWarningBus.kt     # 内存警告事件总线
│   ├── database/                      # Room 数据库（Entity / DAO）
│   └── di/                            # Hilt 模块 + DataStore
├── domain/
│   ├── model/                         # VoiceRecord, VoiceRecordSummary, TodoItem
│   └── repository/                    # Repository 接口
├── data/repository/                   # Repository 实现
└── ui/
    ├── home/                          # 首页仪表盘
    ├── recording/                     # 新建录音 + 实时转写 + 音频导入
    ├── detail/                        # 录音详情（音频 / 转写 / 总结三个 Tab）
    ├── history/                       # 历史记录（搜索 + 侧滑删除）
    ├── settings/                      # API 配置 + ASR/LLM 模式切换 + 模型管理
    ├── navigation/                    # 路由
    └── theme/                         # Material 3 主题
```

原生 JNI 层：

```
app/src/main/cpp/
├── CMakeLists.txt
├── llama_jni.c              # llama.cpp 推理 JNI（LLM 离线）
├── sherpa_onnx_jni.c        # sherpa-onnx 识别 JNI（ASR 离线）
├── include/                 # 第三方 C 头文件
└── llama.cpp/               # llama.cpp 源码
```

## 权限

| 权限 | 用途 |
|---|---|
| RECORD_AUDIO | 录音 |
| INTERNET | 网络通信（ASR + LLM） |
| FOREGROUND_SERVICE | 前台服务运行 |
| FOREGROUND_SERVICE_MICROPHONE | 前台录音（Android 14+） |
| POST_NOTIFICATIONS | 前台服务通知 |
| WAKE_LOCK | 防止 CPU 休眠中断录音 |

## 数据模型

```
VoiceRecord:
  id, title, memo, description, speakers,
  sourceType (RECORDING / IMPORTED),
  startTime, endTime, audioFilePath, transcriptFilePath,
  transcriptText, transcriptStatus (PENDING / PROCESSING / COMPLETED / UNAVAILABLE),
  summary (VoiceRecordSummary), summaryStatus (同上),
  createdAt

VoiceRecordSummary:
  topics, conclusions, todos (TodoItem), nextSteps

TodoItem:
  task, owner, deadline
```

## iOS 版

项目同时提供 iOS 原生版本（SwiftUI + Core Data），功能对等，见 [ios/README.md](ios/README.md)。

## 最低要求

- Android 8.0 (API 26)
- 离线 ASR/LLM 需 arm64-v8a 设备
