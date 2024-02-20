import Foundation

extension Shared {
  @_disfavoredOverload
  public init(_ value: Value, fileID: StaticString = #fileID, line: UInt = #line) {
    self.init(reference: ValueReference(value, fileID: fileID, line: line))
  }

  @_disfavoredOverload
  @available(
    *,
    deprecated,
    message: "Use '@Shared' with a value type or supported reference type"
  )
  public init(_ value: Value, fileID: StaticString = #fileID, line: UInt = #line)
  where Value: AnyObject {
    self.init(reference: ValueReference(value, fileID: fileID, line: line))
  }

  public init(
    wrappedValue value: @autoclosure @escaping () -> Value,
    _ persistentValue: some Persistent<Value>,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) {
    self.init(
      reference: {
        @Dependency(PersistentReferencesKey.self) var references
        return references.withValue {
          if let reference = $0[persistentValue] {
            return reference
          } else {
            let reference = ValueReference(
              initialValue: value(),
              persistentValue: persistentValue,
              fileID: fileID,
              line: line
            )
            $0[persistentValue] = reference
            return reference
          }
        }
      }(),
      keyPath: \Value.self
    )
  }

  @_disfavoredOverload
  @available(
    *,
    deprecated,
    message: "Use '@Shared' with a value type or supported reference type"
  )
  public init(
    wrappedValue value: @autoclosure @escaping () -> Value,
    _ persistentValue: some Persistent<Value>,
    fileID: StaticString = #fileID,
    line: UInt = #line
  ) where Value: AnyObject {
    self.init(wrappedValue: value(), persistentValue, fileID: fileID, line: line)
  }
}

private final class ValueReference<Value>: Reference {
  private var _currentValue: Value
  private var _snapshot: Value?
  fileprivate var persistentValue: (any Persistent<Value>)?  // TODO: Should this not be an `any`?
  private let fileID: StaticString
  private let line: UInt
  private let lock = NSRecursiveLock()
  private let _$perceptionRegistrar = PerceptionRegistrar(
    isPerceptionCheckingEnabled: _isStorePerceptionCheckingEnabled
  )

  init(
    initialValue: @autoclosure @escaping () -> Value,
    persistentValue: some Persistent<Value>,
    fileID: StaticString,
    line: UInt
  ) {
    self._currentValue = persistentValue.load() ?? initialValue()
    self.persistentValue = persistentValue
    self.fileID = fileID
    self.line = line
    Task { @MainActor[weak self, initialValue] in
      for try await value in persistentValue.updates {
        self?.currentValue = value ?? initialValue()
      }
    }
  }

  init(
    _ value: Value,
    fileID: StaticString,
    line: UInt
  ) {
    self._currentValue = value
    self.persistentValue = nil
    self.fileID = fileID
    self.line = line
  }

  deinit {
    self.assertUnchanged()
  }

  var currentValue: Value {
    _read {
      // TODO: write test for deadlock, unit test and UI test
      self._$perceptionRegistrar.access(self, keyPath: \.currentValue)
      self.lock.lock()
      defer { self.lock.unlock() }
      yield self._currentValue
    }
    _modify {
      self._$perceptionRegistrar.willSet(self, keyPath: \.currentValue)
      defer { self._$perceptionRegistrar.didSet(self, keyPath: \.currentValue) }
      self.lock.lock()
      defer { self.lock.unlock() }
      yield &self._currentValue
      self.persistentValue?.save(self._currentValue)
    }
    set {
      self._$perceptionRegistrar.withMutation(of: self, keyPath: \.currentValue) {
        self.lock.withLock {
          self._currentValue = newValue
          self.persistentValue?.save(newValue)
        }
      }
    }
  }

  var snapshot: Value? {
    _read {
      self.lock.lock()
      defer { self.lock.unlock() }
      yield self._snapshot
    }
    _modify {
      self.lock.lock()
      defer { self.lock.unlock() }
      yield &self._snapshot
    }
    set {
      self.lock.withLock { self._snapshot = newValue }
    }
  }

  var description: String {
    "Shared<\(Value.self)>@\(self.fileID):\(self.line)"
  }
}

extension ValueReference: Equatable where Value: Equatable {
  static func == (lhs: ValueReference, rhs: ValueReference) -> Bool {
    if lhs === rhs {
      return lhs.snapshot ?? lhs.currentValue == rhs.currentValue
    } else {
      return lhs.currentValue == rhs.currentValue
    }
  }
}

#if !os(visionOS)
  extension ValueReference: Perceptible {}
#endif

#if canImport(Observation)
  extension ValueReference: Observable {}
#endif