@_spi(Internals) import ComposableArchitecture
import XCTest

#if swift(>=5.7)
  @MainActor
  final class StackReducerTests: BaseTCATestCase {
    func testStackState() async {
      // TODO: flesh out state test
    }

    func testCustomDebugStringConvertible() {
      @Dependency(\.stackElementID) var stackElementID
      XCTAssertEqual(stackElementID.peek().rawValue.base.base as! Int, 0)
      XCTAssertEqual(stackElementID.next().customDumpDescription, "#0")
      XCTAssertEqual(stackElementID.peek().rawValue.base.base as! Int, 1)
      XCTAssertEqual(stackElementID.next().customDumpDescription, "#1")

      withDependencies {
        $0.context = .live
      } operation: {
        XCTAssertEqual(stackElementID.next().customDumpDescription, "#0")
        XCTAssertEqual(stackElementID.next().customDumpDescription, "#1")
        XCTAssertTrue(stackElementID.peek().rawValue.base.base is UUID)
      }
    }

    func testPresent() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {
          var count = 0
        }
        enum Action: Equatable {
          case decrementButtonTapped
          case incrementButtonTapped
        }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .decrementButtonTapped:
            state.count -= 1
            return .none
          case .incrementButtonTapped:
            state.count += 1
            return .none
          }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var children = StackState<Child.State>()
        }
        enum Action: Equatable {
          case children(StackAction<Child.State, Child.Action>)
          case pushChild
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .children:
              return .none
            case .pushChild:
              state.children.append(Child.State())
              return .none
            }
          }
          .forEach(\.children, action: /Action.children) {
            Child()
          }
        }
      }

      let store = TestStore(initialState: Parent.State(), reducer: Parent())

      await store.send(.pushChild) {
        $0.children.append(Child.State())
      }
    }

    func testDismissFromParent() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {}
        enum Action: Equatable {
          case onAppear
        }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .onAppear:
            return .fireAndForget {
              try await Task.never()
            }
          }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var children = StackState<Child.State>()
        }
        enum Action: Equatable {
          case children(StackAction<Child.State, Child.Action>)
          case popChild
          case pushChild
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .children:
              return .none
            case .popChild:
              state.children.removeLast()
              return .none
            case .pushChild:
              state.children.append(Child.State())
              return .none
            }
          }
          .forEach(\.children, action: /Action.children) {
            Child()
          }
        }
      }

      let store = TestStore(initialState: Parent.State(), reducer: Parent())

      await store.send(.pushChild) {
        $0.children.append(Child.State())
      }
      await store.send(.children(.element(id: 0, action: .onAppear)))
      await store.send(.popChild) {
        $0.children.removeLast()
      }
    }

    func testDismissFromChild() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {}
        enum Action: Equatable {
          case closeButtonTapped
          case onAppear
        }
        @Dependency(\.dismiss) var dismiss
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .closeButtonTapped:
            return .fireAndForget {
              await self.dismiss()
            }
          case .onAppear:
            return .fireAndForget {
              try await Task.never()
            }
          }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var children = StackState<Child.State>()
        }
        enum Action: Equatable {
          case children(StackAction<Child.State, Child.Action>)
          case pushChild
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .children:
              return .none
            case .pushChild:
              state.children.append(Child.State())
              return .none
            }
          }
          .forEach(\.children, action: /Action.children) {
            Child()
          }
        }
      }

      let store = TestStore(initialState: Parent.State(), reducer: Parent())

      await store.send(.pushChild) {
        $0.children.append(Child.State())
      }
      await store.send(.children(.element(id: 0, action: .onAppear)))
      await store.send(.children(.element(id: 0, action: .closeButtonTapped)))
      await store.receive(.children(.popFrom(id: 0))) {
        $0.children.removeLast()
      }
    }

    func testDismissFromDeepLinkedChild() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {}
        enum Action: Equatable {
          case closeButtonTapped
        }
        @Dependency(\.dismiss) var dismiss
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .closeButtonTapped:
            return .fireAndForget {
              await self.dismiss()
            }
          }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var children = StackState<Child.State>()
        }
        enum Action: Equatable {
          case children(StackAction<Child.State, Child.Action>)
          case pushChild
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .children:
              return .none
            case .pushChild:
              state.children.append(Child.State())
              return .none
            }
          }
          .forEach(\.children, action: /Action.children) {
            Child()
          }
        }
      }

      var children = StackState<Child.State>()
      children.append(Child.State())
      let store = TestStore(
        initialState: Parent.State(children: children), reducer: Parent()
      )

      await store.send(.children(.element(id: 0, action: .closeButtonTapped)))
      await store.receive(.children(.popFrom(id: 0))) {
        $0.children.removeAll()
      }
    }

    func testEnumChild() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {
          var count = 0
        }
        enum Action: Equatable {
          case closeButtonTapped
          case incrementButtonTapped
          case onAppear
        }
        @Dependency(\.dismiss) var dismiss
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .closeButtonTapped:
            return .fireAndForget {
              await self.dismiss()
            }
          case .incrementButtonTapped:
            state.count += 1
            return .none
          case .onAppear:
            return .fireAndForget {
              try await Task.never()
            }
          }
        }
      }
      struct Navigation: ReducerProtocol {
        enum State: Equatable {
          case child1(Child.State)
          case child2(Child.State)
        }
        enum Action: Equatable {
          case child1(Child.Action)
          case child2(Child.Action)
        }
        var body: some ReducerProtocol<State, Action> {
          Scope(state: /State.child1, action: /Action.child1) {
            Child()
          }
          Scope(state: /State.child2, action: /Action.child2) {
            Child()
          }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var path = StackState<Navigation.State>()
        }
        enum Action: Equatable {
          case path(StackAction<Navigation.State, Navigation.Action>)
          case pushChild1
          case pushChild2
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .path:
              return .none
            case .pushChild1:
              state.path.append(.child1(Child.State()))
              return .none
            case .pushChild2:
              state.path.append(.child2(Child.State()))
              return .none
            }
          }
          .forEach(\.path, action: /Action.path) {
            Navigation()
          }
        }
      }

      let store = TestStore(initialState: Parent.State(), reducer: Parent()._printChanges())
      await store.send(.pushChild1) {
        $0.path.append(.child1(Child.State()))
      }
      await store.send(.path(.element(id: 0, action: .child1(.onAppear))))
      await store.send(.pushChild2) {
        $0.path.append(.child2(Child.State()))
      }
      await store.send(.path(.element(id: 1, action: .child2(.onAppear))))
      await store.send(.path(.popFrom(id: 0))) {
        $0.path.removeAll()
      }
    }

    func testParentDismiss() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {}
        enum Action { case tap }
        @Dependency(\.dismiss) var dismiss
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          .fireAndForget { try await Task.never() }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var path = StackState<Child.State>()
        }
        enum Action {
          case path(StackAction<Child.State, Child.Action>)
          case popToRoot
          case pushChild
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .path:
              return .none
            case .popToRoot:
              state.path.removeAll()
              return .none
            case .pushChild:
              state.path.append(Child.State())
              return .none
            }
          }
          .forEach(\.path, action: /Action.path) {
            Child()
          }
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )
      await store.send(.pushChild) {
        $0.path.append(Child.State())
      }
      await store.send(.path(.element(id: 0, action: .tap)))
      await store.send(.pushChild) {
        $0.path.append(Child.State())
      }
      await store.send(.path(.element(id: 1, action: .tap)))
      await store.send(.popToRoot) {
        $0.path.removeAll()
      }
    }


    func testSiblingCannotCancel() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {
          var count = 0
        }
        enum Action: Equatable {
          case cancel
          case response(Int)
          case tap
        }
        @Dependency(\.mainQueue) var mainQueue
        enum CancelID: Hashable { case cancel }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .cancel:
            return .cancel(id: CancelID.cancel)
          case let .response(value):
            state.count = value
            return .none
          case .tap:
            return .task {
              try await self.mainQueue.sleep(for: .seconds(1))
              return .response(42)
            }
            .cancellable(id: CancelID.cancel)
          }
        }
      }
      struct Navigation: ReducerProtocol {
        enum State: Equatable {
          case child1(Child.State)
          case child2(Child.State)
        }
        enum Action: Equatable {
          case child1(Child.Action)
          case child2(Child.Action)
        }
        var body: some ReducerProtocol<State, Action> {
          Scope(state: /State.child1, action: /Action.child1) { Child() }
          Scope(state: /State.child2, action: /Action.child2) { Child() }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var path = StackState<Navigation.State>()
        }
        enum Action: Equatable {
          case path(StackAction<Navigation.State, Navigation.Action>)
          case pushChild1
          case pushChild2
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .path:
              return .none
            case .pushChild1:
              state.path.append(.child1(Child.State()))
              return .none
            case .pushChild2:
              state.path.append(.child2(Child.State()))
              return .none
            }
          }
          .forEach(\.path, action: /Action.path) {
            Navigation()
          }
        }
      }

      var path = StackState<Navigation.State>()
      path.append(.child1(Child.State()))
      path.append(.child2(Child.State()))
      let mainQueue = DispatchQueue.test
      let store = TestStore(
        initialState: Parent.State(path: path),
        reducer: Parent()
      ) {
        $0.mainQueue = mainQueue.eraseToAnyScheduler()
      }

      await store.send(.path(.element(id: 0, action: .child1(.tap))))
      await store.send(.path(.element(id: 1, action: .child2(.tap))))
      await store.send(.path(.element(id: 0, action: .child1(.cancel))))
      await mainQueue.advance(by: .seconds(1))
      await store.receive(.path(.element(id: 1, action: .child2(.response(42))))) {
        XCTModify(&$0.path[id: 1], case: /Navigation.State.child2) {
          $0.count = 42
        }
      }

      await store.send(.path(.element(id: 0, action: .child1(.tap))))
      await store.send(.path(.element(id: 1, action: .child2(.tap))))
      await store.send(.path(.element(id: 1, action: .child2(.cancel))))
      await mainQueue.advance(by: .seconds(1))
      await store.receive(.path(.element(id: 0, action: .child1(.response(42))))) {
        XCTModify(&$0.path[id: 0], case: /Navigation.State.child1) {
          $0.count = 42
        }
      }
    }

    func testFirstChildWhileEffectInFlight_DeliversToCorrectID() async {
      struct Child: ReducerProtocol {
        let id: Int
        struct State: Equatable {
          var count = 0
        }
        enum Action: Equatable {
          case response(Int)
          case tap
        }
        @Dependency(\.mainQueue) var mainQueue
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case let .response(value):
            state.count += value
            return .none
          case .tap:
            return .task {
              try await self.mainQueue.sleep(for: .seconds(self.id))
              return .response(self.id)
            }
          }
        }
      }
      // TODO: naming options: Stack, Path,
      struct Navigation: ReducerProtocol {
        enum State: Equatable {
          case child1(Child.State)
          case child2(Child.State)
        }
        enum Action: Equatable {
          case child1(Child.Action)
          case child2(Child.Action)
        }
        var body: some ReducerProtocol<State, Action> {
          Scope(state: /State.child1, action: /Action.child1) { Child(id: 1) }
          Scope(state: /State.child2, action: /Action.child2) { Child(id: 2) }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var path = StackState<Navigation.State>()
        }
        enum Action: Equatable {
          case path(StackAction<Navigation.State, Navigation.Action>)
          case popAll
          case popFirst
        }
        var body: some ReducerProtocol<State, Action> {
          Reduce { state, action in
            switch action {
            case .path:
              return .none
            case .popAll:
              state.path = StackState()
              return .none
            case .popFirst:
              state.path[id: state.path.ids[0]] = nil
              return .none
            }
          }
          .forEach(\.path, action: /Action.path) {
            Navigation()
          }
        }
      }

      let mainQueue = DispatchQueue.test
      let store = TestStore(
        initialState: Parent.State(
          path: StackState().appending(contentsOf: [
            .child1(Child.State()),
            .child2(Child.State()),
          ])
        ),
        reducer: Parent()
      ) {
        $0.mainQueue = mainQueue.eraseToAnyScheduler()
      }

      await store.send(.path(.element(id: 0, action: .child1(.tap))))
      await store.send(.path(.element(id: 1, action: .child2(.tap))))
      await mainQueue.advance(by: .seconds(1))
      await store.receive(.path(.element(id: 0, action: .child1(.response(1))))) {
        XCTModify(&$0.path[id: 0], case: /Navigation.State.child1) {
          $0.count = 1
        }
      }
      await mainQueue.advance(by: .seconds(1))
      await store.receive(.path(.element(id: 1, action: .child2(.response(2))))) {
        XCTModify(&$0.path[id: 1], case: /Navigation.State.child2) {
          $0.count = 2
        }
      }

      await store.send(.path(.element(id: 0, action: .child1(.tap))))
      await store.send(.path(.element(id: 1, action: .child2(.tap))))
      await store.send(.popFirst) {
        $0.path[id: 0] = nil
      }
      await mainQueue.advance(by: .seconds(2))
      await store.receive(.path(.element(id: 1, action: .child2(.response(2))))) {
        XCTModify(&$0.path[id: 1], case: /Navigation.State.child2) {
          $0.count = 4
        }
      }
      await store.send(.popFirst) {
        $0.path[id: 1] = nil
      }
    }

    func testSendActionWithIDThatDoesNotExist() async {
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var path = StackState<Int>()
        }
        enum Action {
          case path(StackAction<Int, Void>)
        }
        var body: some ReducerProtocol<State, Action> {
          EmptyReducer()
            .forEach(\.path, action: /Action.path) { EmptyReducer() }
        }
      }

      XCTExpectFailure {
        $0.compactDescription == """
          TODO
          """
      }

      var path = StackState<Int>()
      path.append(1)
      let store = TestStore(
        initialState: Parent.State(path: path),
        reducer: Parent()
      )
      await store.send(.path(.element(id: 999, action: ())))
    }

    func testPopIDThatDoesNotExist() async {
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var path = StackState<Int>()
        }
        enum Action {
          case path(StackAction<Int, Void>)
        }
        var body: some ReducerProtocol<State, Action> {
          EmptyReducer()
            .forEach(\.path, action: /Action.path) { EmptyReducer() }
        }
      }

      XCTExpectFailure {
        $0.compactDescription == """
          TODO
          """
      }

      var path = StackState<Int>()
      path.append(1)
      let store = TestStore(
        initialState: Parent.State(path: path),
        reducer: Parent()
      )
      await store.send(.path(.popFrom(id: 999)))
    }
 
    func testChildWithInFlightEffect() async {
      struct Child: ReducerProtocol {
        struct State: Equatable {}
        enum Action { case tap }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          .fireAndForget { try await Task.never() }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var path = StackState<Child.State>()
        }
        enum Action {
          case path(StackAction<Child.State, Child.Action>)
        }
        var body: some ReducerProtocol<State, Action> {
          EmptyReducer()
            .forEach(\.path, action: /Action.path) { Child() }
        }
      }

      var path = StackState<Child.State>()
      path.append(Child.State())
      let store = TestStore(
        initialState: Parent.State(path: path),
        reducer: Parent()
      )
      let line = #line
      await store.send(.path(.element(id: 0, action: .tap)))

      XCTExpectFailure {
        $0.sourceCodeContext.location?.fileURL.absoluteString.contains("BaseTCATestCase") == true
        || $0.sourceCodeContext.location?.lineNumber == line + 1
        && $0.compactDescription == """
          An effect returned for this action is still running. It must complete before the end of \
          the test. …

          To fix, inspect any effects the reducer returns for this action and ensure that all of \
          them complete by the end of the test. There are a few reasons why an effect may not have \
          completed:

          • If using async/await in your effect, it may need a little bit of time to properly \
          finish. To fix you can simply perform "await store.finish()" at the end of your test.

          • If an effect uses a clock/scheduler (via "receive(on:)", "delay", "debounce", etc.), \
          make sure that you wait enough time for it to perform the effect. If you are using a \
          test clock/scheduler, advance it so that the effects may complete, or consider using an \
          immediate clock/scheduler to immediately perform the effect instead.

          • If you are returning a long-living effect (timers, notifications, subjects, etc.), \
          then make sure those effects are torn down by marking the effect ".cancellable" and \
          returning a corresponding cancellation effect ("Effect.cancel") from another action, or, \
          if your effect is driven by a Combine subject, send it a completion.
          """
      }
    }

    func testExpressibleByIntegerLiteralWarning() {
      XCTExpectFailure {
        withDependencies {
          $0.context = .live
        } operation: {
          let _: StackElementID = 0
        }
      } issueMatcher: {
        $0.compactDescription == """
          Specifying stack element IDs by integer literal is not allowed outside of tests.

          In tests, integer literal stack element IDs can be used as a shorthand to the \
          auto-incrementing generation of the current dependency context. This can be useful when \
          asserting against actions received by a specific element.
          """
      }
    }

    func testMultipleChildEffects() async {
      struct Child: ReducerProtocol {
        struct State: Equatable { var count = 0 }
        enum Action: Equatable { case tap, response(Int) }
        @Dependency(\.mainQueue) var mainQueue
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          switch action {
          case .tap:
            return .run { [count = state.count] send in
              try await self.mainQueue.sleep(for: .seconds(count))
              await send(.response(42))
            }
          case let .response(value):
            state.count = value
            return .none
          }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var children: StackState<Child.State>
        }
        enum Action: Equatable {
          case child(StackAction<Child.State, Child.Action>)
        }
        var body: some ReducerProtocolOf<Self> {
          Reduce { _, _ in .none }
          .forEach(\.children, action: /Action.child) { Child() }
        }
      }

      let mainQueue = DispatchQueue.test
      let store = TestStore(
        initialState: Parent.State(
          children: StackState().appending(contentsOf: [
            Child.State(count: 1),
            Child.State(count: 2),
          ])
        ),
        reducer: Parent()
      ) {
        $0.mainQueue = mainQueue.eraseToAnyScheduler()
      }

      await store.send(.child(.element(id: 0, action: .tap)))
      await store.send(.child(.element(id: 1, action: .tap)))
      await mainQueue.advance(by: .seconds(1))
      await store.receive(.child(.element(id: 0, action: .response(42)))) {
        $0.children[id: 0]?.count = 42
      }
      await mainQueue.advance(by: .seconds(1))
      await store.receive(.child(.element(id: 1, action: .response(42)))) {
        $0.children[id: 1]?.count = 42
      }
    }

    func testChildEffectCancellation() async {
      struct Child: ReducerProtocol {
        struct State: Equatable { }
        enum Action: Equatable { case tap }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          .run { _ in try await Task.never() }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var children: StackState<Child.State>
        }
        enum Action: Equatable {
          case child(StackAction<Child.State, Child.Action>)
        }
        var body: some ReducerProtocolOf<Self> {
          Reduce { _, _ in .none }
          .forEach(\.children, action: /Action.child) { Child() }
        }
      }

      let store = TestStore(
        initialState: Parent.State(
          children: StackState().appending(contentsOf: [
            Child.State(),
          ])
        ),
        reducer: Parent()
      )

      await store.send(.child(.element(id: 0, action: .tap)))
      await store.send(.child(.popFrom(id: 0))) {
        $0.children[id: 0] = nil
      }
    }

    func testPushPop() async {
      struct Child: ReducerProtocol {
        struct State: Equatable { }
        enum Action: Equatable { case tap }
        func reduce(into state: inout State, action: Action) -> EffectTask<Action> {
          .run { _ in try await Task.never() }
        }
      }
      struct Parent: ReducerProtocol {
        struct State: Equatable {
          var children = StackState<Child.State>()
        }
        enum Action: Equatable {
          case child(StackAction<Child.State, Child.Action>)
          case push
        }
        var body: some ReducerProtocolOf<Self> {
          Reduce { state, action in
            switch action {
            case .child:
              return .none
            case .push:
              state.children.append(Child.State())
              return .none
            }
          }
            .forEach(\.children, action: /Action.child) { Child() }
        }
      }

      let store = TestStore(
        initialState: Parent.State(),
        reducer: Parent()
      )

      await store.send(.child(.push(id: 0, state: Child.State()))) {
        $0.children[id: 0] = Child.State()
      }
      await store.send(.push) {
        $0.children[id: 1] = Child.State()
      }
      await store.send(.child(.push(id: 2, state: Child.State()))) {
        $0.children[id: 2] = Child.State()
      }
      await store.send(.push) {
        $0.children[id: 3] = Child.State()
      }
      await store.send(.child(.popFrom(id: 0))) {
        $0.children = StackState()
      }
      await store.send(.child(.push(id: 0, state: Child.State()))) {
        $0.children[id: 0] = Child.State()
      }
    }
  }
#endif
