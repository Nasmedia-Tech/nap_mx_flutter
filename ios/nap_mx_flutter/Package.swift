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
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
