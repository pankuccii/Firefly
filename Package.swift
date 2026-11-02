// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Firefly", platforms: [.macOS(.v14)], products: [.library(name: "FireflyCore", targets: ["FireflyCore"])], targets: [.target(name: "FireflyCore"), .testTarget(name: "FireflyCoreTests", dependencies: ["FireflyCore"])])
