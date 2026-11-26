#!/usr/bin/env python3
"""Run the production Foundation browser policies with Swift 6, without macOS SDKs.

This checks URL parsing, search engines, suggestions, recently closed tabs and comparison source bounds.
It does not replace the SwiftUI/WebKit application build or native UI tests.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
swift = shutil.which("swift")
if not swift:
    raise SystemExit("Swift 6 is required; native macOS UI validation also requires a Mac.")
with tempfile.TemporaryDirectory(prefix="connor-browser-daily-") as directory:
    package = Path(directory)
    sources = package / "Sources" / "ConnorGraphAppSupport"
    tests = package / "Tests" / "BrowserDailyTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BrowserDaily", targets: [
    .target(name: "ConnorGraphAppSupport"),
    .testTarget(name: "BrowserDailyTests", dependencies: ["ConnorGraphAppSupport"])
])
''', encoding="utf-8")
    shutil.copy2(root / "Sources/ConnorGraphAppSupport/DefaultSearchEngine.swift", sources)
    shutil.copy2(root / "Tests/ConnorGraphAppSupportTests/DefaultSearchEngineTests.swift", tests)
    shutil.copy2(root / "Sources/ConnorGraphAppSupport/BrowserTaskStore.swift", sources)
    shutil.copy2(root / "Tests/ConnorGraphAppSupportTests/BrowserTaskStoreTests.swift", tests)
    (package / "Tests/Fixtures").mkdir()
    shutil.copy2(root / "Tests/Fixtures/browser-task-v1.json", package / "Tests/Fixtures")
    subprocess.run([swift, "test", "--package-path", str(package)], check=True)
