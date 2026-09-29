import Foundation
import CoreGraphics

public struct WindowState: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var collapsed: Bool
    public var floating: Bool
    public var translucent: Bool
    public var fontSize: Double

    public init(x: Double = 120, y: Double = 300, width: Double = 300, height: Double = 260,
                collapsed: Bool = false, floating: Bool = false, translucent: Bool = false, fontSize: Double = 13) {
        self.x = x; self.y = y; self.width = width; self.height = height
        self.collapsed = collapsed; self.floating = floating; self.translucent = translucent; self.fontSize = fontSize
    }

    public var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    public func fitted(to screens: [CGRect]) -> WindowState {
        guard let primary = screens.first else { return self }
        let visible = screens.first { $0.intersects(frame) } ?? primary
        var result = self
        result.width = min(max(width.isFinite ? width : 300, 180), visible.width)
        result.height = min(max(height.isFinite ? height : 260, 100), visible.height)
        result.x = min(max(x.isFinite ? x : visible.minX, visible.minX), visible.maxX - result.width)
        result.y = min(max(y.isFinite ? y : visible.minY, visible.minY), visible.maxY - result.height)
        result.fontSize = min(max(fontSize.isFinite ? fontSize : 13, 9), 36)
        return result
    }
}

public final class LayoutStore {
    public let url: URL
    public private(set) var states: [UUID: WindowState]
    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            states = try JSONDecoder().decode([UUID: WindowState].self, from: Data(contentsOf: url))
        } else { states = [:] }
    }
    public func set(_ state: WindowState, for id: UUID) throws {
        var next = states
        next[id] = state
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        states = next
    }
}
