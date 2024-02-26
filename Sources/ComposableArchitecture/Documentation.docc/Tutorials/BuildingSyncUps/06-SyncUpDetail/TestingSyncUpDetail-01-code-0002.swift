import ComposableArchitecture
import SyncUps
import XCTest

class SyncUpDetailTests: XCTestCase {
  func testEdit() async {
    let syncUp = SyncUp(
      id: SyncUp.ID(),
      title: "Point-Free Morning Sync"
    )
    let store = TestStore(initialState: SyncUpDetail.State(syncUp: syncUp)) {
      SyncUpDetail()
    }
  }
}