import CoreBluetooth
import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // With UIScene, plugins register after launch, too late for BGTaskScheduler,
    // so the sync handler is registered here; Dart then submits the request.
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "gbs.openring.app.sync")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OpenRingPermissions")
    else { return }
    PermissionsChannel.shared.attach(registrar.messenger())
  }
}

final class PermissionsChannel: NSObject, CBCentralManagerDelegate {
  static let shared = PermissionsChannel()

  private var channel: FlutterMethodChannel?
  private var central: CBCentralManager?
  private var pendingBluetooth: [FlutterResult] = []

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "gbs.openring.app/permissions", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let name = call.arguments as? String
    switch (call.method, name) {
    case ("status", "bluetooth"):
      result(bluetoothStatus())
    case ("request", "bluetooth"):
      requestBluetooth(result)
    case ("status", "notifications"):
      notificationStatus(result)
    case ("request", "notifications"):
      requestNotifications(result)
    case ("openSettings", _):
      openSettings()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func bluetoothStatus() -> String {
    switch CBManager.authorization {
    case .allowedAlways: return "granted"
    case .denied, .restricted: return "permanentlyDenied"
    default: return "denied"
    }
  }

  // Creating a central manager is what shows the Bluetooth prompt; the
  // delegate fires once the user has answered.
  private func requestBluetooth(_ result: @escaping FlutterResult) {
    guard CBManager.authorization == .notDetermined else {
      result(bluetoothStatus())
      return
    }
    pendingBluetooth.append(result)
    guard central == nil else { return }
    central = CBCentralManager(
      delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard CBManager.authorization != .notDetermined else { return }
    let status = bluetoothStatus()
    let waiting = pendingBluetooth
    pendingBluetooth = []
    self.central = nil
    waiting.forEach { $0(status) }
  }

  private func notificationStatus(_ result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let status: String
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral: status = "granted"
      case .denied: status = "permanentlyDenied"
      default: status = "denied"
      }
      DispatchQueue.main.async { result(status) }
    }
  }

  private func requestNotifications(_ result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      [weak self] _, _ in
      DispatchQueue.main.async { self?.notificationStatus(result) }
    }
  }

  private func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}
