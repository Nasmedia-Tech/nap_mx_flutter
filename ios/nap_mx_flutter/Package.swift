// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "nap_mx_flutter",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "nap-mx-flutter", targets: ["nap_mx_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(
            url: "https://github.com/Nasmedia-Tech/iOS-SSP-Mediation-SPM.git",
            exact: "2.5.0"
        )
    ],
    targets: [
        .target(
            name: "nap_mx_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "AdMixerMediation", package: "iOS-SSP-Mediation-SPM")
            ],
            resources: [
                // If your plugin requires a privacy manifest, for example if it uses any required
                // reason APIs, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                .process("PrivacyInfo.xcprivacy"),
                .process("AMMNativeAdView300x250.xib"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
