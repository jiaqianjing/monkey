// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Monkey",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MonkeyInputMethod", targets: ["MonkeyInputMethod"]),
        .library(name: "MonkeyCore", targets: ["MonkeyCore"]),
        .library(name: "MonkeyPinyin", targets: ["MonkeyPinyin"])
    ],
    targets: [
        .target(name: "MonkeyCore"),
        .target(name: "CRimeBridge", publicHeadersPath: "include"),
        .target(name: "MonkeyPinyin", dependencies: ["CRimeBridge"]),
        .target(name: "MonkeySettings", dependencies: ["MonkeyCore"]),
        .executableTarget(name: "MonkeyInputMethod", dependencies: ["MonkeyCore", "MonkeyPinyin", "MonkeySettings"]),
        .testTarget(name: "MonkeyCoreTests", dependencies: ["MonkeyCore"]),
        .testTarget(name: "MonkeyPinyinTests", dependencies: ["MonkeyPinyin"])
    ],
    swiftLanguageVersions: [.v5]
)
