import AdMixerMediation
import Flutter
import UIKit

public final class NapMxFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let pluginVersion = "0.1.7"
  private var eventSink: FlutterEventSink?
  private var initialized = false
  private var fingerprint: String?
  private var requests: [String: NapMxFullscreenRequest] = [:]
  private let initializeSdk: (Int, Set<Int>) -> Void

  public override init() {
    initializeSdk = { AMMediation.shared.initialize(mediaKey: $0, adunitID: $1) }
    super.init()
  }

  init(initializeSdk: @escaping (Int, Set<Int>) -> Void) {
    self.initializeSdk = initializeSdk
    super.init()
  }

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
          let rawUnits = args["adUnitIds"] as? [String: String] else {
      result(FlutterError(
        code: "invalid_configuration",
        message: "iOS requires a numeric mediaKey and at least one numeric ad unit ID.",
        details: nil
      ))
      return
    }
    guard args["additionalAdUnitIds"] == nil || args["additionalAdUnitIds"] is [String] else {
      result(FlutterError(code: "invalid_configuration", message: "additionalAdUnitIds must be a list of strings.", details: nil))
      return
    }
    let additionalUnits = args["additionalAdUnitIds"] as? [String] ?? []
    let unitValues = Set((Array(rawUnits.values) + additionalUnits).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }).sorted()
    let parsedUnits = unitValues.compactMap(Int.init)
    guard !unitValues.isEmpty, parsedUnits.count == unitValues.count else {
      result(FlutterError(
        code: "invalid_ad_unit",
        message: "Every iOS ad unit ID must be a base-10 integer.",
        details: nil
      ))
      return
    }
    let numericUnits = Set(parsedUnits)
    if args["testMode"] as? Bool == true {
      result(FlutterError(
        code: "test_mode_unsupported",
        message: "The nap mx iOS SDK has no global test-mode API. Use assigned test units and network debug tools.",
        details: nil
      ))
      return
    }
    if let testDeviceIds = args["testDeviceIds"] as? [Any], !testDeviceIds.isEmpty {
      result(FlutterError(
        code: "test_mode_unsupported",
        message: "The nap mx iOS SDK has no test-device API. Use assigned test units and network debug tools.",
        details: nil
      ))
      return
    }
    let privacy = args["privacy"] as? [String: Any]
    if let usPrivacy = privacy?["usPrivacyString"] as? String,
       !usPrivacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result(FlutterError(
        code: "unsupported_privacy",
        message: "The nap mx iOS SDK has no US Privacy string API; use usSaleConsent instead.",
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

    if let privacy {
      let consent = AMMConsent()
      consent.gdprConsent = consentValue(privacy["gdprConsent"] as? String)
      consent.usSaleConsent = consentValue(privacy["usSaleConsent"] as? String)
      consent.childDirected = consentValue(privacy["childDirected"] as? String)
      consent.underAgeOfConsent = consentValue(privacy["underAgeOfConsent"] as? String)
      AMMediation.shared.setConsent(consent)
    }
    let logLevel = args["logLevel"] as? String
    AMMediation.shared.setDebugEnabled(isEnabled: logLevel == "debug")
    initializeSdk(mediaKey, numericUnits)
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

// Injectable SDK entry points keep show-failure tests independent of ad inventory.
struct NapMxFullscreenLoaders {
  typealias InterstitialCompletion = (AMMInterstitial?, AdNetworkType, Error?) -> Void
  typealias VideoCompletion = (AMMVideoInterstitial?, AdNetworkType, Error?) -> Void
  typealias RewardCompletion = (AMMRewardVideo?, AdNetworkType, Error?) -> Void

  var interstitial: (Int, @escaping InterstitialCompletion) -> Void = {
    AMMInterstitial.loadAd(adUnitID: $0, config: AMMInterstitialConfig(), completion: $1)
  }
  var video: (Int, @escaping VideoCompletion) -> Void = {
    AMMVideoInterstitial.loadAd(adUnitID: $0, completion: $1)
  }
  var reward: (Int, [String: String]?, @escaping RewardCompletion) -> Void = {
    AMMRewardVideo.loadAd(adUnitID: $0, customParam: $1, completion: $2)
  }
  var show: (NSObject, UIViewController) -> Void = { ad, root in
    switch ad {
    case let ad as AMMInterstitial: ad.show(rootViewController: root)
    case let ad as AMMVideoInterstitial: ad.show(rootViewController: root)
    case let ad as AMMRewardVideo: ad.show(rootViewController: root)
    default: break
    }
  }
}

final class NapMxFullscreenRequest: NSObject,
    AMMInterstitialDelegate, AMMVideoInterstitialDelegate, AMMRewardVideoDelegate {
  /// How long a closed ad is kept alive so that a reward callback which the network
  /// delivers after the close callback can still reach the app.
  private static let rewardGrace: TimeInterval = 2

  let id: String
  let format: String
  let adUnitText: String
  private let adUnitId: Int
  private let customParams: [String: String]?
  private let emitBlock: ([String: Any]) -> Void
  private let finishedBlock: (String) -> Void
  private let loaders: NapMxFullscreenLoaders
  private let rootViewController: () -> UIViewController?
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
    finished: @escaping (String) -> Void,
    loaders: NapMxFullscreenLoaders = NapMxFullscreenLoaders(),
    rootViewController: @escaping () -> UIViewController? = activeViewController
  ) {
    self.loaders = loaders
    self.rootViewController = rootViewController
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
      loaders.interstitial(adUnitId) { [weak self] ad, adapterType, error in
        guard let self else { ad?.stop(); return }
        guard self.acceptsLoad(ad, current: self.interstitial, stop: { ad?.stop() }) else { return }
        if let error { self.failLoad(error: error); return }
        guard let ad else { self.failLoad(code: "load_failed", message: "SDK returned no ad.", nativeCode: nil); return }
        self.interstitial = ad
        ad.delegate = self
        self.loaded(network: String(describing: adapterType))
      }
    case "interstitialVideo":
      loaders.video(adUnitId) { [weak self] ad, adapterType, error in
        guard let self else { ad?.stop(); return }
        guard self.acceptsLoad(ad, current: self.video, stop: { ad?.stop() }) else { return }
        if let error { self.failLoad(error: error); return }
        guard let ad else { self.failLoad(code: "load_failed", message: "SDK returned no ad.", nativeCode: nil); return }
        self.video = ad
        ad.delegate = self
        self.loaded(network: String(describing: adapterType))
      }
    case "rewarded":
      loaders.reward(adUnitId, customParams) { [weak self] ad, adapterType, error in
        guard let self else { ad?.stop(); return }
        guard self.acceptsLoad(ad, current: self.reward, stop: { ad?.stop() }) else { return }
        if let error { self.failLoad(error: error); return }
        guard let ad else { self.failLoad(code: "load_failed", message: "SDK returned no ad.", nativeCode: nil); return }
        self.reward = ad
        ad.delegate = self
        self.loaded(network: String(describing: adapterType))
      }
    default: failLoad(code: "unsupported", message: "Unsupported format.", nativeCode: nil)
    }
  }

  /// Whether a load completion still belongs to this request.
  /// A stale ad that is not the retained one is stopped.
  private func acceptsLoad(_ ad: AnyObject?, current: AnyObject?, stop: () -> Void) -> Bool {
    guard disposed || state != "loading" else { return true }
    if ad !== current { stop() }
    return false
  }

  // Load completions gate on acceptsLoad before calling this.
  private func loaded(network: String) {
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
    guard let root = rootViewController() else {
      result(FlutterError(code: "no_view_controller", message: "No active view controller.", details: nil))
      return
    }
    state = "showing"
    showResult = result
    if let ad = [interstitial as NSObject?, video, reward].compactMap({ $0 }).first {
      loaders.show(ad, root)
    }
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
    // A pending show result means nothing reached the screen, so no close callback follows.
    let neverPresented = showResult != nil
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
    // Release the ad now instead of holding it until the app disposes the controller.
    // A failure after presentation keeps the ad until its close callback releases it.
    if neverPresented {
      dispose(notify: false)
      finishedBlock(id)
    }
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
    state = "closed"
    emitBlock(event("closed"))
    // The SDK defines no order between the reward and the close callback, and releasing the
    // ad while a reward is still in flight loses that callback. Keep the native ad alive for
    // a bounded window so a late reward still reaches the app.
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.rewardGrace) { [weak self] in
      guard let self else { return }
      self.dispose(notify: false)
      self.finishedBlock(self.id)
    }
  }

  private func failLoad(error: Error) {
    let nsError = error as NSError
    failLoad(code: "load_failed", message: error.localizedDescription, nativeCode: nsError.code)
  }

  /// Pass a nil `nativeCode` for failures the plugin raises itself, so that they are never
  /// mistaken for the SDK's no-fill (-1) or timeout (-8) codes.
  private func failLoad(code: String, message: String, nativeCode: Int?) {
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
    _ type: String, code: String, message: String, nativeCode: Int?
  ) -> [String: Any] {
    var value = event(type)
    value["error"] = [
      "code": code,
      "message": message,
      "nativeCode": nativeCode ?? NSNull(),
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
  /// Reward delivery is intentionally not gated on `disposed`: the reward can arrive after
  /// the close callback, and the SDK notifies exactly once per impression, so the
  /// `rewardSent` flag alone keeps it exactly-once.
  func onRewardVideoEarned(rewardInfo: RewardInfo) {
    guard !rewardSent else { return }
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

// Injectable SDK entry points keep cancellation tests independent of ad inventory.
struct NapMxAdViewLoaders {
  typealias BannerCompletion = (AMMBannerView?, AdNetworkType, Error?) -> Void
  typealias VideoCompletion = (AMMVideoView?, AdNetworkType, Error?) -> Void
  typealias NativeCompletion = (AMMNativeAdViewContainer?, AdNetworkType, Error?) -> Void

  var banner: (Int, UIViewController, @escaping BannerCompletion) -> Void = {
    AMMBannerView.loadAd(adUnitID: $0, rootViewController: $1, completion: $2)
  }
  var video: (Int, UIViewController, @escaping VideoCompletion) -> Void = {
    AMMVideoView.loadAd(adUnitID: $0, rootViewController: $1, completion: $2)
  }
  var native: (Int, UIViewController, AMMNativeAdView, @escaping NativeCompletion) -> Void = {
    AMMNativeAdViewContainer.loadAd(adUnitID: $0, rootViewController: $1, nativeAdView: $2, completion: $3)
  }
}

final class NapMxPlatformAdView: NSObject, FlutterPlatformView,
    AMMBannerViewDelegate, AMMVideoViewDelegate, AMMNativeDelegate {
  private let container: UIView
  private let viewId: Int64
  private let format: String
  private let adUnitText: String
  private let emitBlock: ([String: Any]) -> Void
  private let channel: FlutterMethodChannel
  private let loaders: NapMxAdViewLoaders
  private let rootViewController: () -> UIViewController?
  private var startedAt = Date()
  private var banner: AMMBannerView?
  private var video: AMMVideoView?
  private var native: AMMNativeAdViewContainer?
  private var disposed = false
  private var loading = false
  private var generation = 0

  init(
    frame: CGRect,
    viewId: Int64,
    args: [String: Any],
    messenger: FlutterBinaryMessenger,
    emit: @escaping ([String: Any]) -> Void,
    loaders: NapMxAdViewLoaders = NapMxAdViewLoaders(),
    rootViewController: @escaping () -> UIViewController? = activeViewController
  ) {
    self.loaders = loaders
    self.rootViewController = rootViewController
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
    guard let adUnitId = Int(adUnitText), let root = rootViewController() else {
      result(FlutterError(
        code: "invalid_request",
        message: "A numeric iOS adUnitId and active view controller are required.",
        details: nil
      ))
      return
    }
    generation += 1
    let token = generation
    releaseAds()
    loading = true
    startedAt = Date()
    emit("loadStarted")
    result(nil)
    switch format {
    case "banner":
      loaders.banner(adUnitId, root) {
        [weak self] ad, adapterType, error in
        guard let self, self.isCurrent(token) else { ad?.stop(); return }
        if let error { self.failed(error); return }
        guard let ad else { self.failed(nil); return }
        self.banner = ad
        ad.delegate = self
        self.loaded(adapterType)
        self.attach(ad)
      }
    case "inlineVideo":
      loaders.video(adUnitId, root) {
        [weak self] ad, adapterType, error in
        guard let self, self.isCurrent(token) else { ad?.stop(); return }
        if let error { self.failed(error); return }
        guard let ad else { self.failed(nil); return }
        self.video = ad
        ad.delegate = self
        self.loaded(adapterType)
        self.attach(ad)
      }
    case "native":
      guard let nativeView = loadNativeTemplate() else {
        failedMessage("Native template resource is unavailable.")
        return
      }
      loaders.native(adUnitId, root, nativeView) { [weak self] ad, adapterType, error in
        guard let self, self.isCurrent(token) else { ad?.stop(); return }
        if let error { self.failed(error); return }
        guard let ad else { self.failed(nil); return }
        self.native = ad
        ad.delegate = self
        self.loaded(adapterType)
        self.attach(ad)
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

  /// Whether a load completion belongs to the latest load of a live view.
  private func isCurrent(_ token: Int) -> Bool { !disposed && generation == token }

  // Load completions gate on isCurrent before calling this.
  private func loaded(_ adapterType: Any) {
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
    guard !disposed else { return }
    generation += 1
    loading = false
    disposed = final
    releaseAds()
    emit(final ? "disposed" : "cancelled")
    if final { channel.setMethodCallHandler(nil) }
  }

  private func releaseAds() {
    banner?.delegate = nil; video?.delegate = nil; native?.delegate = nil
    banner?.stop(); video?.stop(); native?.stop()
    banner = nil; video = nil; native = nil
    container.subviews.forEach { $0.removeFromSuperview() }
  }

  private func emit(_ type: String, network: String? = nil) {
    guard !disposed || type == "disposed" else { return }
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
  /// Mediation 2.6.0+: an nap mx video failed to prepare or stopped during playback.
  func onFailShowVideo(error: Error?) {
    guard !disposed else { return }
    let nsError = error as NSError?
    var value = event("showFailed")
    value["network"] = NSNull()
    value["error"] = [
      "code": "show_failed",
      "message": error?.localizedDescription ?? "Ad show failed.",
      "nativeCode": nsError?.code ?? NSNull(),
      "isNoFill": false,
      "isTimeout": false,
    ]
    emitBlock(value)
  }
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

private func loadNativeTemplate() -> AMMNativeAdView? {
  let nativeView = AMMNativeAdView()
  nativeView.backgroundColor = .systemBackground

  let media = UIView()
  let icon = UIImageView()
  let headline = UILabel()
  let advertiser = UILabel()
  let description = UILabel()
  let callToAction = UIButton(type: .system)
  for view in [media, icon, headline, advertiser, description, callToAction] {
    view.translatesAutoresizingMaskIntoConstraints = false
    nativeView.addSubview(view)
  }

  icon.contentMode = .scaleAspectFill
  icon.clipsToBounds = true
  headline.font = .preferredFont(forTextStyle: .headline)
  headline.numberOfLines = 2
  advertiser.font = .preferredFont(forTextStyle: .caption1)
  advertiser.textColor = .secondaryLabel
  description.font = .preferredFont(forTextStyle: .caption1)
  description.textColor = .secondaryLabel
  description.numberOfLines = 2
  callToAction.setTitle("Learn more", for: .normal)

  NSLayoutConstraint.activate([
    media.topAnchor.constraint(equalTo: nativeView.topAnchor),
    media.leadingAnchor.constraint(equalTo: nativeView.leadingAnchor),
    media.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor),
    media.heightAnchor.constraint(equalToConstant: 150),
    icon.topAnchor.constraint(equalTo: media.bottomAnchor, constant: 10),
    icon.leadingAnchor.constraint(equalTo: nativeView.leadingAnchor, constant: 12),
    icon.widthAnchor.constraint(equalToConstant: 44),
    icon.heightAnchor.constraint(equalToConstant: 44),
    headline.topAnchor.constraint(equalTo: icon.topAnchor),
    headline.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
    headline.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor, constant: -12),
    advertiser.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 2),
    advertiser.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
    advertiser.trailingAnchor.constraint(equalTo: headline.trailingAnchor),
    description.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
    description.leadingAnchor.constraint(equalTo: icon.leadingAnchor),
    description.trailingAnchor.constraint(
      lessThanOrEqualTo: callToAction.leadingAnchor,
      constant: -8
    ),
    callToAction.trailingAnchor.constraint(equalTo: nativeView.trailingAnchor, constant: -8),
    callToAction.bottomAnchor.constraint(equalTo: nativeView.bottomAnchor, constant: -8),
    callToAction.widthAnchor.constraint(equalToConstant: 100),
    callToAction.heightAnchor.constraint(equalToConstant: 36),
  ])

  nativeView.media = media
  nativeView.iv_icon = icon
  nativeView.l_headline = headline
  nativeView.l_advertiser = advertiser
  nativeView.l_description = description
  nativeView.b_cta = callToAction
  return nativeView
}
