// swift-tools-version: 5.9
// Package.swift — lógica de la app de control iOS (v1).
// Swift 5 language mode (sin strict concurrency), sin dependencias de terceros.
// El .xcodeproj de la app lo crea una vez el usuario en Xcode (ver README.md): este paquete
// aporta el producto `ControlKit` (fuentes + tests) compilable para iOS y para el host macOS
// (solo para correr `swift test` sin simulador).
import PackageDescription

let package = Package(
    name: "ControlApp",
    platforms: [
        .iOS(.v17),
        // macOS 14 solo para `swift build`/`swift test` en el host; la app es iOS.
        .macOS(.v14)
    ],
    products: [
        .library(name: "ControlKit", targets: ["ControlKit"])
    ],
    targets: [
        .target(name: "ControlKit"),
        .testTarget(name: "ControlTests", dependencies: ["ControlKit"])
    ]
)
