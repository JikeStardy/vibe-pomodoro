# NotchPomodoro 🍅

> macOS 刘海屏番茄钟 + Claude Code 智能提示

一款为 MacBook 设计的番茄钟应用，利用屏幕刘海区域（Dynamic Island）显示计时状态和 Claude Code 会话通知，提供沉浸式开发体验。

## 功能特性

### 番茄钟
- 标准番茄工作法：25 分钟工作 / 5 分钟短休息 / 15 分钟长休息
- 每 4 轮工作后自动切换为长休息
- 可选自动开始休息/工作（无需手动切换）
- 工作完成时休息提示弹窗（5 秒自动消失）
- 系统通知提醒
- 会话记录追踪

### Claude Code Hook 提示
- 实时显示 Claude Code 会话状态（处理中 / 等待输入 / 压缩上下文）
- **权限审批**：在刘海区域直接 Allow / Deny 工具调用请求
- 工具名称与参数预览（Bash 命令、文件路径等）
- 会话结束/错误通知（5 秒自动消失）
- Subagent 活动指示
- vibe-notch 冲突检测

### 界面交互
- **闲置态**（idle）：最小化指示器，宽 350×高 38
- **紧凑态**（compact）：计时进行中，显示时间与进度
- **展开态**（expanded）：悬停或点击展开完整控制面板（360×240）
- **设置态**（settings）：配置面板（380×420）
- **Claude 审批态**：权限请求 UI（380×200）
- **Claude 通知态**：任务状态提示（360×140）
- 多显示器支持：可选择在哪些屏幕显示刘海窗口

## 系统要求

- macOS 13.0+
- Swift 5.9+（编译需要）
- MacBook with notch display（推荐，外接屏也可使用）
- Claude Code CLI（Hook 功能需要）

## 构建与安装

```bash
# 编译
swift build

# 直接运行
swift run

# 编译 Release 版本
swift build -c release

# 使用构建脚本（生成 .app）
./build.sh
```

## 使用指南

### 番茄钟操作

| 操作 | 方式 |
|------|------|
| 展开控制面板 | 鼠标悬停或点击刘海区域 |
| 开始工作 | 展开后点击「开始」按钮 |
| 暂停/继续 | 点击暂停按钮 |
| 跳过当前阶段 | 点击跳过按钮 |
| 停止计时 | 点击停止按钮 |
| 打开设置 | 展开面板中点击齿轮图标 |
| 收起面板 | 点击刘海区域或鼠标离开 |

### Claude Code 集成

Hook 系统在应用启动时**自动安装**，无需手动配置：

1. 检测 `~/.claude` 目录是否存在
2. 将 Python hook 脚本写入 `~/.claude/hooks/notch-pomodoro-hook.py`
3. 在 `~/.claude/settings.json` 中注册所有支持的事件
4. 启动 Unix domain socket 服务器监听事件

**权限审批流程**：
1. Claude Code 请求执行敏感操作（如 Bash 命令、文件写入）
2. Hook 脚本通过 socket 发送 PermissionRequest 事件
3. 刘海区域自动切换为审批 UI，显示工具名称和参数
4. 用户点击 Allow（允许）或 Deny（拒绝）
5. 响应通过 socket 返回给 Claude Code（timeout: 86400s）

## 通知场景一览

| Hook 事件 | 状态映射 | 界面响应 |
|-----------|---------|---------|
| UserPromptSubmit | processing | 紧凑态显示处理中 |
| PreToolUse | running_tool | 显示工具名称 |
| PostToolUse | processing | 回到处理中状态 |
| PermissionRequest | waiting_for_approval | 展开审批 UI（Allow/Deny） |
| Notification (idle_prompt) | waiting_for_input | 通知态：等待输入 |
| Stop | waiting_for_input | 通知态：会话停止 |
| StopFailure | error | 通知态：显示错误信息 |
| SubagentStart/Stop | processing | 标记 subagent 活动 |
| SessionStart | waiting_for_input | 会话开始 |
| SessionEnd | ended | 重置为 idle |
| PreCompact | compacting | 显示压缩上下文状态 |
| PostCompact | processing | 回到处理中状态 |

## 架构概览

```
Sources/
├── App/              # 应用入口与生命周期（AppDelegate、通知权限）
├── Models/           # 数据模型（PomodoroConfig、ClaudeSessionPhase、HookEvent）
├── Controllers/      # 窗口管理与 ViewModel
│   ├── NotchDisplayManager    # 多显示器窗口同步
│   └── NotchWindowController  # 单屏刘海窗口 + NotchViewModel
├── Services/         # Claude Hook 服务
│   └── Hooks/
│       ├── HookInstaller      # 自动安装 hook 脚本到 ~/.claude/
│       └── HookSocketServer   # Unix socket 事件接收与权限响应
├── Resources/        # 资源文件（AppIcon、hook Python 脚本）
└── Views/            # SwiftUI 视图（NotchView、SettingsView）
```

## 配置说明

### 番茄钟设置
- 工作时长：5–60 分钟（默认 25）
- 短休息：1–30 分钟（默认 5）
- 长休息：5–60 分钟（默认 15）
- 长休息间隔：2–8 轮（默认 4）
- 自动开始休息 / 自动开始工作

### 显示器选择
- 默认仅在内建显示器（Built-in Display）显示
- 设置面板可勾选多个已连接显示器
- 支持热插拔：屏幕连接/断开时自动同步窗口

## 技术实现

- **Hook 通信**：Unix domain socket `/tmp/notch-pomodoro-claude.sock`（chmod 600）
- **Hook 脚本**：Python 3，自动安装到 `~/.claude/hooks/notch-pomodoro-hook.py`
- **事件总线**：`HookSocketServer` → Combine `PassthroughSubject` → `ClaudeSessionManager` → SwiftUI 视图
- **状态优先级**：设置 > Claude 审批 > 休息提示 > Claude 通知 > 展开 > 紧凑 > 闲置
- **窗口层级**：`statusBar + 1`，覆盖菜单栏，所有 Space 可见
- **动画**：Spring 动画（response: 0.32, damping: 0.72）+ ease-out 窗口缩放

## 注意事项

- **vibe-notch 冲突**：应用会检测 `claude-island-state.py` 是否已注册，避免重复 hook
- **权限超时**：PermissionRequest hook timeout 设为 86400 秒（24 小时），确保用户有充足时间审批
- **通知自动消失**：`waitingForInput` 和 `error` 状态 5 秒后自动回到 idle
- **非 .app 包运行**：通过 `swift run` 运行时跳过通知权限请求（无 bundle ID）
- **Socket 缓冲区**：128KB 读缓冲，支持大型 tool_input 传输

## 许可证

MIT License
