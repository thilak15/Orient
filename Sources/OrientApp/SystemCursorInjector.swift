import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import OrientCore

/// Low-latency macOS cursor & mouse click injector using CoreGraphics HID events.
public final class SystemCursorInjector: @unchecked Sendable {
    private let eventSource: CGEventSource?

    public init() {
        self.eventSource = CGEventSource(stateID: .hidSystemState)
    }

    /// Returns whether the process currently has macOS Accessibility trust to inject HID events.
    public static func isAccessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        if promptIfNeeded {
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            let options = [promptKey: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    /// Current mouse cursor location in Quartz global top-left coordinates.
    public func currentCursorPosition() -> Point2D {
        if let event = CGEvent(source: nil) {
            let loc = event.location
            return Point2D(x: loc.x, y: loc.y)
        }
        return Point2D(x: 600, y: 400)
    }

    /// Combined Quartz screen bounds across connected displays.
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

    /// Moves the macOS system cursor and sets hardware deltaX/deltaY fields.
    public func moveCursor(to target: Point2D, deltaX: Double, deltaY: Double) {
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

    /// Executes a synthetic mouse click at the specified position (supporting Pre-Click Rollback).
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

