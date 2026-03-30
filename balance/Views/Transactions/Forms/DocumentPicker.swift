import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var fileData: Data?
    @Binding var attachmentType: AttachmentType?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            do {
                let data = try Data(contentsOf: url)
                parent.fileData = data
                
                // تشخیص نوع فایل
                if url.pathExtension.lowercased() == "pdf" {
                    parent.attachmentType = .pdf
                } else if ["jpg", "jpeg", "png", "heic"].contains(url.pathExtension.lowercased()) {
                    parent.attachmentType = .image
                } else {
                    parent.attachmentType = .other
                }
            } catch {
                SecureLogger.error("Error reading file", error)
            }
            
            parent.dismiss()
        }
    }
}
