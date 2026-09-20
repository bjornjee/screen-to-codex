import CoreGraphics

public struct SelectionGesture {
  private var origin: CGPoint?
  public private(set) var rectangle = CGRect.zero

  public init() {}

  public mutating func begin(at point: CGPoint) {
    origin = point
    rectangle = .zero
  }

  public mutating func drag(to point: CGPoint, in bounds: CGRect) {
    guard let origin else { return }
    rectangle = CGRect(
      x: min(origin.x, point.x), y: min(origin.y, point.y),
      width: abs(point.x - origin.x), height: abs(point.y - origin.y)
    ).intersection(bounds)
  }

  public mutating func end(at point: CGPoint, in bounds: CGRect) -> CGRect? {
    guard origin != nil else { return nil }
    drag(to: point, in: bounds)
    origin = nil
    guard rectangle.width >= 8, rectangle.height >= 8 else {
      rectangle = .zero
      return nil
    }
    return rectangle
  }
}
