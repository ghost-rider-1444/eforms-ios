import PencilKit
import SwiftUI

struct SignaturePad: UIViewRepresentable {
    @Binding var value: String
    let clearToken: Int
    let readOnly: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> SignatureCanvas {
        let view = SignatureCanvas()
        view.canvas.delegate = context.coordinator
        view.canvas.drawingPolicy = .anyInput
        view.canvas.isUserInteractionEnabled = !readOnly
        view.restore(value)
        context.coordinator.lastClearToken = clearToken
        return view
    }

    func updateUIView(_ uiView: SignatureCanvas, context: Context) {
        uiView.canvas.isUserInteractionEnabled = !readOnly
        if context.coordinator.lastClearToken != clearToken {
            context.coordinator.lastClearToken = clearToken
            uiView.clear()
            if !value.isEmpty { DispatchQueue.main.async { value = "" } }
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: SignaturePad
        var lastClearToken = 0
        init(parent: SignaturePad) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !parent.readOnly, let holder = canvasView.superview as? SignatureCanvas,
                  let encoded = holder.encodedPNG() else { return }
            parent.value = encoded
        }
    }
}

final class SignatureCanvas: UIView {
    let image = UIImageView()
    let canvas = PKCanvasView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.borderColor = UIColor(red: 231/255, green: 221/255, blue: 233/255, alpha: 1).cgColor
        layer.borderWidth = 1
        image.contentMode = .scaleAspectFit
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        for view in [image, canvas] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) { nil }

    func restore(_ value: String) {
        guard let comma = value.firstIndex(of: ","),
              let data = Data(base64Encoded: String(value[value.index(after: comma)...])) else { return }
        image.image = UIImage(data: data)
    }

    func clear() {
        image.image = nil
        canvas.drawing = PKDrawing()
    }

    func encodedPNG() -> String? {
        let bounds = self.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 640, height: 220) : self.bounds
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let output = renderer.image { context in
            UIColor.white.setFill()
            context.fill(bounds)
            image.image?.draw(in: bounds)
            canvas.drawing.image(from: bounds, scale: UIScreen.main.scale).draw(in: bounds)
        }
        guard let data = output.pngData() else { return nil }
        return "data:image/png;base64,\(data.base64EncodedString())"
    }
}

