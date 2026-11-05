#!/usr/bin/env python3
"""Run production text policies and their Swift tests without macOS frameworks.

Requires Python 3 and Swift 6. This deliberately does not claim to build the
SwiftUI application or replace the native store and UI test suites.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="connor-text-preview-") as directory:
    package = Path(directory)
    sources = package / "Sources" / "ConnorGraphAppSupport"
    tests = package / "Tests" / "PreviewTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PortableTextPreview", targets: [
    .target(name: "ConnorGraphAppSupport"),
    .testTarget(name: "PreviewTests", dependencies: ["ConnorGraphAppSupport"])
])
''', encoding="utf-8")
    shutil.copy2(root / "Sources/ConnorGraphAppSupport/AppLargeTextPage.swift", sources)
    preview = (root / "Sources/ConnorGraphAgentMac/AgentMarkdownPreviewText.swift").read_text(encoding="utf-8")
    policies = preview.split("enum AgentMarkdownPreviewRenderStrategy:", 1)[1].split("struct AgentMarkdownPreviewText:", 1)[0]
    (sources / "PreviewPolicies.swift").write_text(
        "import Foundation\nenum AgentMarkdownPreviewRenderStrategy:" + policies,
        encoding="utf-8",
    )
    shutil.copy2(root / "Tests/ConnorGraphAppSupportTests/AppLargeTextPageTests.swift", tests)
    strategy_tests = (root / "Tests/ConnorGraphAgentMacTests/AgentMarkdownPreviewStrategyTests.swift").read_text(encoding="utf-8")
    strategy_tests = strategy_tests.split("    @Test func fileAndAttachmentPreviewsOfferFullMarkdownExpansion", 1)[0] + "}\n"
    strategy_tests = strategy_tests.replace("import AppKit\n", "").replace(
        "@testable import ConnorGraphAgentMac", "@testable import ConnorGraphAppSupport"
    )
    (tests / "PreviewStrategyTests.swift").write_text(strategy_tests, encoding="utf-8")
    subprocess.run(["swift", "test", "--package-path", str(package)], check=True)
