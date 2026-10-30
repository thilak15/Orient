import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import OrientCore

/// Low-latency macOS cursor, 3D game raw-delta, emulator touch-drag, and tactical Q/E key injector.
public final class SystemCursorInjector: @unchecked Sendable {
    private let eventSource: CGEventSource?
    private var activeLeanState: TacticalLeanState = .upright
    private var isTouchDragging: Bool = false

    // macOS Virtual KeyCodes
    private let keyCodeQ: CGKeyCode = 12
    private let keyCodeE: CGKeyCode = 14
    private let keyCodeSpace: CGKeyCode = 49
    private let keyCodeR: CGKeyCode = 15

    public init() {
        self.eventSource = CGEventSource(stateID: .hidSystemState)
    }

    public static func isAccessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        if promptIfNeeded {
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            let options = [promptKey: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    public func currentCursorPosition() -> Point2D {
        if let event = CGEvent(source: nil) {
            let loc = event.location
            return Point2D(x: loc.x, y: loc.y)
        }
        return Point2D(x: 600, y: 400)
    }

    public func currentScreenBounds() -> Rect2D {
        let mainID = CGMainDisplayID()
        let rect = CGDisplayBounds(mainID)
        if rect.width > 0 && rect.height > 0 {
            return Rect2D(
                minX: rect.minX,
                minY: rect.minY,
                maxX: rect.maxX,
                maxY: rect.maxY
            )
        }
        return Rect2D(minX: 0, minY: 0, maxX: 1920, maxY: 1080)
    }

    /// Moves the macOS cursor and sets hardware deltaX/deltaY fields for 3D Pointer-Lock FPS games.
    public func moveCursor(
        to target: Point2D,
        deltaX: Double,
        deltaY: Double,
        injectionProtocol: GameInjectionProtocol = .pointerLockRawDelta,
        shouldResetTouchDragAnchor: Bool = false
    ) {
        let bounds = currentScreenBounds()
        let anchorCenter = Point2D(
            x: (bounds.minX + bounds.maxX) * 0.65,
            y: (bounds.minY + bounds.maxY) * 0.52
        )

        if injectionProtocol == .emulatorTouchDrag {
            if shouldResetTouchDragAnchor && isTouchDragging {
                let cur = CGPoint(x: target.x, y: target.y)
                if let up = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: cur, mouseButton: .left) {
                    up.post(tap: .cghidEventTap)
                }
                let centerCG = CGPoint(x: anchorCenter.x, y: anchorCenter.y)
                CGWarpMouseCursorPosition(centerCG)
                if let down = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: centerCG, mouseButton: .left) {
                    down.post(tap: .cghidEventTap)
                }
                return
            }

            let cgPoint = CGPoint(x: target.x, y: target.y)
            if !isTouchDragging {
                isTouchDragging = true
                if let down = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: cgPoint, mouseButton: .left) {
                    down.post(tap: .cghidEventTap)
                }
            }
            if let drag = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDragged, mouseCursorPosition: cgPoint, mouseButton: .left) {
                drag.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
                drag.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
                drag.post(tap: .cghidEventTap)
            }
            return
        }

        if isTouchDragging {
            releaseTouchDragIfNeeded()
        }

        let cgPoint = CGPoint(x: target.x, y: target.y)
        if let moveEvent = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: cgPoint,
            mouseButton: .left
        ) {
            moveEvent.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
            moveEvent.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
            moveEvent.post(tap: .cghidEventTap)
        } else {
            CGWarpMouseCursorPosition(cgPoint)
        }
    }

    public func releaseTouchDragIfNeeded() {
        guard isTouchDragging else { return }
        isTouchDragging = false
        let pos = currentCursorPosition()
        let cgPoint = CGPoint(x: pos.x, y: pos.y)
        if let up = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: cgPoint, mouseButton: .left) {
            up.post(tap: .cghidEventTap)
        }
    }

    /// Updates Q/E tactical peek key hold states for PUBG / Tactical FPS games.
    public func updateTacticalLeanKeys(to newState: TacticalLeanState) {
        guard newState != activeLeanState else { return }

        // Release previously held lean key
        switch activeLeanState {
        case .leanLeftQ:
            postKey(keyCode: keyCodeQ, keyDown: false)
        case .leanRightE:
            postKey(keyCode: keyCodeE, keyDown: false)
        case .upright:
            break
        }

        // Press newly active lean key
        switch newState {
        case .leanLeftQ:
            postKey(keyCode: keyCodeQ, keyDown: true)
        case .leanRightE:
            postKey(keyCode: keyCodeE, keyDown: true)
        case .upright:
            break
        }

        activeLeanState = newState
    }

    public func releaseAllHeldKeys() {
        updateTacticalLeanKeys(to: .upright)
        releaseTouchDragIfNeeded()
    }

    public func performClick(action: GestureAction, at position: Point2D) {
        let cgPoint = CGPoint(x: position.x, y: position.y)

        switch action {
        case .leftClick:
            postMouseClick(
                downType: .leftMouseDown,
                upType: .leftMouseUp,
                button: .left,
                at: cgPoint,
                clickCount: 1
            )
        case .rightClick:
            postMouseClick(
                downType: .rightMouseDown,
                upType: .rightMouseUp,
                button: .right,
                at: cgPoint,
                clickCount: 1
            )
        case .doubleClick:
            postMouseClick(
                downType: .leftMouseDown,
                upType: .leftMouseUp,
                button: .left,
                at: cgPoint,
                clickCount: 1
            )
            postMouseClick(
                downType: .leftMouseDown,
                upType: .leftMouseUp,
                button: .left,
                at: cgPoint,
                clickCount: 2
            )
        default:
            break
        }
    }

    private func postKey(keyCode: CGKeyCode, keyDown: Bool) {
        if let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: keyDown) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func postMouseClick(
        downType: CGEventType,
        upType: CGEventType,
        button: CGMouseButton,
        at point: CGPoint,
        clickCount: Int64
    ) {
        if let downEvent = CGEvent(
            mouseEventSource: eventSource,
            mouseType: downType,
            mouseCursorPosition: point,
            mouseButton: button
        ), let upEvent = CGEvent(
            mouseEventSource: eventSource,
            mouseType: upType,
            mouseCursorPosition: point,
            mouseButton: button
        ) {
            downEvent.setIntegerValueField(.mouseEventClickState, value: clickCount)
            upEvent.setIntegerValueField(.mouseEventClickState, value: clickCount)
            downEvent.post(tap: .cghidEventTap)
            upEvent.post(tap: .cghidEventTap)
        }
    }
}
