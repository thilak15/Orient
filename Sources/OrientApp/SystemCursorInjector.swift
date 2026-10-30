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

    // Sub-pixel residual accumulators (macOS kCGMouseEventDeltaX/Y are int64 fields;
    // without residual accumulation, sub-pixel 120Hz deltas < 1.0px truncate to 0!)
    private var residualDeltaX: Double = 0.0
    private var residualDeltaY: Double = 0.0

    // macOS Virtual KeyCodes
    private let keyCodeQ: CGKeyCode = 12
    private let keyCodeE: CGKeyCode = 14
    private let keyCodeSpace: CGKeyCode = 49
    private let keyCodeR: CGKeyCode = 15

    public init() {
        let src = CGEventSource(stateID: .hidSystemState)
        src?.localEventsSuppressionInterval = 0.0
        self.eventSource = src
    }

    public static func isAccessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        if promptIfNeeded {
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            let options = [promptKey: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    /// Resets any stale ad-hoc CDHash entry in macOS TCC and triggers a fresh Accessibility prompt.
    public static func resetStaleTCCAndPromptAccessibility() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", "com.orient.cursorlab"]
        try? process.run()
        process.waitUntilExit()

        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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

    /// Moves the macOS cursor and sets integer hardware deltaX/deltaY fields for 3D Pointer-Lock FPS games.
    public func moveCursor(
        to target: Point2D,
        deltaX: Double,
        deltaY: Double,
        injectionProtocol: GameInjectionProtocol = .pointerLockRawDelta,
        shouldResetTouchDragAnchor: Bool = false,
        lockCursorInPlaceFor3DGame: Bool = false
    ) {
        residualDeltaX += deltaX
        residualDeltaY += deltaY

        let intDX = Int64(residualDeltaX.rounded(.towardZero))
        let intDY = Int64(residualDeltaY.rounded(.towardZero))

        if intDX == 0 && intDY == 0 && !shouldResetTouchDragAnchor {
            return
        }

        residualDeltaX -= Double(intDX)
        residualDeltaY -= Double(intDY)

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
                drag.setIntegerValueField(.mouseEventDeltaX, value: intDX)
                drag.setIntegerValueField(.mouseEventDeltaY, value: intDY)
                drag.post(tap: .cghidEventTap)
            }
            return
        }

        if isTouchDragging {
            releaseTouchDragIfNeeded()
        }

        // Preserve physical mouse button state so aiming while firing (Left-Click) or ADS scoping (Right-Click) works seamlessly
        let isLeftDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let isRightDown = CGEventSource.buttonState(.combinedSessionState, button: .right)

        let eventType: CGEventType
        let mouseButton: CGMouseButton
        if isLeftDown {
            eventType = .leftMouseDragged
            mouseButton = .left
        } else if isRightDown {
            eventType = .rightMouseDragged
            mouseButton = .right
        } else {
            eventType = .mouseMoved
            mouseButton = .left
        }

        // In 3D Game Pointer-Lock mode, keep cursor position inside the active game window
        // so turning 360° never drags the cursor onto the macOS Dock, Menu Bar, or Browser URL bar.
        let cursorPt: CGPoint
        if lockCursorInPlaceFor3DGame {
            let cur = currentCursorPosition()
            cursorPt = CGPoint(x: cur.x, y: cur.y)
        } else {
            cursorPt = CGPoint(x: target.x, y: target.y)
        }

        if let moveEvent = CGEvent(
            mouseEventSource: eventSource,
            mouseType: eventType,
            mouseCursorPosition: cursorPt,
            mouseButton: mouseButton
        ) {
            moveEvent.setIntegerValueField(.mouseEventDeltaX, value: intDX)
            moveEvent.setIntegerValueField(.mouseEventDeltaY, value: intDY)
            moveEvent.post(tap: .cghidEventTap)
        } else if !lockCursorInPlaceFor3DGame {
            CGWarpMouseCursorPosition(cursorPt)
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
        residualDeltaX = 0
        residualDeltaY = 0
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
