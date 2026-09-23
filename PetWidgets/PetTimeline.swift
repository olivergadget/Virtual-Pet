import SwiftUI
import WidgetKit

/// One moment in the pet's day, read from the same save file the app looks after.
struct PetEntry: TimelineEntry {
    let date: Date
    /// `nil` until somebody adopts a pet.
    let pet: Pet?

    /// Needs drift whether or not anyone is looking, so the widget runs the app's own
    /// simulation forward to the moment this entry will be shown.
    init(date: Date, pet: Pet?) {
        self.date = date
        self.pet = pet.map {
            var aged = $0
            aged.advance(to: date)
            return aged
        }
    }
}

struct PetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry {
        PetEntry(date: .now, pet: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        // In the gallery there may be no pet yet, and an empty widget sells nothing.
        let pet = context.isPreview ? .sample : PetArchive.load()
        completion(PetEntry(date: .now, pet: pet))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        let pet = PetArchive.load()
        let now = Date.now
        // Idle drift is slow and entirely predictable, so the next few hours can be
        // drawn up front. Anything the person actually does reloads the timeline from
        // the app the moment it is saved.
        let entries = stride(from: 0, through: Self.lookAhead, by: Self.step).map {
            PetEntry(date: now.addingTimeInterval($0), pet: pet)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static let step: TimeInterval = 20 * 60
    private static let lookAhead: TimeInterval = 4 * 60 * 60
}

extension Pet {
    /// A stand-in pet for the widget gallery and the redacted placeholder: a few days
    /// old, well loved, and just about ready for dinner.
    static var sample: Pet {
        var pet = Pet(name: "Mochi", kind: .cat)
        pet.bornAt = .now.addingTimeInterval(-6 * 86_400)
        pet.bondPoints = 220
        pet.needs = Needs(fullness: 0.46, fun: 0.72, affection: 0.88, rest: 0.64)
        return pet
    }
}
