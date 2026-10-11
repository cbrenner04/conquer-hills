import SwiftUI
import WorkoutKit

/// "How'd it go?": five stars and notes to self. Used on the summary and in a saved run's detail.
struct RunReflectionEditor: View {
    @Binding var rating: Int?
    @Binding var notes: String
    @FocusState private var notesFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How'd it go?")
                    .font(.headline)
                Spacer()
                if notesFocused {
                    Button("Done") { notesFocused = false }
                        .accessibilityIdentifier("reflection-done")
                }
            }
            HStack(spacing: 10) {
                ForEach(RunHistoryEntry.ratingRange, id: \.self) { star in
                    Button {
                        // Tapping the current rating again clears it.
                        rating = rating == star ? nil : star
                    } label: {
                        Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                            .font(.system(size: 34))
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("star-\(star)")
                    .accessibilityLabel("\(star) \(star == 1 ? "star" : "stars")")
                    .accessibilityAddTraits(star == rating ? .isSelected : [])
                }
            }
            TextField("Notes to self (optional)", text: $notes, axis: .vertical)
                .lineLimit(3...8)
                .focused($notesFocused)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.2)))
                .accessibilityIdentifier("reflection-notes")
        }
    }
}

/// A saved run's rating as small stars, with a note icon when it has notes. Empty when it has neither.
struct RunReflectionBadge: View {
    let entry: RunHistoryEntry

    var body: some View {
        HStack(spacing: 6) {
            if let rating = entry.rating {
                HStack(spacing: 1) {
                    ForEach(RunHistoryEntry.ratingRange, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                    }
                }
                .foregroundStyle(.yellow)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(rating) of 5 stars")
            }
            if entry.notes != nil {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Has notes")
            }
        }
        .font(.caption)
    }
}
