import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let appGroupId = "group.com.sneha.iosfinds"
  private let sharedKey = "ShareKey"
  private var shareChannel: FlutterMethodChannel?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NSLog("[AppDelegate:1] didFinishLaunchingWithOptions — launchOptions keys=\(launchOptions?.keys.map { $0.rawValue } ?? [])")
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    NSLog("[AppDelegate:1] super.application result=\(result)")
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    NSLog("[AppDelegate:engine] didInitializeImplicitFlutterEngine — registering plugins")
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupMethodChannel(messenger: engineBridge.applicationRegistrar.messenger())
    NSLog("[AppDelegate:engine] share_extension method channel ready")

    DispatchQueue.main.async { [weak self] in
      self?.checkAndProcessSharedData()
      self?.handleShareExtensionURL()
    }
  }
  
  private func setupMethodChannel(messenger: FlutterBinaryMessenger) {
    NSLog("[AppDelegate:ch] setupMethodChannel — creating FlutterMethodChannel 'com.collectio.app/share_extension'")
    let channel = FlutterMethodChannel(name: "com.collectio.app/share_extension",
                                      binaryMessenger: messenger)
    self.shareChannel = channel
    channel.setMethodCallHandler { [weak self] (call, result) in
      NSLog("[AppDelegate:ch] method call received — method='\(call.method)' args=\(String(describing: call.arguments))")
      switch call.method {
      case "getSharedUrl":
        self?.getSharedUrl(result: result)
      case "clearSharedUrl":
        self?.clearSharedUrl(result: result)
      default:
        NSLog("[AppDelegate:ch] unknown method '\(call.method)' — returning FlutterMethodNotImplemented")
        result(FlutterMethodNotImplemented)
      }
    }
    NSLog("[AppDelegate:ch] method call handler installed")
  }
  
  private func getSharedUrl(result: @escaping FlutterResult) {
    NSLog("[AppDelegate:get] getSharedUrl — checking appGroup '\(appGroupId)' key '\(sharedKey)'")
    if let userDefaults = UserDefaults(suiteName: appGroupId) {
      let allKeys = userDefaults.dictionaryRepresentation().keys.sorted()
      NSLog("[AppDelegate:get] appGroup UserDefaults keys=\(allKeys)")
      if let sharedUrl = userDefaults.string(forKey: sharedKey), !sharedUrl.isEmpty {
        NSLog("[AppDelegate:get] FOUND in appGroup: '\(sharedUrl)'")
        result(sharedUrl)
        return
      } else {
        NSLog("[AppDelegate:get] NOT FOUND in appGroup (value=\(String(describing: userDefaults.object(forKey: sharedKey))))")
      }
    } else {
      NSLog("[AppDelegate:get] ERROR: could not open UserDefaults for appGroup '\(appGroupId)'")
    }
    let fallback = UserDefaults.standard.string(forKey: "shared_url_from_extension")
    NSLog("[AppDelegate:get] fallback standard UserDefaults value='\(fallback ?? "nil")' — returning this")
    result(fallback)
  }
  
  private func clearSharedUrl(result: @escaping FlutterResult) {
    NSLog("[AppDelegate:clear] clearSharedUrl — removing from appGroup '\(appGroupId)' and standard UserDefaults")
    if let userDefaults = UserDefaults(suiteName: appGroupId) {
      userDefaults.removeObject(forKey: sharedKey)
      let synced = userDefaults.synchronize()
      NSLog("[AppDelegate:clear] appGroup removal done, synchronize=\(synced)")
    } else {
      NSLog("[AppDelegate:clear] ERROR: could not open UserDefaults for appGroup '\(appGroupId)'")
    }
    UserDefaults.standard.removeObject(forKey: "shared_url_from_extension")
    let synced = UserDefaults.standard.synchronize()
    NSLog("[AppDelegate:clear] standard UserDefaults removal done, synchronize=\(synced)")
    result(true)
  }
  
  // Called by SceneDelegate when collectio://share URL is received
  func handleShareExtensionURL(retryCount: Int = 0) {
    NSLog("[AppDelegate:url] handleShareExtensionURL — checking appGroup '\(appGroupId)' key '\(sharedKey)'")
    if let userDefaults = UserDefaults(suiteName: appGroupId),
       let sharedUrl = userDefaults.string(forKey: sharedKey),
       !sharedUrl.isEmpty {
      NSLog("[AppDelegate:url] found URL '\(sharedUrl)' — shareChannel=\(shareChannel != nil ? "SET" : "NIL")")
      if shareChannel == nil {
        if retryCount < 10 {
          NSLog("[AppDelegate:url] shareChannel nil — retry \(retryCount + 1)/10 in 300ms")
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.handleShareExtensionURL(retryCount: retryCount + 1)
          }
        } else {
          NSLog("[AppDelegate:url] shareChannel still nil after retries — Flutter will read via getSharedUrl on resume")
        }
        return
      }
      shareChannel?.invokeMethod("shareReceived", arguments: sharedUrl)
      NSLog("[AppDelegate:url] invokeMethod 'shareReceived' called")
    } else {
      NSLog("[AppDelegate:url] handleShareExtensionURL — no URL found in appGroup UserDefaults")
    }
  }
  
  // Fallback for non-scene based URL handling
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    NSLog("[AppDelegate:openURL] application(_:open:) — url='\(url)' scheme='\(url.scheme ?? "nil")' host='\(url.host ?? "nil")'")
    if url.scheme == "collectio" && url.host == "share" {
      NSLog("[AppDelegate:openURL] collectio://share matched — calling handleShareExtensionURL")
      handleShareExtensionURL()
      return true
    }
    NSLog("[AppDelegate:openURL] not a share URL — delegating to super")
    return super.application(app, open: url, options: options)
  }
  
  private func checkAndProcessSharedData() {
    NSLog("[AppDelegate:launch] checkAndProcessSharedData — checking appGroup '\(appGroupId)' key '\(sharedKey)'")
    guard let userDefaults = UserDefaults(suiteName: appGroupId),
          let sharedUrl = userDefaults.string(forKey: sharedKey),
          !sharedUrl.isEmpty else {
      NSLog("[AppDelegate:launch] checkAndProcessSharedData — no pending URL found")
      return
    }
    
    NSLog("[AppDelegate:launch] Found shared URL at launch: '\(sharedUrl)'")
    
    UserDefaults.standard.set(sharedUrl, forKey: "shared_url_from_extension")
    let synced = UserDefaults.standard.synchronize()
    NSLog("[AppDelegate:launch] Copied to standard UserDefaults, synchronize=\(synced)")
  }
}
