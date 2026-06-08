# NotchPomodoro - MacBook 灵动岛番茄钟

一款为 MacBook 设计的番茄钟应用，在屏幕刘海区域（灵动岛）显示计时器状态，提供沉浸式的专注体验。

## 功能特性

### 核心功能
- **番茄工作法**：25分钟工作 + 5分钟短休息 + 15分钟长休息
- **灵动岛显示**：在 MacBook 刘海区域实时显示计时器状态
- **菜单栏集成**：在菜单栏显示计时器，点击展开详细控制面板
- **自定义时长**：可配置工作、短休息、长休息的时长
- **自动切换**：可选自动开始休息/工作
- **通知提醒**：计时结束时发送系统通知

### 界面交互
- **紧凑模式**：刘海区域显示时间和进度条
- **展开模式**：点击展开显示完整控制按钮
- **进度可视化**：环形进度条和线性进度条双重显示
- **状态图标**：根据当前状态显示不同图标和颜色

## 系统要求

- macOS 13.0 或更高版本
- MacBook Pro（带刘海屏幕）或其他 Mac 电脑
- Xcode 15.0+（编译需要）

## 安装与运行

### 方法一：使用 Swift Package Manager

```bash
cd NotchPomodoro
swift build
swift run
```

### 方法二：使用 Xcode

1. 打开 Xcode
2. 选择 "Open Existing Project"
3. 选择 `NotchPomodoro` 文件夹
4. 等待 Swift Package 解析完成
5. 点击运行按钮 (Cmd+R)

### 方法三：编译为独立应用

```bash
# 编译 Release 版本
swift build -c release

# 复制应用到 Applications 文件夹
cp -r .build/release/NotchPomodoro.app /Applications/
```

## 使用说明

### 基本操作

1. **开始工作**：点击菜单栏图标或刘海区域，选择"开始工作"
2. **暂停/继续**：点击暂停按钮
3. **跳过当前阶段**：点击跳过按钮进入下一阶段
4. **停止计时**：点击停止按钮结束当前计时

### 刘海区域交互

- **单击**：展开/收起详细控制面板
- **拖动**：可以微调窗口位置

### 设置项

- **工作时长**：5-60分钟，默认25分钟
- **短休息**：1-30分钟，默认5分钟
- **长休息**：5-60分钟，默认15分钟
- **长休息间隔**：2-8轮，默认4轮
- **自动开始休息**：工作结束后自动进入休息
- **自动开始工作**：休息结束后自动开始工作
- **刘海区域显示**：在刘海区域显示计时器
- **菜单栏显示**：在菜单栏显示计时器状态

## 项目结构

```
NotchPomodoro/
├── Package.swift                 # Swift Package 配置
└── Sources/
    ├── App/
    │   ├── NotchPomodoroApp.swift    # 应用入口
    │   ├── Info.plist                # 应用配置
    │   └── NotchPomodoro.entitlements
    ├── Models/
    │   ├── PomodoroModels.swift      # 数据模型
    │   └── PomodoroTimer.swift       # 计时器逻辑
    ├── Views/
    │   ├── NotchView.swift           # 刘海区域视图
    │   └── SettingsView.swift        # 设置视图
    └── Controllers/
        ├── MenuBarController.swift   # 菜单栏控制器
        └── NotchWindowController.swift # 刘海窗口控制器
```

## 技术栈

- **SwiftUI**：声明式 UI 框架
- **AppKit**：macOS 原生窗口和菜单栏控制
- **Combine**：响应式编程框架
- **UserNotifications**：系统通知

## 开发计划

- [ ] 添加历史记录统计
- [ ] 支持自定义主题颜色
- [ ] 添加白噪音功能
- [ ] 支持快捷键操作
- [ ] 添加 DND（勿扰模式）联动
- [ ] 支持多任务切换

## 参考项目

- [TomatoBar](https://github.com/ivoronin/TomatoBar) - macOS 菜单栏番茄钟

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！
