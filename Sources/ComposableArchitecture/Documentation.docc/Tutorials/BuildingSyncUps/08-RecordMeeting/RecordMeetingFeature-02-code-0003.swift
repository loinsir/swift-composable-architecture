import ComposableArchitecture
import SwiftUI

@Reducer
struct SyncUpDetail {
  @ObservableState
  struct State {
    @Presents var destination: Destination.State?
    @Shared var syncUp: SyncUp
  }

  enum Action {
    case cancelEditButtonTapped
    case deleteButtonTapped
    case destination(PresentationAction<Destination.Action>)
    case doneEditingButtonTapped
    case editButtonTapped
    @CasePathable
    enum Alert {
      case confirmButtonTapped
    }
  }

  @Dependency(\.dismiss) var dismiss

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .destination(.presented(.alert(.confirmButtonTapped))):
        return .run { send in
          await send(.delegate(.deleteSyncUp(id: state.syncUp.id)))
          await dismiss()
        }

      case .destination:
        return .none

      case .cancelEditButtonTapped:
        state.destination = nil
        return .none

      case .deleteButtonTapped:
        state.destination = .alert(.deleteSyncUp)
        return .none

      case .doneEditingButtonTapped:
        guard let editedSyncUp = state.destination?.edit?.syncUp
        else { return .none }
        state.syncUp = editedSyncUp
        state.destination = nil
        return .none

      case .editButtonTapped:
        state.destination = .edit(SyncUpForm.State(syncUp: state.syncUp))
        return .none
      }
    }
    .ifLet(\.$destination, action: \.destination)
  }
}

extension AlertState where Action == SyncUpDetail.Destination.Alert {
  // ...
}

struct SyncUpDetail.Destination {
  // ...
}

struct SyncUpDetailView: View {
  // ...
}
