import ComposableArchitecture
import SwiftUI

struct StandupDetail: Reducer {
  @ObservableState
  struct State: Equatable {
    @ObservationStateIgnored
    @PresentationState var destination: Destination.State?
    var standup: Standup

    init(destination: Destination.State? = nil, standup: Standup) {
      self.destination = destination
      self.standup = standup
    }
  }
  @CasePathable
  enum Action: Equatable, Sendable {
    case cancelEditButtonTapped
    case delegate(Delegate)
    case deleteButtonTapped
    case deleteMeetings(atOffsets: IndexSet)
    case destination(PresentationAction<Destination.Action>)
    case doneEditingButtonTapped
    case editButtonTapped
    case startMeetingButtonTapped

    enum Delegate: Equatable {
      case deleteStandup
      case standupUpdated(Standup)
      case startMeeting
    }
  }

  @Dependency(\.dismiss) var dismiss
  @Dependency(\.openSettings) var openSettings
  @Dependency(\.speechClient.authorizationStatus) var authorizationStatus

  struct Destination: Reducer {
    @CasePathable
    @ObservableState
    enum State: Equatable {
      case alert(AlertState<Action.Alert>)
      case edit(StandupForm.State)
    }
    @CasePathable
    enum Action: Equatable, Sendable {
      case alert(Alert)
      case edit(StandupForm.Action)

      enum Alert {
        case confirmDeletion
        case continueWithoutRecording
        case openSettings
      }
    }
    var body: some ReducerOf<Self> {
      Scope(state: #casePath(\.edit), action: #casePath(\.edit)) {
        StandupForm()
      }
    }
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .cancelEditButtonTapped:
        state.destination = nil
        return .none

      case .delegate:
        return .none

      case .deleteButtonTapped:
        state.destination = .alert(.deleteStandup)
        return .none

      case let .deleteMeetings(atOffsets: indices):
        state.standup.meetings.remove(atOffsets: indices)
        return .none

      case let .destination(.presented(.alert(alertAction))):
        switch alertAction {
        case .confirmDeletion:
          return .run { send in
            await send(.delegate(.deleteStandup), animation: .default)
            await self.dismiss()
          }
        case .continueWithoutRecording:
          return .send(.delegate(.startMeeting))
        case .openSettings:
          return .run { _ in
            await self.openSettings()
          }
        }

      case .destination:
        return .none

      case .doneEditingButtonTapped:
        guard case let .some(.edit(editState)) = state.destination
        else { return .none }
        state.standup = editState.standup
        state.destination = nil
        return .none

      case .editButtonTapped:
        state.destination = .edit(StandupForm.State(standup: state.standup))
        return .none

      case .startMeetingButtonTapped:
        switch self.authorizationStatus() {
        case .notDetermined, .authorized:
          return .send(.delegate(.startMeeting))

        case .denied:
          state.destination = .alert(.speechRecognitionDenied)
          return .none

        case .restricted:
          state.destination = .alert(.speechRecognitionRestricted)
          return .none

        @unknown default:
          return .none
        }
      }
    }
    .ifLet(\.$destination, action: #casePath(\.destination)) {
      Destination()
    }
    .onChange(of: \.standup) { oldValue, newValue in
      Reduce { state, action in
        .send(.delegate(.standupUpdated(newValue)))
      }
    }
  }
}

struct StandupDetailView: View {
  @State var store: StoreOf<StandupDetail>

  var body: some View {
    List {
      Section {
        Button {
          self.store.send(.startMeetingButtonTapped)
        } label: {
          Label("Start Meeting", systemImage: "timer")
            .font(.headline)
            .foregroundColor(.accentColor)
        }
        HStack {
          Label("Length", systemImage: "clock")
          Spacer()
          Text(self.store.standup.duration.formatted(.units()))
        }

        HStack {
          Label("Theme", systemImage: "paintpalette")
          Spacer()
          Text(self.store.standup.theme.name)
            .padding(4)
            .foregroundColor(self.store.standup.theme.accentColor)
            .background(self.store.standup.theme.mainColor)
            .cornerRadius(4)
        }
      } header: {
        Text("Standup Info")
      }

      if !self.store.standup.meetings.isEmpty {
        Section {
          ForEach(self.store.standup.meetings) { meeting in
            NavigationLink(
              state: AppFeature.Path.State.meeting(meeting, standup: self.store.standup)
            ) {
              HStack {
                Image(systemName: "calendar")
                Text(meeting.date, style: .date)
                Text(meeting.date, style: .time)
              }
            }
          }
          .onDelete { indices in
            self.store.send(.deleteMeetings(atOffsets: indices))
          }
        } header: {
          Text("Past meetings")
        }
      }

      Section {
        ForEach(self.store.standup.attendees) { attendee in
          Label(attendee.name, systemImage: "person")
        }
      } header: {
        Text("Attendees")
      }

      Section {
        Button("Delete") {
          self.store.send(.deleteButtonTapped)
        }
        .foregroundColor(.red)
        .frame(maxWidth: .infinity)
      }
    }
    .navigationTitle(self.store.standup.title)
    .toolbar {
      Button("Edit") {
        self.store.send(.editButtonTapped)
      }
    }
    .alert(
      store: self.store.scope(state: \.$destination, action: { .destination($0) }),
      state: /StandupDetail.Destination.State.alert,
      action: StandupDetail.Destination.Action.alert
    )
//    .sheet(
//      store: self.store.scope(state: \.$destination, action: { .destination($0) }),
//      state: /StandupDetail.Destination.State.edit,
//      action: StandupDetail.Destination.Action.edit
//    ) { store in
//      NavigationStack {
//        StandupFormView(store: store)
//          .navigationTitle(self.store.standup.title)
//          .toolbar {
//            ToolbarItem(placement: .cancellationAction) {
//              Button("Cancel") {
//                self.store.send(.cancelEditButtonTapped)
//              }
//            }
//            ToolbarItem(placement: .confirmationAction) {
//              Button("Done") {
//                self.store.send(.doneEditingButtonTapped)
//              }
//            }
//          }
//      }
//    }

//    .sheet(
//      item: self.$store.scope(
//        state: \.destination?.edit,
//        action: { .destination($0.map { .edit($0) }) }
//      )
//    )

    // self.store.scope(#feature(\.edit))
    // self.store.scope(#feature(\.destination?.edit))

    .sheet(
      // item: self.$store.scope(#feature(\.destination?.edit))
      item: self.$store.scope(
        state: \.destination?.edit,
        action: { .destination($0.presented { .edit($0) }) }
        // action: #presentationAction(\.destination?.presented?.edit)
        // destination: { .destination($0) }, action: { .edit($0) }
      )
    ) { store in
      NavigationStack {
        StandupFormView(store: store)
          .navigationTitle(self.store.standup.title)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Cancel") {
                self.store.send(.cancelEditButtonTapped)
              }
            }
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") {
                self.store.send(.doneEditingButtonTapped)
              }
            }
          }
      }
    }
  }
}

extension PresentationAction {
  func presenting<NewAction>(
    _ transform: (Action) -> NewAction
  ) -> PresentationAction<NewAction> {
    switch self {
    case .dismiss:
      return .dismiss
    case let .presented(action):
      return .presented(transform(action))
    }
  }

  func map<NewAction>(
    _ transform: (Action) -> NewAction
  ) -> PresentationAction<NewAction> {
    switch self {
    case .dismiss:
      return .dismiss
    case let .presented(action):
      return .presented(transform(action))
    }
  }
}

extension View {
  @available(*, deprecated)
  public func sheet<
    State: ObservableState, Action, DestinationState, DestinationAction, Content: View
  >(
    store: Store<PresentationState<State>, PresentationAction<Action>>,
    state toDestinationState: @escaping (_ state: State) -> DestinationState?,
    action fromDestinationAction: @escaping (_ destinationAction: DestinationAction) -> Action,
    onDismiss: (() -> Void)? = nil,
    @ViewBuilder content: @escaping (_ store: Store<DestinationState, DestinationAction>) -> Content
  ) -> some View {
    self
  }
}

extension AlertState where Action == StandupDetail.Destination.Action.Alert {
  static let deleteStandup = Self {
    TextState("Delete?")
  } actions: {
    ButtonState(role: .destructive, action: .confirmDeletion) {
      TextState("Yes")
    }
    ButtonState(role: .cancel) {
      TextState("Nevermind")
    }
  } message: {
    TextState("Are you sure you want to delete this meeting?")
  }

  static let speechRecognitionDenied = Self {
    TextState("Speech recognition denied")
  } actions: {
    ButtonState(action: .continueWithoutRecording) {
      TextState("Continue without recording")
    }
    ButtonState(action: .openSettings) {
      TextState("Open settings")
    }
    ButtonState(role: .cancel) {
      TextState("Cancel")
    }
  } message: {
    TextState(
      """
      You previously denied speech recognition and so your meeting meeting will not be \
      recorded. You can enable speech recognition in settings, or you can continue without \
      recording.
      """
    )
  }

  static let speechRecognitionRestricted = Self {
    TextState("Speech recognition restricted")
  } actions: {
    ButtonState(action: .continueWithoutRecording) {
      TextState("Continue without recording")
    }
    ButtonState(role: .cancel) {
      TextState("Cancel")
    }
  } message: {
    TextState(
      """
      Your device does not support speech recognition and so your meeting will not be recorded.
      """
    )
  }
}

struct StandupDetail_Previews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      StandupDetailView(
        store: Store(initialState: StandupDetail.State(standup: .mock)) {
          StandupDetail()
        }
      )
    }
  }
}
