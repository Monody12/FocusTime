import Cocoa
import FlutterMacOS
import EventKit

/// macOS 主窗口控制器，同时承担 EventKit 日历桥接职责。
///
/// `device_calendar` 插件不提供 macOS 实现，因此通过 FlutterMethodChannel
/// ("com.focusmytime.calendar") 手动桥接 EventKit API，
/// 使 Dart 层的 `MacOsCalendarPlugin` 可以像调用 Android/iOS 插件一样操作 macOS 日历。
///
/// 兼容性说明：
/// - macOS 14.0 (Sonoma)+ 使用 `requestFullAccessToEvents` 新 API
/// - macOS 10.15 ~ 13.x (Ventura 等) 使用 `requestAccess(to: .event)` 旧 API
/// - macOS 10.14 及更早版本无需权限请求，直接返回 true
class MainFlutterWindow: NSWindow {
  /// EventKit 事件存储实例，所有日历操作都通过它完成
  let eventStore = EKEventStore()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 注册日历 MethodChannel，将所有 EventKit 操作统一分发到 handleCalendarMethodCall
    let channel = FlutterMethodChannel(name: "com.focusmytime.calendar", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      self.handleCalendarMethodCall(call: call, result: result)
    }

    super.awakeFromNib()
  }

  /// 日历 MethodChannel 统一分发器
  func handleCalendarMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    // MARK: - 权限相关

    /// 检查当前应用是否已获得日历访问权限
    /// macOS 14+ 有 fullAccess / writeOnly / authorized 三种已授权状态
    /// macOS 13 及更早只有 authorized 一种
    case "hasPermissions":
      let status = EKEventStore.authorizationStatus(for: .event)
      if #available(macOS 14.0, *) {
        result(status == .fullAccess || status == .writeOnly || status == .authorized)
      } else {
        result(status == .authorized)
      }

    /// 请求日历访问权限，按 macOS 版本选择对应 API
    /// 注意：权限回调在后台线程，必须切回主线程才能调用 FlutterResult
    case "requestPermissions":
      if #available(macOS 14.0, *) {
        // macOS 14+ Sonoma: 使用新的 Full Access API（替代已废弃的 requestAccess）
        eventStore.requestFullAccessToEvents { granted, error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "PERMISSION_FAILED", message: error.localizedDescription, details: nil))
            } else {
              result(granted)
            }
          }
        }
      } else if #available(macOS 10.15, *) {
        // macOS 10.15 ~ 13.x: 使用旧版 API（Ventura 等系统走这里）
        eventStore.requestAccess(to: .event) { granted, error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "PERMISSION_FAILED", message: error.localizedDescription, details: nil))
            } else {
              result(granted)
            }
          }
        }
      } else {
        // macOS 10.14 及更早：无需权限
        result(true)
      }

    // MARK: - 日历管理

    /// 获取设备上所有日历列表，返回 [{id, name, isReadOnly}]
    case "retrieveCalendars":
      let calendars = eventStore.calendars(for: .event)
      let list = calendars.map { cal -> [String: Any] in
        return [
          "id": cal.calendarIdentifier,
          "name": cal.title,
          "isReadOnly": !cal.allowsContentModifications
        ]
      }
      result(list)

    /// 创建新日历，优先使用本地 (Local) 源，其次回退到 CalDAV 或默认源
    case "createCalendar":
      guard let args = call.arguments as? [String: Any],
            let name = args["name"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        return
      }
      let calendar = EKCalendar(for: .event, eventStore: eventStore)
      calendar.title = name

      // 选择可写入的日历源：优先本地，其次默认日历的源，最后取第一个可用源
      let sources = eventStore.sources.filter { $0.sourceType == .local || $0.sourceType == .calDAV }
      if let source = sources.first(where: { $0.sourceType == .local }) ?? eventStore.defaultCalendarForNewEvents?.source ?? sources.first {
        calendar.source = source
      } else {
        result(FlutterError(code: "NO_CALENDAR_SOURCE", message: "No writable calendar source available", details: nil))
        return
      }

      do {
        try eventStore.saveCalendar(calendar, commit: true)
        result(calendar.calendarIdentifier)
      } catch {
        result(FlutterError(code: "SAVE_FAILED", message: error.localizedDescription, details: nil))
      }

    // MARK: - 事件操作

    /// 创建或更新日历事件（有 eventId 则更新，无则创建）
    /// 传入参数：calendarId, eventId, title, description, start(毫秒时间戳), end(毫秒时间戳)
    /// 返回：保存后的 eventId
    case "createOrUpdateEvent":
      guard let args = call.arguments as? [String: Any],
            let title = args["title"] as? String,
            let startMs = int64Arg(args["start"]),
            let endMs = int64Arg(args["end"]) else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        return
      }

      let calendarId = args["calendarId"] as? String
      let eventId = args["eventId"] as? String
      let description = args["description"] as? String

      // 有 eventId → 复用已有事件（UPDATE），无 → 创建新事件（INSERT）
      var event: EKEvent!
      if let eId = eventId, let existing = eventStore.event(withIdentifier: eId) {
        event = existing
      } else {
        event = EKEvent(eventStore: eventStore)
      }

      // 指定日历 → 使用指定的；否则使用默认日历
      if let cId = calendarId, let cal = eventStore.calendar(withIdentifier: cId) {
        event.calendar = cal
      } else if event.calendar == nil {
        event.calendar = eventStore.defaultCalendarForNewEvents
      }

      event.title = title
      event.notes = description
      // Dart 传入的是毫秒时间戳，需要转换为秒
      event.startDate = Date(timeIntervalSince1970: TimeInterval(startMs) / 1000.0)
      event.endDate = Date(timeIntervalSince1970: TimeInterval(endMs) / 1000.0)

      // 设置事件触发时的闹钟提醒（relativeOffset: 0 = 事件开始时立即提醒）
      event.alarms = [EKAlarm(relativeOffset: 0)]

      do {
        try eventStore.save(event, span: .thisEvent, commit: true)
        if let identifier = event.eventIdentifier {
          result(identifier)
        } else {
          result(FlutterError(code: "SAVE_FAILED", message: "Event saved without identifier", details: nil))
        }
      } catch {
        result(FlutterError(code: "SAVE_FAILED", message: error.localizedDescription, details: nil))
      }

    /// 删除指定事件，事件不存在时视为成功（幂等）
    case "deleteEvent":
      guard let args = call.arguments as? [String: Any],
            let eventId = args["eventId"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        return
      }

      if let event = eventStore.event(withIdentifier: eventId) {
        do {
          try eventStore.remove(event, span: .thisEvent, commit: true)
          result(true)
        } catch {
          result(FlutterError(code: "DELETE_FAILED", message: error.localizedDescription, details: nil))
        }
      } else {
        // 事件不存在也算删除成功（防止因手动删除导致的报错）
        result(true)
      }

    /// 删除整个日历及其所有事件，日历不存在时视为成功
    case "deleteCalendar":
      guard let args = call.arguments as? [String: Any],
            let calendarId = args["calendarId"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        return
      }
      if let cal = eventStore.calendar(withIdentifier: calendarId) {
        do {
          try eventStore.removeCalendar(cal, commit: true)
          result(true)
        } catch {
          result(FlutterError(code: "DELETE_FAILED", message: error.localizedDescription, details: nil))
        }
      } else {
        result(true)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 将 Dart 传入的 Any? 类型安全转换为 Int64
  /// Flutter MethodChannel 在不同平台可能传入 Int、Int64 或 NSNumber 类型
  private func int64Arg(_ value: Any?) -> Int64? {
    if let value = value as? Int64 {
      return value
    }
    if let value = value as? Int {
      return Int64(value)
    }
    if let value = value as? NSNumber {
      return value.int64Value
    }
    return nil
  }
}
