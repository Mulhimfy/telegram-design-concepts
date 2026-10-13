import Foundation

// Signature stubs of SwiftSignalKit (submodules/SSignalKit/SwiftSignalKit/Source).

// Real: `public enum NoError {}` (SwiftSignalKit/Source/Signal.swift:8) — uninhabited, not an Error.
public enum NoError {
}

public protocol Disposable: AnyObject {
    func dispose()
}

public final class ActionDisposable: Disposable {
    private var action: (() -> Void)?

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public func dispose() {
        let action = self.action
        self.action = nil
        action?()
    }
}

public final class DisposableDict<T: Hashable>: Disposable {
    private var disposed = false
    private var disposables: [T: Disposable] = [:]

    public init() {
    }

    public func set(_ disposable: Disposable?, forKey key: T) {
        if self.disposed {
            disposable?.dispose()
            return
        }
        let previous = self.disposables[key]
        if let disposable = disposable {
            self.disposables[key] = disposable
        }
        previous?.dispose()
    }

    public func dispose() {
        self.disposed = true
        let disposables = self.disposables
        self.disposables.removeAll()
        for (_, disposable) in disposables {
            disposable.dispose()
        }
    }
}

public final class Subscriber<T, E> {
    private let next: ((T) -> Void)?
    private let error: ((E) -> Void)?
    private let completed: (() -> Void)?

    init(next: ((T) -> Void)?, error: ((E) -> Void)?, completed: (() -> Void)?) {
        self.next = next
        self.error = error
        self.completed = completed
    }

    public func putNext(_ next: T) {
        self.next?(next)
    }

    public func putError(_ error: E) {
        self.error?(error)
    }

    public func putCompletion() {
        self.completed?()
    }
}

public final class Signal<T, E> {
    private let generator: (Subscriber<T, E>) -> Disposable

    public init(_ generator: @escaping (Subscriber<T, E>) -> Disposable) {
        self.generator = generator
    }

    public func start(next: ((T) -> Void)! = nil, error: ((E) -> Void)! = nil, completed: (() -> Void)! = nil) -> Disposable {
        return self.generator(Subscriber(next: next, error: error, completed: completed))
    }

    public static func single(_ value: T) -> Signal<T, E> {
        return Signal { subscriber in
            subscriber.putNext(value)
            subscriber.putCompletion()
            return ActionDisposable(action: {})
        }
    }
}

precedencegroup PipeRight {
    associativity: left
    higherThan: DefaultPrecedence
}

infix operator |> : PipeRight

public func |> <T, U>(value: T, function: ((T) -> U)) -> U {
    return function(value)
}

public func map<T, E, R>(_ f: @escaping (T) -> R) -> (Signal<T, E>) -> Signal<R, E> {
    return { signal in
        return Signal { subscriber in
            return signal.start(next: { value in
                subscriber.putNext(f(value))
            }, error: { error in
                subscriber.putError(error)
            }, completed: {
                subscriber.putCompletion()
            })
        }
    }
}

public func deliverOnMainQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> {
    return Signal { subscriber in
        return signal.start(next: { value in
            DispatchQueue.main.async {
                subscriber.putNext(value)
            }
        }, error: { error in
            DispatchQueue.main.async {
                subscriber.putError(error)
            }
        }, completed: {
            DispatchQueue.main.async {
                subscriber.putCompletion()
            }
        })
    }
}
