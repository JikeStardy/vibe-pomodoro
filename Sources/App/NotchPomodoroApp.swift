import SwiftUI
import UserNotifications
import Combine

@main
struct NotchPomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var timer: PomodoroTimer!
    private var notchWindowController: NotchWindowController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 请求通知权限
        requestNotificationPermission()
        
        // 初始化番茄钟
        timer = PomodoroTimer()
        
        // 初始化刘海窗口
        notchWindowController = NotchWindowController(timer: timer)
        
        // 根据配置显示/隐藏刘海窗口
        updateNotchVisibility()
        
        // 监听配置变化
        timer.$config
            .sink { [weak self] _ in
                self?.updateNotchVisibility()
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func requestNotificationPermission() {
        // 延迟请求通知权限，确保 app bundle 已就绪
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // 检查是否在有效的 app bundle 中运行
            guard Bundle.main.bundleURL.pathExtension == "app" else {
                print("警告: 未在 .app 包中运行，跳过通知权限请求")
                return
            }
            
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if granted {
                    print("通知权限已授予")
                } else if let error = error {
                    print("通知权限请求失败: \(error)")
                }
            }
            center.delegate = self
        }
    }
    
    private func updateNotchVisibility() {
        if timer.config.showInNotch {
            notchWindowController.show()
        } else {
            notchWindowController.hide()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // 保存状态
        timer.stop()
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 在前台也显示通知
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // 通知点击事件，目前不做特殊处理（菜单栏弹窗已移除）
        completionHandler()
    }
}
