import Foundation

struct SyncUp: Equatable, Identifiable, Codable {
  let id: UUID
  var attendees: [Attendee] = []
  var duration: Duration = .seconds(60 * 5)
  var meetings: [Meeting] = []
  var theme: Theme = .bubblegum
  var title = ""
}

struct Attendee: Equatable, Identifiable, Codable {
  let id: UUID
  var name = ""
}

struct Meeting: Equatable, Identifiable, Codable {
  let id: UUID
  let date: Date
  var transcript: String
}

enum Theme: String, CaseIterable, Equatable, Identifiable, Codable {
  var id: Self { self }
  
  case bubblegum
  case buttercup
  case indigo
  case lavender
  case magenta
  case navy
  case orange
  case oxblood
  case periwinkle
  case poppy
  case purple
  case seafoam
  case sky
  case tan
  case teal
  case yellow
}