import AdMixerMediation
import Flutter
import UIKit

public final class NapMxFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let pluginVersion = "0.1.0"
  private var eventSink: FlutterEventSink?
  private var initialized = false
  private var fingerprint: String?
  private var requests: [String: NapMxFullscreenRequest] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NapMxFlutterPlugin()
    let methods = FlutterMethodChannel(
      name: "nap_mx_flutter/methods",
      binaryMessenger: registrar.messenger()
    )
    let events = FlutterEventChannel(
      name: "nap_mx_flutter/events",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methods)
    events.setStreamHandler(instance)
    registrar.register(
      NapMxAdViewFactory(messenger: registrar.messenger(), emit: instance.emit),
      withId: "nap_mx_flutter/ad_view"
    )
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    dispatchPrecondition(condition: .onQueue(.main))
    switch call.method {
    case "initialize": initialize(call, result: result)
    case "getSdkInfo":
      let bundle = Bundle(for: AMMediation.self)
      result([
        "platform": "ios",
        "pluginVersion": Self.pluginVersion,
        "sdkVersion": bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
        "adapterVersions": NSNull(),
      ])
    case "loadFullscreen": loadFullscreen(call, result: result)
    case "showFullscreen": showFullscreen(call, result: result)
    case "disposeFullscreen": disposeFullscreen(call, result: result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func initialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let mediaKeyText = args["mediaKey"] as? String,
          let mediaKey = Int(mediaKeyText),
          let rawUnits = args["adUnitIds"] as? [String: String],
          !rawUnits.isEmpty else {
      result(FlutterError(
        code: "invalid_configuration",
        message: "iOS requires a numeric mediaKey and at least one numeric ad unit ID.",
        details: nil
      ))
      return
    }
    let unitValues = rawUnits.values.sorted()
    let numericUnits = Set(unitValues.compactMap(Int.init))
    guard numericUnits.count == unitValues.count else {
      result(FlutterError(
        code: "invalid_ad_unit",
        message: "Every iOS ad unit ID must be a base-10 integer.",
        details: nil
      ))
      return
    }
    if args["testMode"] as? Bool == true {
      result(FlutterError(
        code: "test_mode_unsupported",
        message: "The nap mx iOS SDK has no global test-mode API. Use assigned test units and network debug tools.",
        details: nil
      ))
      return
    }
    if let mediation = args["mediation"] as? [String: Any], !mediation.isEmpty {
      result(FlutterError(
        code: "mediation_configuration_unsupported",
        message: "Initialize optional iOS network SDKs in AppDelegate or SceneDelegate as documented by each adapter.",
        details: nil
      ))
      return
    }
    let newFingerprint = "\(mediaKey)|\(unitValues.joined(separator: ","))"
    if initialized {
      if fingerprint == newFingerprint { result(nil) }
      else {
        result(FlutterError(
          code: "already_initialized",
          message: "nap mx was initialized with other values.",
          details: nil
        ))
      }
      return
    }

    if let privacy = args["privacy"] as? [String: Any] {
      let consent = AMMConsent()
      consent.gdprConsent = consentValue(privacy["gdprConsent"] as? String)
      consent.usSaleConsent = consentValue(privacy["usSaleConsent"] as? String)
      consent.childDirected = consentValue(privacy["childDirected"] as? String)
      consent.underAgeOfConsent = consentValue(privacy["underAgeOfConsent"] as? String)
      AMMediation.shared.setConsent(consent)
    }
    let logLevel = args["logLevel"] as? String
    AMMediation.shared.setDebugEnabled(isEnabled: logLevel == "debug")
    AMMediation.shared.initialize(mediaKey: mediaKey, adunitID: numericUnits)
    initialized = true
    fingerprint = newFingerprint
    result(nil)
    emit(baseEvent("initializationSucceeded"))
  }

  private func consentValue(_ value: String?) -> AMMConsentStatus {
    switch value {
    case "granted": return .granted
    case "denied": return .denied
    default: return .unspecified
    }
  }

  private func loadFullscreen(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard initialized else {
      result(FlutterError(code: "not_initialized", message: "Call initialize first.", details: nil))
      return
    }
    guard let args = call.arguments as? [String: Any],
          let requestId = args["requestId"] as? String,
          let format = args["format"] as? String,
          let adUnitText = args["adUnitId"] as? String,
          let adUnitId = Int(adUnitText) else {
      result(FlutterError(
        code: "invalid_request",
        message: "requestId, format, and a numeric iOS adUnitId are required.",
        details: nil
      ))
      return
    }
    guard ["interstitial", "interstitialVideo", "rewarded"].contains(format) else {
      result(FlutterError(code: "unsupported", message: "Unsupported format: \(format)", details: nil))
      return
    }
    guard requests[requestId] == nil else {
      result(FlutterError(code: "duplicate_request", message: "requestId is already active.", details: nil))
      return
    }
    let timeout = min(max((args["timeoutMs"] as? NSNumber)?.doubleValue ?? 30_000, 1_000), 120_000)
    let customParams = args["customParams"] as? [String: String]
    let request = NapMxFullscreenRequest(
      id: requestId,
      format: format,
      adUnitText: adUnitText,
      adUnitId: adUnitId,
      customParams: customParams,
      timeout: timeout / 1_000,
      completion: result,
      emit: emit,
      finished: { [weak self] id in self?.requests.removeValue(forKey: id) }
    )
    requests[requestId] = request
    emit(request.event("loadStarted"))
    request.load()
  }

  private func showFullscreen(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let requestId = args["requestId"] as? String,
          let request = requests[requestId] else {
      result(FlutterError(code: "not_loaded", message: "No active request.", details: nil))
      return
    }
    request.show(result: result)
  }

  private func disposeFullscreen(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if let args = call.arguments as? [String: Any],
       let requestId = args["requestId"] as? String {
      requests.removeValue(forKey: requestId)?.dispose(notify: true)
    }
    result(nil)
  }

  private func emit(_ event: [String: Any]) {
    if Thread.isMainThread { eventSink?(event) }
    else { DispatchQueue.main.async { [weak self] in self?.eventSink?(event) } }
  }
}

private final class NapMxFullscreenRequest: NSObject,
    AMMInterstitialDelegate, AMMVideoInterstitialDelegate, AMMRewardVideoDelegate {
  let id: String
  let format: String
  let adUnitText: String
  private let adUnitId: Int
  private let customParams: [String: String]?
  private let emitBlock: ([String: Any]) -> Void
  private let finishedBlock: (String) -> Void
  private var loadResult: FlutterResult?
  private var showResult: FlutterResult?
  private var timeoutWork: DispatchWorkItem?
  private var interstitial: AMMInterstitial?
  private var video: AMMVideoInterstitial?
  private var reward: AMMRewardVideo?
  private var network: String?
  private var state = "loading"
  private var disposed = false
  private var rewardSent = false
  private let startedAt = Date()

  init(
    id: String,
    format: String,
    adUnitText: String,
    adUnitId: Int,
    customParams: [String: String]?,
    timeout: TimeInterval,
    completion: @escaping FlutterResult,
    emit: @escaping ([String: Any]) -> Void,
    finished: @escaping (String) -> Void
  ) {
    self.id = id
    self.format = format
    self.adUnitText = adUnitText
    self.adUnitId = adUnitId
    self.customParams = customParams
    loadResult = completion
    emitBlock = emit
    finishedBlock = finished
    super.init()
    let work = DispatchWorkItem { [weak self] in
      self?.failLoad(code: "timeout", message: "Plugin load timeout.", nativeCode: -8)
    }
    timeoutWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
  }

  func load() {
    switch format {
    case "interstitial":
      AMMInterstitial.loadAd(adUnitID: adUnitId, config: AMMInterstitialConfig()) {
        [weak self] ad, adapterType, error in
        guard let self else { return }
        if let error { self.failLoad(error: error); return }
        guard let ad else { self.failLoad(code: "load_failed", message: "SDK returned no ad.", nativeCode: -1); return }
        self.interstitial = ad
        ad.delegate = self
        self.loaded(network: String(describing: adapterType))
      }
    case "interstitialVideo":
      AMMVideoInterstitial.loadAd(adUnitID: adUnitId) { [weak self] ad, adapterType, error in
        guard let self else { return }
        if let error { self.failLoad(error: error); return }
        guard let ad else { self.failLoad(code: "load_failed", message: "SDK returned no ad.", nativeCode: -1); return }
        self.video = ad
        ad.delegate = self
        self.loaded(network: String(describing: adapterType))
      }
    case "rewarded":
      AMMRewardVideo.loadAd(adUnitID: adUnitId, customParam: customParams) {
        [weak self] ad, adapterType, error in
        guard let self else { return }
        if let error { self.failLoad(error: error); return }
        guard let ad else { self.failLoad(code: "load_failed", message: "SDK returned no ad.", nativeCode: -1); return }
        self.reward = ad
        ad.delegate = self
        self.loaded(network: String(describing: adapterType))
      }
    default: failLoad(code: "unsupported", message: "Unsupported format.", nativeCode: -1)
    }
  }

  private func loaded(network: String) {
    guard !disposed, state == "loading" else { dispose(notify: false); return }
    timeoutWork?.cancel()
    timeoutWork = nil
    self.network = network
    state = "loaded"
    loadResult?(nil)
    loadResult = nil
    emitBlock(event("loaded"))
  }

  func show(result: @escaping FlutterResult) {
    guard state == "loaded" else {
      result(FlutterError(code: "not_loaded", message: "Ad is in state \(state).", details: nil))
      return
    }
    guard let root = activeViewController() else {
      result(FlutterError(code: "no_view_controller", message: "No active view controller.", details: nil))
      return
    }
    state = "showing"
    showResult = result
    if let interstitial { interstitial.show(rootViewController: root) }
    else if let video { video.show(rootViewController: root) }
    else if let reward { reward.show(rootViewController: root) }
    else {
      state = "failed"
      showResult = nil
      result(FlutterError(code: "not_loaded", message: "Loaded ad instance is unavailable.", details: nil))
    }
  }

  private func didShow() {
    guard !disposed else { return }
    showResult?(nil)
    showResult = nil
    emitBlock(event("shown"))
  }

  private func didFailShow(_ error: Error?) {
    guard !disposed else { return }
    state = "failed"
    let nsError = error as NSError?
    showResult?(FlutterError(
      code: "show_failed",
      message: error?.localizedDescription ?? "Ad show failed.",
      details: nsError?.code
    ))
    showResult = nil
    let code = (error as NSError?)?.code ?? -5
    emitBlock(errorEvent(
      "showFailed",
      code: "show_failed",
      message: error?.localizedDescription ?? "Ad show failed.",
      nativeCode: code
    ))
  }

  private func didClose() {
    guard !disposed else { return }
    if showResult != nil {
      showResult?(FlutterError(
        code: "show_failed",
        message: "Ad closed before a show confirmation.",
        details: nil
      ))
      showResult = nil
    }
    emitBlock(event("closed"))
    dispose(notify: false)
    finishedBlock(id)
  }

  private func failLoad(error: Error) {
    let nsError = error as NSError
    failLoad(code: "load_failed", message: error.localizedDescription, nativeCode: nsError.code)
  }

  private func failLoad(code: String, message: String, nativeCode: Int) {
    guard !disposed, state == "loading" else { return }
    state = "failed"
    timeoutWork?.cancel()
    timeoutWork = nil
    loadResult?(FlutterError(code: code, message: message, details: nativeCode))
    loadResult = nil
    emitBlock(errorEvent("loadFailed", code: code, message: message, nativeCode: nativeCode))
    dispose(notify: false)
    finishedBlock(id)
  }

  func dispose(notify: Bool) {
    guard !disposed else { return }
    disposed = true
    state = "disposed"
    timeoutWork?.cancel()
    timeoutWork = nil
    loadResult?(FlutterError(code: "cancelled", message: "Ad request was disposed.", details: nil))
    showResult?(FlutterError(code: "cancelled", message: "Ad request was disposed.", details: nil))
    loadResult = nil
    showResult = nil
    interstitial?.stop()
    video?.stop()
    reward?.stop()
    interstitial = nil
    video = nil
    reward = nil
    if notify { emitBlock(event("disposed")) }
  }

  func event(_ type: String) -> [String: Any] {
    [
      "type": type,
      "timestampMs": Int(Date().timeIntervalSince1970 * 1_000),
      "requestId": id,
      "format": format,
      "adUnitId": adUnitText,
      "network": network ?? NSNull(),
      "elapsedMs": Int(Date().timeIntervalSince(startedAt) * 1_000),
    ]
  }

  private func errorEvent(_ type: String, error: Error) -> [String: Any] {
    let nsError = error as NSError
    return errorEvent(type, code: "load_failed", message: error.localizedDescription, nativeCode: nsError.code)
  }

  private func errorEvent(
    _ type: String, code: String, message: String, nativeCode: Int
  ) -> [String: Any] {
    var value = event(type)
    value["error"] = [
      "code": code,
      "message": message,
      "nativeCode": nativeCode,
      "isNoFill": nativeCode == -1,
      "isTimeout": nativeCode == -8,
    ]
    return value
  }

  func onSuccessShowInterstitial() { didShow() }
  func onFailShowInterstitial(error: Error?) { didFailShow(error) }
  func onClickInterstitial() { if !disposed { emitBlock(event("clicked")) } }
  func onCloseInterstitial() { didClose() }

  func onSuccessShowVideoInterstitial() { didShow() }
  func onFailShowVideoInterstitial(error: Error?) { didFailShow(error) }
  func onCloseVideoInterstitial() { didClose() }
  func onClickVideoInterstitial() { if !disposed { emitBlock(event("clicked")) } }
  func onCompleteVideoInterstitial() { if !disposed { emitBlock(event("completed")) } }

  func onSuccessShowReward() { didShow() }
  func onFailShowReward(error: Error?) { didFailShow(error) }
  func onCloseRewardVideo() { didClose() }
  func onClickRewardVideo() { if !disposed { emitBlock(event("clicked")) } }
  func onRewardVideoComplete() { if !disposed { emitBlock(event("completed")) } }
  func onRewardVideoEarned(rewardInfo: RewardInfo) {
    guard !rewardSent, !disposed else { return }
    rewardSent = true
    var value = event("rewarded")
    value["reward"] = ["transactionId": rewardInfo.transactionId ?? ""]
    emitBlock(value)
  }
}

private final class NapMxAdViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  private let emitBlock: ([String: Any]) -> Void

  init(messenger: FlutterBinaryMessenger, emit: @escaping ([String: Any]) -> Void) {
    self.messenger = messenger
    emitBlock = emit
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NapMxPlatformAdView(
      frame: frame,
      viewId: viewId,
      args: args as? [String: Any] ?? [:],
      messenger: messenger,
      emit: emitBlock
    )
  }
}

private final class NapMxPlatformAdView: NSObject, FlutterPlatformView,
    AMMBannerViewDelegate, AMMVideoViewDelegate, AMMNativeDelegate {
  private let container: UIView
  private let viewId: Int64
  private let format: String
  private let adUnitText: String
  private let emitBlock: ([String: Any]) -> Void
  private let channel: FlutterMethodChannel
  private var startedAt = Date()
  private var banner: AMMBannerView?
  private var video: AMMVideoView?
  private var native: AMMNativeAdViewContainer?
  private var disposed = false
  private var loading = false

  init(
    frame: CGRect,
    viewId: Int64,
    args: [String: Any],
    messenger: FlutterBinaryMessenger,
    emit: @escaping ([String: Any]) -> Void
  ) {
    container = UIView(frame: frame)
    self.viewId = viewId
    format = args["format"] as? String ?? ""
    adUnitText = args["adUnitId"] as? String ?? ""
    emitBlock = emit
    channel = FlutterMethodChannel(name: "nap_mx_flutter/view/\(viewId)", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "disposed", message: nil, details: nil)); return }
      switch call.method {
      case "load": self.load(result: result)
      case "cancel": self.release(final: false); result(nil)
      case "dispose": self.release(final: true); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    if args["autoLoad"] as? Bool == true { load(result: { _ in }) }
  }

  func view() -> UIView { container }

  private func load(result: @escaping FlutterResult) {
    guard !disposed else { result(FlutterError(code: "disposed", message: nil, details: nil)); return }
    guard !loading else { result(FlutterError(code: "already_loading", message: nil, details: nil)); return }
    guard let adUnitId = Int(adUnitText), let root = activeViewController() else {
      result(FlutterError(
        code: "invalid_request",
        message: "A numeric iOS adUnitId and active view controller are required.",
        details: nil
      ))
      return
    }
    releaseAds()
    loading = true
    startedAt = Date()
    emit("loadStarted")
    result(nil)
    switch format {
    case "banner":
      AMMBannerView.loadAd(adUnitID: adUnitId, rootViewController: root) {
        [weak self] ad, adapterType, error in
        guard let self else { return }
        if let error { self.failed(error); return }
        guard let ad else { self.failed(nil); return }
        self.banner = ad
        ad.delegate = self
        self.attach(ad)
        self.loaded(adapterType)
      }
    case "inlineVideo":
      AMMVideoView.loadAd(adUnitID: adUnitId, rootViewController: root) {
        [weak self] ad, adapterType, error in
        guard let self else { return }
        if let error { self.failed(error); return }
        guard let ad else { self.failed(nil); return }
        self.video = ad
        ad.delegate = self
        self.attach(ad)
        self.loaded(adapterType)
      }
    case "native":
      guard let nativeView = loadNativeTemplate() else {
        failedMessage("Native template resource is unavailable.")
        return
      }
      AMMNativeAdViewContainer.loadAd(
        adUnitID: adUnitId,
        rootViewController: root,
        nativeAdView: nativeView
      ) { [weak self] ad, adapterType, error in
        guard let self else { return }
        if let error { self.failed(error); return }
        guard let ad else { self.failed(nil); return }
        self.native = ad
        ad.delegate = self
        self.attach(ad)
        self.loaded(adapterType)
      }
    default: failedMessage("Unsupported view format: \(format)")
    }
  }

  private func attach(_ ad: UIView) {
    container.subviews.forEach { $0.removeFromSuperview() }
    ad.frame = container.bounds
    ad.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(ad)
    if format == "native" {
      let label = UILabel(frame: CGRect(x: 6, y: 6, width: 22, height: 16))
      label.text = "Ad"
      label.font = .systemFont(ofSize: 10, weight: .semibold)
      label.textAlignment = .center
      label.textColor = .white
      label.backgroundColor = UIColor.black.withAlphaComponent(0.62)
      label.accessibilityLabel = "Advertisement"
      container.addSubview(label)
    }
  }

  private func loaded(_ adapterType: Any) {
    guard !disposed else { releaseAds(); return }
    loading = false
    emit("loaded", network: String(describing: adapterType))
  }

  private func failed(_ error: Error?) {
    guard !disposed else { return }
    let nsError = error as NSError?
    failedMessage(error?.localizedDescription ?? "SDK returned no ad.", nativeCode: nsError?.code)
  }

  private func failedMessage(_ message: String, nativeCode: Int? = nil) {
    guard !disposed else { return }
    loading = false
    var value = event("loadFailed")
    value["error"] = [
      "code": "load_failed",
      "message": message,
      "nativeCode": nativeCode ?? NSNull(),
      "isNoFill": nativeCode == -1,
      "isTimeout": nativeCode == -8,
    ]
    emitBlock(value)
  }

  private func release(final: Bool) {
    loading = false
    releaseAds()
    emit(final ? "disposed" : "cancelled")
    if final { disposed = true; channel.setMethodCallHandler(nil) }
  }

  private func releaseAds() {
    banner?.stop(); video?.stop(); native?.stop()
    banner = nil; video = nil; native = nil
    container.subviews.forEach { $0.removeFromSuperview() }
  }

  private func emit(_ type: String, network: String? = nil) {
    var value = event(type)
    value["network"] = network ?? NSNull()
    emitBlock(value)
  }

  private func event(_ type: String) -> [String: Any] {
    [
      "type": type,
      "timestampMs": Int(Date().timeIntervalSince1970 * 1_000),
      "viewId": Int(viewId),
      "format": format,
      "adUnitId": adUnitText,
      "elapsedMs": Int(Date().timeIntervalSince(startedAt) * 1_000),
    ]
  }

  func onSuccessShowBanner() { emit("shown") }
  func onClickBanner() { emit("clicked") }
  func onSuccessShowVideo() { emit("shown") }
  func onClickVideo() { emit("clicked") }
  func onSkipVideo() { emit("skipped") }
  func onCompleteVideo() { emit("completed") }
  func onSuccessShowNative() { emit("shown") }
  func onClickNative() { emit("clicked") }

  deinit { releaseAds() }
}

private func baseEvent(_ type: String) -> [String: Any] {
  ["type": type, "timestampMs": Int(Date().timeIntervalSince1970 * 1_000)]
}

private func activeViewController() -> UIViewController? {
  let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
  let window = scenes.first(where: { $0.activationState == .foregroundActive })?
    .windows.first(where: \.isKeyWindow)
  var controller = window?.rootViewController
  while true {
    if let presented = controller?.presentedViewController { controller = presented; continue }
    if let navigation = controller as? UINavigationController { controller = navigation.visibleViewController; continue }
    if let tabs = controller as? UITabBarController { controller = tabs.selectedViewController; continue }
    break
  }
  return controller
}

private func resourceBundle() -> Bundle {
  #if SWIFT_PACKAGE
  return Bundle.module
  #else
  let host = Bundle(for: NapMxFlutterPlugin.self)
  if let url = host.url(forResource: "nap_mx_flutter_resources", withExtension: "bundle"),
     let resources = Bundle(url: url) {
    return resources
  }
  return host
  #endif
}

private func loadNativeTemplate() -> AMMNativeAdView? {
  UINib(nibName: "AMMNativeAdView300x250", bundle: resourceBundle())
    .instantiate(withOwner: nil, options: nil).first as? AMMNativeAdView
}
