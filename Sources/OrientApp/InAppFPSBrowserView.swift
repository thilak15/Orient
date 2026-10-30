import SwiftUI
import AppKit
import WebKit
import OrientCore

/// Direct JavaScript Pointer-Lock & MouseDelta bridge for playing 3D WebGL FPS games
/// (Deadshot.io, Krunker.io, Ev.io) directly inside Orient.app with ZERO macOS Accessibility friction.
@MainActor
public final class InAppWebGameBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    public weak var webView: WKWebView?
    public var onPointerLockChanged: ((Bool) -> Void)?
    public var onADSStateChanged: ((Bool) -> Void)?

    public private(set) var isCanvasPointerLocked: Bool = false
    public private(set) var isPageLoading: Bool = false
    public private(set) var currentURLString: String = "https://deadshot.io"

    private var pendingDX: Double = 0.0
    private var pendingDY: Double = 0.0
    private var isEvaluatingLookJS: Bool = false
    private var activeLeanState: TacticalLeanState = .upright

    public override init() {
        super.init()
    }

    public func loadGame(url: String) {
        currentURLString = url
        guard let parsed = URL(string: url) else { return }
        webView?.load(URLRequest(url: parsed))
    }

    public func reload() {
        webView?.reload()
    }

    /// Accumulates 120Hz AirPods look deltas and flushes them directly into the WebGL game's Pointer-Lock listeners.
    public func queueLookDelta(dx: Double, dy: Double) {
        pendingDX += dx
        pendingDY += dy

        guard !isEvaluatingLookJS else { return }
        guard abs(pendingDX) >= 0.15 || abs(pendingDY) >= 0.15 else { return }
        guard let webView else {
            pendingDX = 0
            pendingDY = 0
            return
        }

        let sendDX = pendingDX
        let sendDY = pendingDY
        pendingDX = 0.0
        pendingDY = 0.0
        isEvaluatingLookJS = true

        let js = String(format: "if(window.__orientInjectLookDelta){window.__orientInjectLookDelta(%.2f,%.2f);}", sendDX, sendDY)
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isEvaluatingLookJS = false
            }
        }
    }

    /// Injects Q / E tactical lean key holds directly into the WebGL game DOM.
    public func updateTacticalLean(to newState: TacticalLeanState) {
        guard newState != activeLeanState else { return }
        guard let webView else {
            activeLeanState = newState
            return
        }

        switch activeLeanState {
        case .leanLeftQ:
            webView.evaluateJavaScript("if(window.__orientInjectKey){window.__orientInjectKey('q','KeyQ',81,false);}", completionHandler: nil)
        case .leanRightE:
            webView.evaluateJavaScript("if(window.__orientInjectKey){window.__orientInjectKey('e','KeyE',69,false);}", completionHandler: nil)
        case .upright:
            break
        }

        switch newState {
        case .leanLeftQ:
            webView.evaluateJavaScript("if(window.__orientInjectKey){window.__orientInjectKey('q','KeyQ',81,true);}", completionHandler: nil)
        case .leanRightE:
            webView.evaluateJavaScript("if(window.__orientInjectKey){window.__orientInjectKey('e','KeyE',69,true);}", completionHandler: nil)
        case .upright:
            break
        }

        activeLeanState = newState
    }

    /// Injects a left or right mouse click directly onto the active WebGL canvas.
    public func injectFireClick(action: GestureAction) {
        guard let webView else { return }
        let button = (action == .rightClick) ? 2 : 0
        webView.evaluateJavaScript("if(window.__orientInjectClick){window.__orientInjectClick(\(button));}", completionHandler: nil)
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else { return }

        if type == "pointerLock", let locked = dict["locked"] as? Bool {
            isCanvasPointerLocked = locked
            onPointerLockChanged?(locked)
        } else if type == "ads", let active = dict["active"] as? Bool {
            onADSStateChanged?(active)
        }
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isPageLoading = true
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageLoading = false
        if let urlStr = webView.url?.absoluteString {
            currentURLString = urlStr
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isPageLoading = false
    }

    public static let pointerLockBridgeScript: String = """
    (function() {
      if (window.__orientBridgeInstalled) return;
      window.__orientBridgeInstalled = true;
      window.__orientLockedElement = null;
      window.__orientMouseButtons = 0;

      function notifyBridge(payload) {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.orientBridge) {
            window.webkit.messageHandlers.orientBridge.postMessage(payload);
          }
        } catch (e) {}
      }

      try {
        Object.defineProperty(Document.prototype, 'pointerLockElement', {
          get: function() { return window.__orientLockedElement || document.querySelector('canvas') || null; },
          configurable: true
        });
        Object.defineProperty(Document.prototype, 'mozPointerLockElement', {
          get: function() { return window.__orientLockedElement || document.querySelector('canvas') || null; },
          configurable: true
        });
        Object.defineProperty(Document.prototype, 'webkitPointerLockElement', {
          get: function() { return window.__orientLockedElement || document.querySelector('canvas') || null; },
          configurable: true
        });
      } catch (e) {}

      Element.prototype.requestPointerLock = function() {
        window.__orientLockedElement = this;
        try { this.style.cursor = 'crosshair'; } catch (e) {}
        notifyBridge({ type: 'pointerLock', locked: true });
        setTimeout(function() {
          document.dispatchEvent(new Event('pointerlockchange', { bubbles: true }));
          document.dispatchEvent(new Event('mozpointerlockchange', { bubbles: true }));
          document.dispatchEvent(new Event('webkitpointerlockchange', { bubbles: true }));
        }, 0);
        return Promise.resolve();
      };

      Element.prototype.mozRequestPointerLock = Element.prototype.requestPointerLock;
      Element.prototype.webkitRequestPointerLock = Element.prototype.requestPointerLock;

      Document.prototype.exitPointerLock = function() {
        if (window.__orientLockedElement) {
          try { window.__orientLockedElement.style.cursor = 'default'; } catch (e) {}
        }
        window.__orientLockedElement = null;
        notifyBridge({ type: 'pointerLock', locked: false });
        setTimeout(function() {
          document.dispatchEvent(new Event('pointerlockchange', { bubbles: true }));
          document.dispatchEvent(new Event('mozpointerlockchange', { bubbles: true }));
          document.dispatchEvent(new Event('webkitpointerlockchange', { bubbles: true }));
        }, 0);
      };

      window.addEventListener('mousedown', function(e) {
        window.__orientMouseButtons = e.buttons || 1;
        if (e.button === 2) {
          notifyBridge({ type: 'ads', active: true });
        }
        if (e.target && e.target.tagName === 'CANVAS' && !window.__orientLockedElement) {
          window.__orientLockedElement = e.target;
          notifyBridge({ type: 'pointerLock', locked: true });
          document.dispatchEvent(new Event('pointerlockchange', { bubbles: true }));
        }
      }, true);

      window.addEventListener('mouseup', function(e) {
        window.__orientMouseButtons = e.buttons || 0;
        if (e.button === 2) {
          notifyBridge({ type: 'ads', active: false });
        }
      }, true);

      window.__orientInjectLookDelta = function(dx, dy) {
        const target = window.__orientLockedElement || document.querySelector('canvas') || document.body || document;
        if (target) {
          const rect = target.getBoundingClientRect ? target.getBoundingClientRect() : { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight };
          const cx = Math.round(rect.left + rect.width * 0.5);
          const cy = Math.round(rect.top + rect.height * 0.5);

          const ev = new MouseEvent('mousemove', {
            bubbles: true,
            cancelable: true,
            view: window,
            clientX: cx,
            clientY: cy,
            screenX: cx,
            screenY: cy,
            buttons: window.__orientMouseButtons || 0
          });
          const rdx = Math.round(dx * 100) / 100;
          const rdy = Math.round(dy * 100) / 100;
          Object.defineProperty(ev, 'movementX', { get: function() { return rdx; } });
          Object.defineProperty(ev, 'movementY', { get: function() { return rdy; } });
          Object.defineProperty(ev, 'mozMovementX', { get: function() { return rdx; } });
          Object.defineProperty(ev, 'mozMovementY', { get: function() { return rdy; } });
          Object.defineProperty(ev, 'webkitMovementX', { get: function() { return rdx; } });
          Object.defineProperty(ev, 'webkitMovementY', { get: function() { return rdy; } });
          target.dispatchEvent(ev);
        }

        // Also forward to any child iframes
        const frames = document.querySelectorAll('iframe');
        for (let i = 0; i < frames.length; i++) {
          try {
            if (frames[i].contentWindow && frames[i].contentWindow.__orientInjectLookDelta) {
              frames[i].contentWindow.__orientInjectLookDelta(dx, dy);
            }
          } catch (e) {}
        }
      };

      window.__orientInjectKey = function(key, code, keyCode, isDown) {
        const type = isDown ? 'keydown' : 'keyup';
        const target = window.__orientLockedElement || document.querySelector('canvas') || document.body || window;
        const ev = new KeyboardEvent(type, {
          key: key,
          code: code,
          keyCode: keyCode,
          which: keyCode,
          bubbles: true,
          cancelable: true
        });
        target.dispatchEvent(ev);
        document.dispatchEvent(ev);
        window.dispatchEvent(ev);
      };

      window.__orientInjectClick = function(btn) {
        const target = window.__orientLockedElement || document.querySelector('canvas') || document.body;
        if (!target) return;
        const rect = target.getBoundingClientRect ? target.getBoundingClientRect() : { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight };
        const cx = Math.round(rect.left + rect.width * 0.5);
        const cy = Math.round(rect.top + rect.height * 0.5);
        const downEv = new MouseEvent('mousedown', {
          bubbles: true, cancelable: true, view: window,
          button: btn, buttons: btn === 2 ? 2 : 1, clientX: cx, clientY: cy
        });
        const upEv = new MouseEvent('mouseup', {
          bubbles: true, cancelable: true, view: window,
          button: btn, buttons: 0, clientX: cx, clientY: cy
        });
        target.dispatchEvent(downEv);
        setTimeout(function() { target.dispatchEvent(upEv); }, 35);
      };
    })();
    """
}

public struct InAppFPSWebViewRepresentable: NSViewRepresentable {
    public let bridge: InAppWebGameBridge
    public let initialURL: String

    public init(bridge: InAppWebGameBridge, initialURL: String) {
        self.bridge = bridge
        self.initialURL = initialURL
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let userContent = WKUserContentController()
        let script = WKUserScript(
            source: InAppWebGameBridge.pointerLockBridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContent.addUserScript(script)
        userContent.add(bridge, name: "orientBridge")
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.navigationDelegate = bridge
        webView.uiDelegate = bridge
        bridge.webView = webView

        if let url = URL(string: initialURL) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
