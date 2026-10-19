import AdMixerMediation
import Flutter
import UIKit
import XCTest
@testable import nap_mx_flutter

final class RunnerTests: XCTestCase {
  func testSdkInfo() {
    NapMxFlutterPlugin().handle(FlutterMethodCall(methodName: "getSdkInfo", arguments: nil)) { result in
      let info = result as? [String: Any]
      XCTAssertEqual(info?["platform"] as? String, "ios")
      XCTAssertEqual(info?["pluginVersion"] as? String, "0.1.7")
    }
  }

  func testFullscreenDelegateEventsAndErrors() {
    for format in ["interstitial", "interstitialVideo", "rewarded"] {
      var events: [[String: Any]] = []
      let request = NapMxFullscreenRequest(
        id: "request", format: format, adUnitText: "456", adUnitId: 456,
        customParams: nil, timeout: 30, completion: { _ in },
        emit: { events.append($0) }, finished: { _ in }
      )
      let error = NSError(domain: "test", code: -5)
      switch format {
      case "interstitial":
        request.onSuccessShowInterstitial(); request.onClickInterstitial()
        request.onFailShowInterstitial(error: error); request.onCloseInterstitial()
      case "interstitialVideo":
        request.onSuccessShowVideoInterstitial(); request.onClickVideoInterstitial()
        request.onCompleteVideoInterstitial()
        request.onFailShowVideoInterstitial(error: error); request.onCloseVideoInterstitial()
      default:
        request.onSuccessShowReward(); request.onClickRewardVideo()
        request.onRewardVideoComplete()
        request.onFailShowReward(error: error); request.onCloseRewardVideo()
      }
      let expected = format == "interstitial"
        ? ["shown", "clicked", "showFailed", "closed"]
        : ["shown", "clicked", "completed", "showFailed", "closed"]
      XCTAssertEqual(events.compactMap { $0["type"] as? String }, expected)
      let failure = events.first { $0["type"] as? String == "showFailed" }?["error"] as? [String: Any]
      XCTAssertEqual(failure?["code"] as? String, "show_failed")
      XCTAssertEqual(failure?["nativeCode"] as? Int, -5)
      XCTAssertTrue(events.allSatisfy { $0["requestId"] as? String == "request" && $0["format"] as? String == format })
      request.dispose(notify: true)
      let count = events.count
      request.onClickInterstitial(); request.onSuccessShowReward(); request.onCloseVideoInterstitial()
      XCTAssertEqual(events.count, count)
    }
  }

  func testListOnlyAndMixedRegistration() {
    for defaults in [[:], ["banner": "456", "native": "456"]] {
      var calls = 0
      let plugin = NapMxFlutterPlugin { mediaKey, units in
        calls += 1
        XCTAssertEqual(mediaKey, 123)
        XCTAssertEqual(units, Set([456, 789]))
      }
      plugin.handle(FlutterMethodCall(methodName: "initialize", arguments: [
        "mediaKey": "123", "adUnitIds": defaults,
        "additionalAdUnitIds": [" 456 ", "789", "789"],
      ])) { XCTAssertNil($0) }
      XCTAssertEqual(calls, 1)
    }
  }

  func testAllInlineFormatsIgnoreCancelledCallbacks() {
    for format in ["banner", "native", "inlineVideo"] {
      let root = UIViewController()
      var completions: [(Bool) -> Void] = []
      var returned: [UIView] = []
      var loaders = NapMxAdViewLoaders()
      let error = NSError(domain: "test", code: -1)
      loaders.banner = { id, _, done in
        XCTAssertEqual(id, 456)
        completions.append { success in
          let ad = success ? AMMBannerView(rootViewController: root) : nil
          if let ad { returned.append(ad) }
          done(ad, .unknown, success ? nil : error)
        }
      }
      loaders.video = { id, _, done in
        XCTAssertEqual(id, 456)
        completions.append { success in
          let ad = success ? AMMVideoView(rootViewController: root) : nil
          if let ad { returned.append(ad) }
          done(ad, .unknown, success ? nil : error)
        }
      }
      loaders.native = { id, _, _, done in
        XCTAssertEqual(id, 456)
        completions.append { success in
          let ad = success ? AMMNativeAdViewContainer(rootViewController: root) : nil
          if let ad { returned.append(ad) }
          done(ad, .unknown, success ? nil : error)
        }
      }
      let messenger = TestMessenger()
      var events: [[String: Any]] = []
      let view = NapMxPlatformAdView(
        frame: CGRect(x: 0, y: 0, width: 320, height: 360), viewId: 7,
        args: ["format": format, "adUnitId": "456"], messenger: messenger,
        emit: { events.append($0) }, loaders: loaders, rootViewController: { root }
      )
      XCTAssertNil(messenger.invoke("load"))
      XCTAssertNil(messenger.invoke("cancel"))
      XCTAssertNil(messenger.invoke("load"))
      XCTAssertEqual(completions.count, 2)
      let before = events.count
      completions[0](false)
      completions[0](true)
      XCTAssertEqual(events.count, before)
      XCTAssertTrue(view.view().subviews.isEmpty)
      XCTAssertNil(returned.last?.superview)
      XCTAssertEqual((messenger.invoke("load") as? FlutterError)?.code, "already_loading")
      completions[1](true)
      XCTAssertEqual(events.last?["type"] as? String, "loaded")
      XCTAssertTrue(returned.last?.superview === view.view())
      switch format {
      case "banner": view.onSuccessShowBanner(); view.onClickBanner()
      case "native": view.onSuccessShowNative(); view.onClickNative()
      default: view.onSuccessShowVideo(); view.onClickVideo(); view.onCompleteVideo(); view.onSkipVideo()
      }
      XCTAssertTrue(events.allSatisfy { $0["viewId"] as? Int == 7 && $0["adUnitId"] as? String == "456" })
      XCTAssertNil(messenger.invoke("dispose"))
      let disposedCount = events.count
      view.onSuccessShowBanner(); view.onClickVideo(); view.onCompleteVideo()
      XCTAssertEqual(events.count, disposedCount)
      XCTAssertTrue(view.view().subviews.isEmpty)
      XCTAssertEqual(events.last?["type"] as? String, "disposed")
    }
  }
}

private final class TestMessenger: NSObject, FlutterBinaryMessenger {
  private var handler: FlutterBinaryMessageHandler?
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    self.handler = handler
    return 1
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) { handler = nil }
  func invoke(_ method: String) -> Any? {
    let codec = FlutterStandardMethodCodec.sharedInstance()
    var result: Any?
    var replied = false
    handler?(codec.encode(FlutterMethodCall(methodName: method, arguments: nil))) { data in
      replied = true
      if let data { result = codec.decodeEnvelope(data) }
    }
    XCTAssertTrue(replied)
    return result
  }
}
