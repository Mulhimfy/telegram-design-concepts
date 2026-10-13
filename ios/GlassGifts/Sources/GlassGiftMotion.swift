import Foundation
import UIKit
import CoreMotion

/// The phone's tilt for every gift tile on screen: one shared Core Motion source (prototype/src/profile/glass-gifts.js
/// `MotionSource`, filtered by `GlassGiftMotionFilter`).
///
/// The tilt moves the light — the sheen, the prismatic streak and the lit edge — across all tiles at once, with only a
/// hint of lean. Like the TON wallet card's motion (WalletCardComponent.swift:938-973) it runs only while it is seen:
/// · a **client** is a gifts pane (`PeerInfoGiftsPaneNode`) that holds a `Client` while it is in the window; the
///   sensor runs while at least one client's view is on screen. A pane that is in the window but off screen (the tab
///   next to the selected one) puts the source on standby: the sensor stops and the source looks again twice a second.
///   With no client at all nothing runs.
/// · **listeners** are the tiles: they get every change of the value (more than 0.01°) and read `light` when they
///   draw. They don't keep the sensor on.
/// · it stops when the app resigns active and when Reduce Motion is on (then the tiles don't lean and the light
///   follows only the finger).
public final class GlassGiftMotion {
    public static let shared = GlassGiftMotion()

    private final class WeakView {
        weak var view: UIView?

        init(_ view: UIView) {
            self.view = view
        }
    }

    /// Held by whoever shows gift tiles (a gifts pane); the source runs while one of their views is on screen.
    /// Dropping it unregisters.
    public final class Client {
        fileprivate let id: Int
        private weak var source: GlassGiftMotion?

        fileprivate init(id: Int, source: GlassGiftMotion) {
            self.id = id
            self.source = source
        }

        deinit {
            let id = self.id
            let source = self.source
            if Thread.isMainThread {
                source?.removeClient(id: id)
            } else {
                DispatchQueue.main.async {
                    source?.removeClient(id: id)
                }
            }
        }
    }

    /// A tile's subscription to the value; dropping it unsubscribes.
    public final class Listener {
        fileprivate let id: Int
        private weak var source: GlassGiftMotion?

        fileprivate init(id: Int, source: GlassGiftMotion) {
            self.id = id
            self.source = source
        }

        deinit {
            let id = self.id
            let source = self.source
            if Thread.isMainThread {
                source?.removeListener(id: id)
            } else {
                DispatchQueue.main.async {
                    source?.removeListener(id: id)
                }
            }
        }
    }

    private enum Phase {
        case stopped
        /// Clients exist but none is on screen: no sensor, a look twice a second.
        case standby
        case running
    }

    /// Smallest change (degrees) passed on to the tiles.
    private static let threshold: Double = 0.01
    /// The sensor's rate (the wallet card's, WalletCardBackgroundView.swift:37-41).
    private static let interval: Double = 1.0 / 60.0
    /// How often a source on standby looks for a client on screen.
    private static let standbyInterval: Double = 0.5

    /// The current tilt in screen axes, nil while the source doesn't run.
    public private(set) var light: GlassGiftLight?

    private let manager = CMMotionManager()
    private var filter = GlassGiftMotionFilter()
    private var integrator = GlassGiftRotationIntegrator()
    private var phase: Phase = .stopped
    /// Client id → its view (weak: the source never keeps a pane alive).
    private var clients: [Int: WeakView] = [:]
    private var listeners: [Int: (GlassGiftLight?) -> Void] = [:]
    private var nextId = 0
    private var standbyTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isApplicationActive = true

    private init() {
        self.manager.deviceMotionUpdateInterval = GlassGiftMotion.interval
        if Bundle.main.bundlePath.hasSuffix(".appex") {
            self.isApplicationActive = true
        } else {
            self.isApplicationActive = UIApplication.shared.applicationState == .active
        }
        let center = NotificationCenter.default
        self.observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.isApplicationActive = false
            self?.updatePhase()
        }))
        self.observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.isApplicationActive = true
            self?.updatePhase()
        }))
        self.observers.append(center.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updatePhase()
        }))
    }

    /// Registers something that shows gift tiles (its `view` is checked for being on screen). Keep the client while
    /// the view is in the window (`didEnterHierarchy` … `didExitHierarchy`).
    public func addClient(view: UIView) -> Client {
        self.nextId += 1
        self.clients[self.nextId] = WeakView(view)
        let client = Client(id: self.nextId, source: self)
        self.updatePhase()
        return client
    }

    /// `update` gets every change of the value (nil when the source stops).
    public func addListener(_ update: @escaping (GlassGiftLight?) -> Void) -> Listener {
        self.nextId += 1
        self.listeners[self.nextId] = update
        return Listener(id: self.nextId, source: self)
    }

    private func removeClient(id: Int) {
        self.clients.removeValue(forKey: id)
        self.updatePhase()
    }

    private func removeListener(id: Int) {
        self.listeners.removeValue(forKey: id)
    }

    /// The first client view that is on screen, if any.
    private func visibleClientView() -> UIView? {
        for (_, client) in self.clients {
            if let view = client.view, GlassGiftMotion.isOnScreen(view) {
                return view
            }
        }
        return nil
    }

    /// Whether `view` shows at least a sliver in its window (a pane next to the selected one lies outside it).
    public static func isOnScreen(_ view: UIView) -> Bool {
        guard let window = view.window, !view.isHidden, view.alpha > 0.01 else {
            return false
        }
        let frame = view.convert(view.bounds, to: window).intersection(window.bounds)
        return !frame.isNull && frame.width >= 1.0 && frame.height >= 1.0
    }

    private var canRun: Bool {
        return self.isApplicationActive && !UIAccessibility.isReduceMotionEnabled && self.manager.isDeviceMotionAvailable
    }

    private func updatePhase() {
        let phase: Phase
        if self.clients.isEmpty || !self.canRun {
            phase = .stopped
        } else if self.visibleClientView() != nil {
            phase = .running
        } else {
            phase = .standby
        }
        self.setPhase(phase)
    }

    private func setPhase(_ phase: Phase) {
        if self.phase == phase {
            return
        }
        self.phase = phase

        if phase == .running {
            self.standbyTimer?.invalidate()
            self.standbyTimer = nil
            // The first reading is the reference again: the light starts from neutral.
            self.filter.reset()
            self.integrator.reset()
            self.manager.startDeviceMotionUpdates(to: .main, withHandler: { [weak self] motion, _ in
                guard let self, let motion else {
                    return
                }
                self.handle(motion)
            })
        } else {
            if self.manager.isDeviceMotionActive {
                self.manager.stopDeviceMotionUpdates()
            }
            self.publish(nil)
            if phase == .standby {
                if self.standbyTimer == nil {
                    let timer = Timer(timeInterval: GlassGiftMotion.standbyInterval, repeats: true, block: { [weak self] _ in
                        self?.updatePhase()
                    })
                    self.standbyTimer = timer
                    RunLoop.main.add(timer, forMode: .common)
                }
            } else {
                self.standbyTimer?.invalidate()
                self.standbyTimer = nil
            }
        }
    }

    private func handle(_ motion: CMDeviceMotion) {
        guard self.phase == .running else {
            return
        }
        guard let view = self.visibleClientView() else {
            self.updatePhase()
            return
        }
        let dt = self.integrator.add(rateX: motion.rotationRate.x, rateY: motion.rotationRate.y, timestamp: motion.timestamp)
        self.filter.feed(beta: self.integrator.beta, gamma: self.integrator.gamma)
        guard let value = self.filter.update(dt: dt) else {
            return
        }
        let light = GlassGiftMotion.screenRotation(of: view).apply(value)
        if let current = self.light, abs(current.x - light.x) < GlassGiftMotion.threshold && abs(current.y - light.y) < GlassGiftMotion.threshold {
            return
        }
        self.publish(light)
    }

    private func publish(_ light: GlassGiftLight?) {
        if self.light == light {
            return
        }
        self.light = light
        for (_, update) in self.listeners {
            update(light)
        }
    }

    private static func screenRotation(of view: UIView) -> GlassGiftScreenRotation {
        switch view.window?.windowScene?.interfaceOrientation ?? .portrait {
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .portrait
        }
    }
}
