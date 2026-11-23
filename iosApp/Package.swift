// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LilacAnime",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LilacAnimeCore", targets: ["LilacAnimeCore"])
    ],
    targets: [
        .target(
            name: "LilacAnimeCore",
            path: "LilacAnime",
            exclude: ["Resources"]
        )
    ]
)
