import Flutter
import UIKit
import AVFoundation
import WebKit
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var cookieChannelAttached = false
  private var cookieChannelAttempts = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("[AppDelegate] AudioSession setup error: \(error)")
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.valapp.mobile.wishlist-refresh",
      frequency: NSNumber(value: 3 * 60 * 60)
    )
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Attach once the root FlutterViewController exists; retry from the
    // implicit-engine callback below if it is not attached yet.
    attachCookieChannel()
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    attachCookieChannel()
  }

  /// Audit H4: exposes the shared WKWebsiteDataStore cookies (INCLUDING
  /// HttpOnly `ssid`) to Dart — `document.cookie` can never see them.
  /// Idempotent: re-setting a handler on the same channel is harmless.
  private func attachCookieChannel() {
    guard !cookieChannelAttached else { return }
    guard let controller = window?.rootViewController as? FlutterViewController else {
      // Implicit engines may attach the root VC slightly later; retry a few
      // times, then give up silently (Dart falls back to JS capture).
      cookieChannelAttempts += 1
      if cookieChannelAttempts < 10 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          self?.attachCookieChannel()
        }
      }
      return
    }
    cookieChannelAttached = true

    let channel = FlutterMethodChannel(
      name: "valapp/native_cookies",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "getCookies" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let urlString = args?["url"] as? String ?? ""
      let host = URL(string: urlString)?.host ?? ""

      WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
        var pairs: [String] = []
        for cookie in cookies {
          if Self.cookieMatchesHost(cookie.domain, host: host) {
            pairs.append("\(cookie.name)=\(cookie.value)")
          }
        }
        result(pairs.joined(separator: "; "))
      }
    }
  }

  /// Tolerant domain match: exact host, dot-suffix, or any riotgames.com
  /// cookie (Riot rotates between auth.riotgames.com and .riotgames.com).
  private static func cookieMatchesHost(_ domain: String, host: String) -> Bool {
    let d = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
    if d.isEmpty || host.isEmpty { return false }
    if d == host || host.hasSuffix("." + d) || d.hasSuffix("." + host) { return true }
    return d.hasSuffix("riotgames.com")
  }
}
