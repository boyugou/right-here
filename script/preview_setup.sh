#!/usr/bin/env bash
#
# Render the setup window to a PNG without a screen, for looking at layout and translations.
#
#   ./script/preview_setup.sh out.png              English, light
#   ./script/preview_setup.sh out.png de           German
#   ./script/preview_setup.sh out.png en --dark    dark mode
#   ./script/preview_setup.sh out.png en --onboarding   the first-run card, as when the Finder extension is off
#
# It builds a throwaway package under .build/preview that links the app's own view files and the
# package libraries, then renders SetupView with ImageRenderer. The checks it shows are the real ones
# for this machine, except that the runner-script check compares against the preview binary's path.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: preview_setup.sh out.png [language] [--dark] [--onboarding]}"
# The script changes folder before it renders, so a relative output path is resolved against where it was started.
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
LANGUAGE="${2:-en}"
DARK=""
ONBOARDING=""
for flag in "${@:3}"; do
  [[ "$flag" == "--dark" ]] && DARK="--dark"
  [[ "$flag" == "--onboarding" ]] && ONBOARDING="--onboarding"
done
PREVIEW="$ROOT/.build/preview"
# SwiftPM names a path dependency after its folder, which is not "right-here" in a worktree or a renamed clone.
PKG="$(basename "$ROOT")"

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
            dependencies: [.product(name: "RightHereCore", package: "$PKG"), .product(name: "RightHereKit", package: "$PKG")],
            path: "Sources/preview",
            swiftSettings: [.swiftLanguageMode(.v5), .define("PREVIEW")]
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
    if CommandLine.arguments.contains("--onboarding") { model.simulateExtensionOff() }
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
"$BIN" "$OUT" $DARK $ONBOARDING -AppleLanguages "($LANGUAGE)"
