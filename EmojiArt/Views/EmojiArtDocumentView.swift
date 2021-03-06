//
//  EmojiArtDocumentView.swift
//  EmojiArt
//
//  Created by CS193p Instructor on 4/26/21.
//  Copyright Β© 2021 Stanford University. All rights reserved.
//

import SwiftUI

struct EmojiArtDocumentView: View {
    @ObservedObject var document: EmojiArtDocument
    @State private var selectedEmojis = Set<EmojiArtModel.Emoji>()
    @GestureState private var gestureDragOffset = CGSize.zero
    @State private var steadyStateZoomScale: CGFloat = 1
    @GestureState private var gestureZoomScale: CGFloat = 1
    @State private var steadyStatePanOffset: CGSize = CGSize.zero
    @GestureState private var gesturePanOffset: CGSize = CGSize.zero
    
    private let testEmojis = "ππ·π¦ ππ»ππΆπ²πππ₯πβ½οΈπππ²π©πππΈπ βοΈπππβ€οΈβοΈββββ οΈπΆββπ³οΈ"
    private let defaultEmojiFontSize: CGFloat = 40
    
    private var panOffset: CGSize {
        (steadyStatePanOffset + gesturePanOffset) * zoomScale
    }
    private var zoomScale: CGFloat {
        steadyStateZoomScale * gestureZoomScale
    }
    private var documentBody: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.overlay(
                    OptionalImage(uiImage: document.backgroundImage)
                        .scaleEffect(zoomScale)
                        .position(convertFromEmojiCoordinates((0,0), in: geometry))
                )
                .gesture(doubleTapToZoom(in: geometry.size))
                if document.backgroundImageFetchStatus == .fetching {
                    ProgressView().scaleEffect(2)
                } else {
                    ForEach(document.emojiArt.emojis) { emoji in
                        Text(emoji.text)
                            .background(selectedEmojis.contains(emoji) ? Color.yellow : nil)
                            .font(.system(size: fontSize(for: emoji)))
                            .scaleEffect(zoomScale)
                            .position(position(for: emoji, in: geometry))
                            .gesture(oneTapSelection(emoji: emoji).exclusively(before: longPressGesture(emoji)))
                            .gesture(dragEmojiGesture(emoji: emoji))

                    }
                }
            }
            .clipped()
            .onDrop(of: [.plainText,.url,.image], isTargeted: nil) { providers, location in
                drop(providers: providers, at: location, in: geometry)
            }
            .gesture(panGesture().simultaneously(with: zoomGesture()))
            .onTapGesture{
                selectedEmojis.removeAll()
            }
        }
    }
    
    private var palette: some View {
        ScrollingEmojisView(emojis: testEmojis)
            .font(.system(size: defaultEmojiFontSize))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            documentBody
            palette
        }
    }
    
    
    // MARK: - Selection
    
    private func oneTapSelection(emoji: EmojiArtModel.Emoji ) -> some Gesture {
        TapGesture(count: 1)
            .onEnded {
                selectedEmojis.toggleMatching(item: emoji)
                print(selectedEmojis)
            }
    }
    
    // MARK: - Drag Emoji

    private func dragEmojiGesture(emoji: EmojiArtModel.Emoji ) -> some Gesture {
        DragGesture()
            .updating($gestureDragOffset) { latestValue , gestureDragOffset, _ in
                gestureDragOffset = latestValue.translation / zoomScale
            }
            .onEnded{ latestValue in
                let dragTraslation = latestValue.translation / zoomScale
                
                if selectedEmojis.contains(emoji) {
                    selectedEmojis.forEach { emojiSelected in
                        document.moveEmoji(emojiSelected, by: dragTraslation)
                    }
                }
            }
    }
    
    // MARK: - Delete Emoji
    
    private func longPressGesture(_ emoji: EmojiArtModel.Emoji) -> some Gesture {
        LongPressGesture(minimumDuration: 1)
            .onEnded { finished in
                selectedEmojis.contains(emoji) ? selectedEmojis.toggleMembership(of: emoji) : nil
                document.deleteEmoji(emoji)
            }
    }
    
    // MARK: - Drag and Drop
    
    private func drop(providers: [NSItemProvider], at location: CGPoint, in geometry: GeometryProxy) -> Bool {
        var found = providers.loadObjects(ofType: URL.self) { url in
            document.setBackground(.url(url.imageURL))
        }
        if !found {
            found = providers.loadObjects(ofType: UIImage.self) { image in
                if let data = image.jpegData(compressionQuality: 1.0) {
                    document.setBackground(.imageData(data))
                }
            }
        }
        if !found {
            found = providers.loadObjects(ofType: String.self) { string in
                if let emoji = string.first, emoji.isEmoji {
                    document.addEmoji(
                        String(emoji),
                        at: convertToEmojiCoordinates(location, in: geometry),
                        size: defaultEmojiFontSize / zoomScale
                    )
                }
            }
        }
        return found
    }
    
    // MARK: - Positioning/Sizing Emoji
    
    private func position(for emoji: EmojiArtModel.Emoji, in geometry: GeometryProxy) -> CGPoint {
        
        if selectedEmojis.contains(emoji) {
            return convertFromEmojiCoordinates((emoji.x + Int(gestureDragOffset.width), emoji.y + Int(gestureDragOffset.height)), in: geometry)
        } else {
            return convertFromEmojiCoordinates((emoji.x, emoji.y), in: geometry)
        }
    }
    
    private func fontSize(for emoji: EmojiArtModel.Emoji) -> CGFloat {
        CGFloat(emoji.size)
    }
    
    private func convertToEmojiCoordinates(_ location: CGPoint, in geometry: GeometryProxy) -> (x: Int, y: Int) {
        let center = geometry.frame(in: .local).center
        let location = CGPoint(
            x: (location.x - panOffset.width - center.x) / zoomScale,
            y: (location.y - panOffset.height - center.y) / zoomScale
        )
        return (Int(location.x), Int(location.y))
    }
    
    private func convertFromEmojiCoordinates(_ location: (x: Int, y: Int), in geometry: GeometryProxy) -> CGPoint {
        let center = geometry.frame(in: .local).center
        return CGPoint(
            x: center.x + CGFloat(location.x) * zoomScale + panOffset.width,
            y: center.y + CGFloat(location.y) * zoomScale + panOffset.height
        )
    }
    
    // MARK: - Zooming
    

    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .updating($gestureZoomScale) { latestGestureScale, gestureZoomScale, _ in
                if selectedEmojis.isEmpty {
                    gestureZoomScale = latestGestureScale
                } else {
                    for emojiSelected in selectedEmojis {
                        document.scaleEmoji(emojiSelected, by: latestGestureScale / zoomScale)
                    }
                }
            }
            .onEnded { gestureScaleAtEnd in
                if selectedEmojis.isEmpty {
                    steadyStateZoomScale *= gestureScaleAtEnd
                } else {
                    for emojiSelected in selectedEmojis {
                        document.scaleEmoji(emojiSelected, by: gestureScaleAtEnd)
                    }
                }
            }
    }
    
    private func doubleTapToZoom(in size: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation {
                    zoomToFit(document.backgroundImage, in: size)
                }
            }
    }
    
    private func zoomToFit(_ image: UIImage?, in size: CGSize) {
        if let image = image, image.size.width > 0, image.size.height > 0, size.width > 0, size.height > 0  {
            let hZoom = size.width / image.size.width
            let vZoom = size.height / image.size.height
            steadyStatePanOffset = .zero
            steadyStateZoomScale = min(hZoom, vZoom)
        }
    }
    
    // MARK: - Panning
    

    
    private func panGesture() -> some Gesture {
        DragGesture()
            .updating($gesturePanOffset) { latestDragGestureValue, gesturePanOffset, _ in
                gesturePanOffset = latestDragGestureValue.translation / zoomScale
            }
            .onEnded { finalDragGestureValue in
                steadyStatePanOffset = steadyStatePanOffset + (finalDragGestureValue.translation / zoomScale)
            }
    }

}

struct ScrollingEmojisView: View {
    let emojis: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(emojis.map { String($0) }, id: \.self) { emoji in
                    Text(emoji)
                        .onDrag { NSItemProvider(object: emoji as NSString) }
                }
            }
        }
    }
}

//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        EmojiArtDocumentView(document: EmojiArtDocument())
//    }
//}
