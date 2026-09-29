// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FeedbackKit",
    platforms: [
        // .v16 for ShareLink, used by FeedbackView.
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "FeedbackKit",
            targets: ["FeedbackKit"]
        )
    ],
    targets: [
        .target(
            name: "FeedbackKit",
            dependencies: [],
            path: "ios/Sources/FeedbackKit"
        ),
        .testTarget(
            name: "FeedbackKitTests",
            dependencies: ["FeedbackKit"],
            path: "ios/Tests/FeedbackKitTests"
        )
    ]
)
