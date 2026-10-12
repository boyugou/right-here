#!/usr/bin/env bash
#
# Render the setup window to a PNG without a screen, for looking at layout and translations.
#
#   ./script/preview_setup.sh out.png              English, light
#   ./script/preview_setup.sh out.png de           German
#   ./script/preview_setup.sh out.png en --dark    dark mode
#
# It builds a throwaway package under .build/preview that links the app's own view files and the
# package libraries, then renders SetupView with ImageRenderer. The checks it shows are the real ones
# for this machine, except that the runner-script check compares against the preview binary's path.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: preview_setup.sh out.png [language] [--dark]}"
LANGUAGE="${2:-en}"
DARK="${3:-}"
PREVIEW="$ROOT/.build/preview"

mkdir -p "$PREVIEW/Sources/preview"
cat > "$PREVIEW/Package.swift" <<PACKAGE
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Preview",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "$ROOT")],
    targets: [
        .executableTarget(
            name: "preview",
            dependencies: [.product(name: "RightHereCore", package: "right-here"), .product(name: "RightHereKit", package: "right-here")],
            path: "Sources/preview",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
PACKAGE
ln -sf "$ROOT/Apps/RightHere/SetupView.swift" "$PREVIEW/Sources/preview/SetupView.swift"
ln -sf "$ROOT/Apps/RightHere/SetupModel.swift" "$PREVIEW/Sources/preview/SetupModel.swift"
cat > "$PREVIEW/Sources/preview/main.swift" <<'SWIFT'
import AppKit
import SwiftUI

@MainActor
func render(dark: Bool, to path: String) async {
    let model = SetupModel()
    await model.refresh()
    // A real window mirrors itself for a right-to-left system language; the renderer needs to be told.
    let language = Locale.preferredLanguages.first ?? "en"
    let rightToLeft = Locale.Language(identifier: language).characterDirection == .rightToLeft
    let view = SetupView(model: model)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("render failed"); exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(Int(image.size.width)) x \(Int(image.size.height)) pt)")
}

let arguments = CommandLine.arguments
MainActor.assumeIsolated {
    _ = NSApplication.shared
    Task { @MainActor in
        await render(dark: arguments.contains("--dark"), to: arguments[1])
        exit(0)
    }
    RunLoop.main.run()
}
SWIFT

cd "$PREVIEW"
swift build 2>&1 | grep -E "error|warning: unre" || true
BIN="$(swift build --show-bin-path)/preview"
if [[ "$DARK" == "--dark" ]]; then
  "$BIN" "$OUT" --dark -AppleLanguages "($LANGUAGE)"
else
  "$BIN" "$OUT" -AppleLanguages "($LANGUAGE)"
fi
