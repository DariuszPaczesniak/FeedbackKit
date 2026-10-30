#if os(iOS)
import SwiftUI

/// Which checklist items `FeedbackView` shows.
enum ChecklistFilter: String, CaseIterable, Identifiable {
    case all
    case notRun
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .notRun: return "Not run"
        case .failed: return "Failed"
        }
    }

    func includes(_ entry: TestScenarioResult?) -> Bool {
        switch self {
        case .all: return true
        case .notRun: return entry == nil
        case .failed: return entry?.result == .fail
        }
    }
}

/// One checklist item: title/detail, a status badge, Pass/Fail/Skip/Blocked
/// buttons (tapping the selected one resets the item to "not run"), and --
/// once the item has a result -- an inline notes field.
///
/// Stateless: reads the item's current result and reports taps/edits back
/// through closures, so `FeedbackView` stays the single owner of the
/// session (and of saving it).
struct ChecklistItemRow: View {
    let item: TestChecklistItem
    let entry: TestScenarioResult?
    let onSelect: (TestResult) -> Void
    let onReset: () -> Void
    let notes: Binding<String>

    private static let results: [TestResult] = [.pass, .fail, .skip, .blocked]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry?.result.statusTitle ?? "Not run")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(entry == nil ? .secondary : entry!.result.tint)
                    .accessibilityLabel("Status: \(entry?.result.statusTitle ?? "Not run")")
                    .accessibilityIdentifier("feedbackkit.checklist.item.\(item.id).status")
            }

            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            // Four buttons side by side when they fit; stacked at large
            // Dynamic Type sizes rather than truncating their labels.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { resultButtons }
                VStack(alignment: .leading, spacing: 8) { resultButtons }
            }

            if entry != nil {
                TextField("Notes (optional)", text: notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Notes for \(item.title)")
                    .accessibilityIdentifier("feedbackkit.checklist.item.\(item.id).notes")
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var resultButtons: some View {
        ForEach(Self.results, id: \.self) { result in
            resultButton(result)
        }
    }

    @ViewBuilder
    private func resultButton(_ result: TestResult) -> some View {
        let isSelected = entry?.result == result
        let button = Button {
            if isSelected { onReset() } else { onSelect(result) }
        } label: {
            Text(result.buttonTitle)
                .lineLimit(1)
        }
        .tint(result.tint)
        .accessibilityLabel(result.buttonTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Resets \(item.title) to not run" : "Marks \(item.title) as \(result.statusTitle.lowercased())")
        .accessibilityIdentifier("feedbackkit.checklist.item.\(item.id).\(result.rawValue.lowercased())")

        if isSelected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

extension TestResult {
    var buttonTitle: String {
        switch self {
        case .pass: return "Pass"
        case .fail: return "Fail"
        case .skip: return "Skip"
        case .blocked: return "Blocked"
        }
    }

    var statusTitle: String {
        switch self {
        case .pass: return "Passed"
        case .fail: return "Failed"
        case .skip: return "Skipped"
        case .blocked: return "Blocked"
        }
    }

    /// System colors, so they adapt to dark mode and Increase Contrast.
    var tint: Color {
        switch self {
        case .pass: return .green
        case .fail: return .red
        case .skip: return .orange
        case .blocked: return .purple
        }
    }
}
#endif
