import CoreGraphics
import Testing

@testable import ScreenToCodexCore

private let selectionBounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

@Test func selectionWaitsForMouseDown() {
  var selection = SelectionGesture()
  #expect(selection.end(at: CGPoint(x: 200, y: 200), in: selectionBounds) == nil)
}

@Test func mouseReleaseReturnsSelectedRegion() {
  var selection = SelectionGesture()
  selection.begin(at: CGPoint(x: 300, y: 400))
  selection.drag(to: CGPoint(x: 150, y: 100), in: selectionBounds)
  #expect(
    selection.end(at: CGPoint(x: 100, y: 100), in: selectionBounds)
      == CGRect(x: 100, y: 100, width: 200, height: 300))
}

@Test func clickWithoutDragKeepsWaitingForSelection() {
  var selection = SelectionGesture()
  selection.begin(at: CGPoint(x: 50, y: 50))
  #expect(selection.end(at: CGPoint(x: 50, y: 50), in: selectionBounds) == nil)
  selection.begin(at: CGPoint(x: 50, y: 50))
  #expect(
    selection.end(at: CGPoint(x: 150, y: 150), in: selectionBounds)
      == CGRect(x: 50, y: 50, width: 100, height: 100))
}

@Test func selectionIsClippedToItsDisplay() {
  var selection = SelectionGesture()
  selection.begin(at: CGPoint(x: 50, y: 50))
  #expect(
    selection.end(at: CGPoint(x: 1500, y: 900), in: selectionBounds)
      == CGRect(x: 50, y: 50, width: 950, height: 750))
}
