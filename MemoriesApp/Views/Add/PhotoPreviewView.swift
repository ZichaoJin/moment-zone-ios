//
//  PhotoPreviewView.swift
//  MemoriesApp
//

import SwiftUI

struct PhotoPreviewView: View {
    let photoIds: [String]
    @Binding var selectedIds: [String]
    var onDelete: ((String) -> Void)?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(photoIds, id: \.self) { localId in
                    PhotoPreviewItem(
                        localIdentifier: localId,
                        isSelected: selectedIds.contains(localId)
                    ) {
                        onDelete?(localId)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct PhotoPreviewItem: View {
    let localIdentifier: String
    let isSelected: Bool
    var onDelete: () -> Void
    
    @State private var image: UIImage?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                        }
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white)
                    .background {
                        Circle()
                            .fill(.black.opacity(0.5))
                    }
                    .font(.title3)
            }
            .offset(x: 4, y: -4)
        }
        .onAppear {
            PhotoService.loadThumbnail(localIdentifier: localIdentifier, targetSize: CGSize(width: 160, height: 160)) { img in
                image = img
            }
        }
    }
}

#Preview {
    PhotoPreviewView(photoIds: [], selectedIds: .constant([]))
}
