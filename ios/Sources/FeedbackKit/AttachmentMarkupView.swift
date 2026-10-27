#if os(iOS)
import SwiftUI
import PencilKit

/// Freehand markup editor for a single `FeedbackAttachment`: shows the
/// attachment's original image as a static background with a transparent
/// `PKCanvasView` on top for drawing. "Done" flattens the drawing onto the
/// original image and writes the composite back into `attachment.markup`.
/// "Clear" resets the canvas without discarding a previously-saved markup
/// until Done is tapped again.
struct AttachmentMarkupView: View {
    @Binding var attachment: FeedbackAttachment
    @Environment(\.dismiss) private var dismiss

    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Image(uiImage: attachment.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    CanvasRepresentable(canvasView: $canvasView, toolPicker: toolPicker)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .background(Color.black.opacity(0.05))
            .navigationTitle("Markup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        canvasView.drawing = PKDrawing()
                    }
                    .accessibilityIdentifier("feedbackkit.markupClearButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        flattenAndSave()
                        dismiss()
                    }
                    .accessibilityIdentifier("feedbackkit.markupDoneButton")
                }
            }
            .onAppear {
                // Restore any existing drawing wasn't persisted separately from the
                // flattened image, so there's nothing to re-load here -- the canvas
                // always starts blank over the (possibly already-marked-up) image.
                toolPicker.setVisible(true, forFirstResponder: canvasView)
                toolPicker.addObserver(canvasView)
                canvasView.becomeFirstResponder()
            }
        }
    }

    private func flattenAndSave() {
        let bounds = canvasView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            return format
        }())

        let composite = renderer.image { _ in
            // Mirror the `.scaledToFit()` layout used on screen so the saved
            // composite matches what the user actually drew on -- drawing the
            // original stretched to fill `bounds` would distort any image
            // whose aspect ratio doesn't match the canvas and misalign markup.
            let imageSize = attachment.original.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            let fitScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            let fittedSize = CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)
            let origin = CGPoint(x: (bounds.width - fittedSize.width) / 2, y: (bounds.height - fittedSize.height) / 2)

            attachment.original.draw(in: CGRect(origin: origin, size: fittedSize))
            let drawingImage = canvasView.drawing.image(from: bounds, scale: scale)
            drawingImage.draw(in: CGRect(origin: .zero, size: bounds.size))
        }

        attachment.markup = composite
    }
}

/// `UIViewRepresentable` wrapper around a transparent `PKCanvasView` used
/// purely for freehand drawing input; the tool picker is managed by the
/// presenting view (`AttachmentMarkupView`).
private struct CanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let toolPicker: PKToolPicker

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
#endif
