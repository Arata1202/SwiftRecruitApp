import UIKit
import XCTest

final class AccentColorContrastTests: XCTestCase {
    func testLinkTextIsReadableOnGroupedRowsInBothAppearances() throws {
        let accent = try XCTUnwrap(UIColor(named: "AccentColor", in: .main, compatibleWith: nil))
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let foreground = accent.resolvedColor(with: traits)
            let background = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
            XCTAssertGreaterThanOrEqual(try contrastRatio(foreground, background), 4.5)
        }
    }

    func testProminentFillIsReadableWithWhiteText() throws {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let accent = try XCTUnwrap(UIColor(named: "AccentColor", in: .main, compatibleWith: traits))
        XCTAssertGreaterThanOrEqual(try contrastRatio(.white, accent.resolvedColor(with: traits)), 4.5)
    }

    private func contrastRatio(_ first: UIColor, _ second: UIColor) throws -> Double {
        let a = try luminance(first)
        let b = try luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ color: UIColor) throws -> Double {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let components = try XCTUnwrap(color.cgColor.converted(to: space, intent: .relativeColorimetric, options: nil)?.components)
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(components[0]) + 0.7152 * linear(components[1]) + 0.0722 * linear(components[2])
    }
}
