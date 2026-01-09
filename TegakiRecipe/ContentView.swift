import SwiftUI
import PhotosUI

struct Recipe: Identifiable {
    let id = UUID()
    let imageName: String
    let ingredientsText: String
}



struct ContentView: View {
    @State private var recipes: [Recipe] = [
        Recipe(imageName: "pasta", ingredientsText: "Pasta, Eggs, Bacon, Parmesan, Black Pepper"),
        Recipe(imageName: "brownie", ingredientsText: "Flour, Sugar, Cocoa, Eggs, Butter, Vanilla")
    ]

    @State private var showAddRecipe = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(recipes) { recipe in
                        RecipeCard(
                            recipe: recipe,
                            onDelete: { delete(recipe) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddRecipe = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.blue))
                    }
                }
            }
            .sheet(isPresented: $showAddRecipe) {
                AddRecipeSheet()
            }
        }
    }

    private func delete(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
    }
    
}




struct RecipeCard: View {
    let recipe: Recipe
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(recipe.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(recipe.ingredientsText)
                .font(.system(size: 15))
                .foregroundStyle(Color(.label))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.systemGray6))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
        )
    }
}


import SwiftUI
import PhotosUI

struct AddRecipeSheet: View {
    @Environment(\.dismiss) var dismiss

    @State var ingredientsText = ""
    @State var selectedImages: [UIImage] = []
    @State var photoItems: [PhotosPickerItem] = []
    @State var showPhotoPicker = false
    @State var showCamera = false

    @State var isUploading = false
    @State var isPolling = false
    @State var uploadError: String?
    @State var resultText: String?
    @State var jobId: String?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Add Recipe")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                UploadOption(icon: "photo", title: "Choose Photos")
                    .onTapGesture { showPhotoPicker = true }

                UploadOption(icon: "camera", title: "Take Photo")
                    .onTapGesture { showCamera = true }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $photoItems,
                matching: .images
            )
            .onChange(of: photoItems) { newItems in
                loadImages(from: newItems)
            }
            .sheet(isPresented: $showCamera) {
                CameraCaptureView(images: $selectedImages)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Ingredients")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                TextEditor(text: $ingredientsText)
                    .frame(height: 90)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), style: .init(lineWidth: 1, dash: [6]))
                    )
            }

            if let err = uploadError {
                Text(err).foregroundStyle(.red).font(.system(size: 13))
            }
            if let jid = jobId {
                Text("job_id: \(jid)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let res = resultText {
                ScrollView {
                    Text(res).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxHeight: 120)
            }

            Spacer()

            Button {
                Task { await uploadRecipeAndPoll() }
            } label: {
                Text(isUploading || isPolling ? "Working..." : "Upload Recipe")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background((isUploading || isPolling) ? Color(.systemGray4) : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedImages.isEmpty || isUploading || isPolling)
        }
        .padding(16)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    func uploadRecipeAndPoll() async {
        uploadError = nil
        resultText = nil
        jobId = nil

        do {
            let jid = try await uploadRecipe()
            jobId = jid
            await pollJob(jobId: jid)
        } catch {
            uploadError = error.localizedDescription
        }
    }

    func uploadRecipe() async throws -> String {
        isUploading = true
        defer { isUploading = false }

        guard !selectedImages.isEmpty else { throw URLError(.badURL) }

        // ✅ ここを自分のサーバURLに（/jobs が正しい）
        let base = "http://127.0.0.1:8000"
        guard let url = URL(string: "\(base)/jobs") else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let recipeName = "temp_recipe" // TextField作るまで仮

        let body = try makeMultipartBody(
            boundary: boundary,
            recipeName: recipeName,
            images: selectedImages
        )
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(JobStatus.self, from: data)
        return decoded.job_id
    }

    func pollJob(jobId: String) async {
        isPolling = true
        defer { isPolling = false }

        let base = "http://127.0.0.1:8000"
        guard let url = URL(string: "\(base)/jobs/\(jobId)") else { return }

        let deadline = Date().addingTimeInterval(60)
        let intervalNs: UInt64 = 1_000_000_000

        while Date() < deadline {
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.setValue("application/json", forHTTPHeaderField: "Accept")

                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    uploadError = "GET failed"
                    return
                }

                if let status = try? JSONDecoder().decode(JobStatus.self, from: data),
                   status.status != "done" {
                    try await Task.sleep(nanoseconds: intervalNs)
                    continue
                }

                resultText = String(data: data, encoding: .utf8)
                return

            } catch {
                uploadError = error.localizedDescription
                return
            }
        }

        uploadError = "Timed out waiting for result"
    }

    func makeMultipartBody(boundary: String, recipeName: String, images: [UIImage]) throws -> Data {
        var body = Data()

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"recipe_name\"\r\n\r\n")
        body.appendString("\(recipeName)\r\n")

        for (idx, img) in images.enumerated() {
            guard let jpeg = img.jpegData(compressionQuality: 0.9) else { continue }

            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"files\"; filename=\"photo\(idx).jpg\"\r\n")
            body.appendString("Content-Type: image/jpeg\r\n\r\n")
            body.append(jpeg)
            body.appendString("\r\n")
        }

        body.appendString("--\(boundary)--\r\n")
        return body
    }

    func loadImages(from items: [PhotosPickerItem]) {
        for item in items {
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImages.append(image)
                }
            }
        }
    }
}

struct JobStatus: Decodable {
    let job_id: String
    let status: String
}

extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}

struct UploadOption: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.systemGray4), style: .init(lineWidth: 1, dash: [6]))
        )
    }
}

struct CameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var images: [UIImage]
    @State private var currentImage: UIImage?

    var body: some View {
        VStack {
            CameraView(image: $currentImage)

            HStack {
                Button("Cancel") { dismiss() }

                Spacer()

                Button("Use Photo") {
                    if let img = currentImage {
                        images.append(img)
                        currentImage = nil
                    }
                }

                Button("Done") { dismiss() }
            }
            .padding()
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
        }
    }
}



#Preview {
    ContentView()
}
