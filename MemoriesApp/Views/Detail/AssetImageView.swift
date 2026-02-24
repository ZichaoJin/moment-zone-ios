//
//  AssetImageView.swift
//  MemoriesApp
//

import SwiftUI
import UIKit

struct AssetImageView: View {
    let localIdentifier: String
    let targetSize: CGSize
    let adaptive: Bool

    @State private var image: UIImage?
    @State private var requestToken: String = ""

    init(localIdentifier: String, size: CGSize = CGSize(width: 400, height: 400), adaptive: Bool = false) {
        self.localIdentifier = localIdentifier
        self.targetSize = size
        self.adaptive = adaptive
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: adaptive ? .fit : .fill)
            } else {
                Rectangle()
                    .fill(.gray.opacity(0.2))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .modifier(AssetFrameModifier(adaptive: adaptive, size: targetSize))
        .clipped()
        .onAppear {
            loadImage()
        }
        .onChange(of: localIdentifier) { _, _ in
            loadImage()
        }
        .onChange(of: targetSize) { _, _ in
            loadImage()
        }
    }

    private func loadImage() {
        let token = "\(localIdentifier)_\(Int(targetSize.width))x\(Int(targetSize.height))"
        requestToken = token
        PhotoService.loadThumbnail(localIdentifier: localIdentifier, targetSize: targetSize) { img in
            guard requestToken == token else { return }
            if let img {
                image = img
            }
        }
    }
}

private struct AssetFrameModifier: ViewModifier {
    let adaptive: Bool
    let size: CGSize
    func body(content: Content) -> some View {
        if adaptive {
            content.frame(maxWidth: .infinity)
        } else {
            content.frame(width: size.width, height: size.height)
        }
    }
}

#Preview {
    AssetImageView(localIdentifier: "")
        .frame(width: 200, height: 200)
}
