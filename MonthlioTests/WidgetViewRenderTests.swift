import SwiftUI
import WidgetKit
import XCTest
@testable import Monthlio

/// Renders every widget family to a PNG so layout can be eyeballed without
/// adding the widget to a Home Screen. Files land in the temporary directory
/// printed by the test; the assertions only check that rendering works.
@MainActor
final class WidgetViewRenderTests: XCTestCase {
    private static let sizes: [(WidgetFamily, CGSize, String)] = [
        (.systemSmall, CGSize(width: 170, height: 170), "small"),
        (.systemMedium, CGSize(width: 364, height: 170), "medium"),
        (.accessoryRectangular, CGSize(width: 172, height: 76), "rectangular"),
        (.accessoryCircular, CGSize(width: 76, height: 76), "circular"),
        (.accessoryInline, CGSize(width: 300, height: 30), "inline"),
    ]

    private func render(_ content: WidgetEntryContent, family: WidgetFamily, size: CGSize) -> UIImage? {
        let view = MonthlioWidgetView(content: content, family: family)
            .frame(width: size.width, height: size.height)
            .padding(family == .systemSmall || family == .systemMedium ? 16 : 0)
            .background(Color(.systemBackground))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    func testEveryFamilyRendersPlaceholderDiscreetAndEmptyStates() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "monthlio-widgets")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("WIDGET_RENDER_DIR=\(directory.path)")

        var discreet = WidgetEntryContent.placeholder()
        discreet.isDiscreet = true
        let empty = WidgetTimelineBuilder.content(from: nil, at: .now)
        let variants: [(String, WidgetEntryContent)] = [("placeholder", .placeholder()), ("discreet", discreet), ("empty", empty)]

        for (family, size, name) in Self.sizes {
            for (variant, content) in variants {
                let image = try XCTUnwrap(render(content, family: family, size: size), "\(name) \(variant) did not render")
                XCTAssertGreaterThan(image.size.width, 0)
                if let data = image.pngData() {
                    try data.write(to: directory.appending(path: "\(name)-\(variant).png"))
                }
            }
        }
    }
}
