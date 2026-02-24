//
//  FullScreenPhotoView.swift
//  MemoriesApp
//

import SwiftUI

/// 全屏照片查看器：点击或下滑退出
struct FullScreenPhotoView: View {
    let photo: Photo
    var onDismiss: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            AssetImageView(localIdentifier: photo.assetLocalId, size: CGSize(width: 800, height: 800), adaptive: true)
                .scaleEffect(scale)
                .offset(dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                            let progress = abs(value.translation.height) / 300
                            scale = max(0.7, 1 - progress * 0.3)
                        }
                        .onEnded { value in
                            if abs(value.translation.height) > 120 {
                                onDismiss()
                            } else {
                                withAnimation(.spring(response: 0.3)) {
                                    dragOffset = .zero
                                    scale = 1.0
                                }
                            }
                        }
                )
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
                
                VStack(spacing: 6) {
                    if !photo.displayLocationName.isEmpty {
                        Text(photo.displayLocationName)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Text(photo.timestamp.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.bottom, 40)
            }
        }
        .statusBarHidden()
    }
}
