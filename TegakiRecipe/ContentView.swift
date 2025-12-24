//
//  ContentView.swift
//  TegakiRecipe
//
//  Created by Kohei Sawabe on 2025-12-11.
//

import PhotosUI
import SwiftUI

struct ContentView: View {
    @State var selectedPhotos: [PhotosPickerItem] = []
    @State var images = [UIImage]()
    var body: some View {
        VStack {
            ScrollView(.horizontal){
                LazyHGrid(rows: [GridItem(.fixed(300))]){
                    ForEach(0..<images.count, id: \.self){
                        index in Image(uiImage: images[index])
                            .resizable()
                            .scaledToFit()
                    }
                }
            }.onChange(of: selectedPhotos){
                convertDataToImage()
            }
            PhotosPicker("Select a photo",
                         selection: $selectedPhotos,
                         maxSelectionCount: 1,
                         selectionBehavior: .ordered,
                         matching: .images
            )
        }
        .padding()
        Button {
            Task {
                await uploadPhotos(selectedPhotos)
            }
        } label: {
            HStack(spacing: 8) {
                Image(uiImage: UIImage(resource: .upload))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text("Upload Recipe")
            }
        }
    }
    func convertDataToImage(){
        images.removeAll()
        
        if !selectedPhotos.isEmpty{
            for eachItem in selectedPhotos{
                Task{
                    if let imageData = try? await
                        eachItem.loadTransferable(type: Data.self) {
                        if let image = UIImage(data: imageData){
                            images.append(image)
                        }
                    }
                }
            }
        }
    }
    func uploadPhotos(_ items: [PhotosPickerItem]) async{
        
    }
}


#Preview {
    ContentView()
}
