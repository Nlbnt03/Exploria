import Flutter
import UIKit
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var locationChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    registerLocationChannel()
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private var alwaysAuthContinuation: CheckedContinuation<Bool, Never>?
  private let locationManager = CLLocationManager()

  private func registerLocationChannel() {
    if locationChannel != nil {
      return
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "kesfedio/location",
        binaryMessenger: controller.binaryMessenger)
      configureLocationChannel(channel)
      return
    }

    if let registrar = self.registrar(forPlugin: "KesfedioLocationChannel") {
      let channel = FlutterMethodChannel(
        name: "kesfedio/location",
        binaryMessenger: registrar.messenger())
      configureLocationChannel(channel)
    }
  }

  private func configureLocationChannel(_ channel: FlutterMethodChannel) {
    locationChannel = channel
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(false)
        return
      }
      if call.method == "requestAlwaysAuthorization" {
        self.requestAlwaysAuthorization(call, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestAlwaysAuthorization(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    Task {
      let granted = await requestAlwaysAuthorizationOnIos()
      result(granted)
    }
  }

  private func requestAlwaysAuthorizationOnIos() async -> Bool {
    let status = CLLocationManager.authorizationStatus()
    if status == .authorizedAlways {
      return true
    }
    guard status == .authorizedWhenInUse else {
      return false
    }
    return await withCheckedContinuation { continuation in
      alwaysAuthContinuation = continuation
      locationManager.delegate = self
      locationManager.requestAlwaysAuthorization()
      DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
        guard let self = self else { return }
        self.finishAlwaysAuthorization(
          granted: CLLocationManager.authorizationStatus() == .authorizedAlways)
      }
    }
  }

  private func finishAlwaysAuthorization(granted: Bool) {
    alwaysAuthContinuation?.resume(returning: granted)
    alwaysAuthContinuation = nil
  }
}

extension AppDelegate: CLLocationManagerDelegate {
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = CLLocationManager.authorizationStatus()
    if status == .notDetermined { return }
    finishAlwaysAuthorization(granted: status == .authorizedAlways)
  }
}
