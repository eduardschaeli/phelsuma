import CoreGraphics
import Testing
@testable import PhelsumaCore

@Test func colorColumnsStartInCenterAndWrapDownwardBeforeFanningOut() {
    // Catches mixing colors in a column, failing to wrap at the bottom, and placing the next color beside the wrong edge.
    let items = [
        ColorColumnLayout.Item(id: 1, color: .yellow, size: CGSize(width: 100, height: 300)),
        ColorColumnLayout.Item(id: 2, color: .yellow, size: CGSize(width: 100, height: 300)),
        ColorColumnLayout.Item(id: 3, color: .blue, size: CGSize(width: 100, height: 120)),
        ColorColumnLayout.Item(id: 4, color: .green, size: CGSize(width: 100, height: 120))
    ]
    let positions = ColorColumnLayout.positions(for: items, in: CGRect(x: 0, y: 0, width: 800, height: 600))
    #expect(positions[1] == CGPoint(x: 350, y: 280))
    #expect(positions[2] == CGPoint(x: 466, y: 280))
    #expect(positions[3] == CGPoint(x: 234, y: 460))
    #expect(positions[4] == CGPoint(x: 582, y: 460))
}

@Test func colorColumnsStackDifferentHeightsAndOverlapHorizontallyWhenFull() {
    // Catches vertical overlap within a column and columns escaping the visible screen.
    let items = [
        ColorColumnLayout.Item(id: 1, color: .yellow, size: CGSize(width: 120, height: 180)),
        ColorColumnLayout.Item(id: 2, color: .yellow, size: CGSize(width: 80, height: 100)),
        ColorColumnLayout.Item(id: 3, color: .blue, size: CGSize(width: 120, height: 100)),
        ColorColumnLayout.Item(id: 4, color: .green, size: CGSize(width: 120, height: 100))
    ]
    let positions = ColorColumnLayout.positions(for: items, in: CGRect(x: 0, y: 0, width: 300, height: 400))
    #expect(positions[1] == CGPoint(x: 90, y: 200))
    #expect(positions[2] == CGPoint(x: 90, y: 84))
    #expect(positions[3] == CGPoint(x: 0, y: 280))
    #expect(positions[4] == CGPoint(x: 180, y: 280))
}
