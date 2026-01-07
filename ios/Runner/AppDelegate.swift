import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    self.registerTbWebAuth()
    self.registerEspProvisioning()

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerTbWebAuth() {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "tb_web_auth", binaryMessenger: controller.binaryMessenger)
    let instance = TbWebAuthHandler()
    channel.setMethodCallHandler({
          (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
        instance.handle(call, result: result)
    })
  }

  private func registerEspProvisioning() {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "esp_provisioning", binaryMessenger: controller.binaryMessenger)
    let instance = EspProvisioningHandler()
    channel.setMethodCallHandler({
          (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
        instance.handle(call, result: result)
    })
  }
}
