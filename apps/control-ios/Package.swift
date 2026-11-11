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
    dependencies: [
        // ComponentsKit (MIT, solo iOS; UIKit + envoltorios SwiftUI). Tema Homita en Theme/HomitaComponents.swift.
        .package(url: "https://github.com/componentskit/ComponentsKit", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ControlKit",
            dependencies: [
                // Solo iOS: en el host macOS (swift test) la dependencia no se enlaza.
                .product(name: "ComponentsKit", package: "ComponentsKit", condition: .when(platforms: [.iOS])),
            ],
            // Geist/GeistMono del dashboard (OFL, ver Resources/Fonts/OFL.txt).
            resources: [.process("Resources/Fonts")]
        ),
        .testTarget(name: "ControlTests", dependencies: ["ControlKit"])
    ]
)
