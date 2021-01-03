//
//  ContentView.swift
//  DuplicatePhotoRemover
//
//  Created by David Gannon on 02/01/2021.
//

import SwiftUI
import Photos

struct ProgressBar: View {
    
    private let value: Int
    private let maxValue: Int
    private let backgroundEnabled: Bool
    private let backgroundColor: Color
    private let foregroundColor: Color
    
    init(
        value: Int,
        maxValue: Int,
        backgroundEnabled: Bool = true,
        backgroundColor: Color = Color.black,
        foregroundColor: Color = Color.green
    ) {
        self.value = value
        self.maxValue = maxValue
        self.backgroundEnabled = backgroundEnabled
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometryReader in

                if self.backgroundEnabled {
                    Capsule().foregroundColor(self.backgroundColor)
                }
                
                Capsule()
                    .frame(
                        width: self.progress(
                            value: self.value,
                            maxValue: self.maxValue,
                            width: geometryReader.size.width
                        )
                    )
                    .foregroundColor(self.foregroundColor)
                    .animation(.easeIn)
            }
        }
    }
    
    private func progress(
        value: Int,
        maxValue: Int,
        width: CGFloat
    ) -> CGFloat {
        let percentage = Double(value) / Double(maxValue)
        return width *  CGFloat(percentage)
    }
    
}

struct DuplicateItem: Identifiable, Equatable {
    
    var id = UUID()
    var image: PHAsset
    
    static func == (lhs: DuplicateItem, rhs: DuplicateItem) -> Bool {
        return lhs.image == rhs.image
    }
    
}

struct ContentView: View {
    
    @State private var currentPhotoIndex: Int = 0
    @State private var photoCount: Int = 1
    
    @State private var running = false
    
    @State private var duplicates: [PHAsset: [DuplicateItem]] = [:]
    @State private var duplicateItems: [DuplicateItem] = []
    
    @State private var selectedDuplicate: PHAsset? = nil
    
    var body: some View {
        
        if self.running {
            
            VStack(spacing: 12.0) {
            
                Button("Stop Duplicate Check") {
                    self.running = false
                }
                
                ProgressBar(
                    value: currentPhotoIndex,
                    maxValue: photoCount,
                    foregroundColor: .green
                ).frame(height: 10)
                
                Text("\(currentPhotoIndex) of \(photoCount)")
                
                Text("Found \(self.duplicateItems.count) Duplicates")
                
                // ensure we fill the rest with empty space!
                Spacer()
                
            }
            .padding()
            
        } else {
            
            VStack(spacing: 12.0) {
                
                Button("Look for duplicates") {
                    self.running = true
                    DispatchQueue.global(qos: .background).async {
                        runDuplicateCheck()
                    }
                }.padding()

                Text("Found \(self.duplicateItems.count) Duplicates")
                
                HStack {
                    
                    List(self.duplicateItems) { duplicate in
                                        
                        HStack {
                            Button(action: {
                                self.selectedDuplicate = duplicate.image
                            }) {
                                getThumnail(asset: duplicate.image)
                            }.buttonStyle(PlainButtonStyle())
                            Button(action: {
                                self.selectedDuplicate = duplicate.image
                            }) {
                                getImageLabel(duplicate: duplicate)
                            }.buttonStyle(PlainButtonStyle())
                        }
                        
                    }
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 138))]) {
                            if (selectedDuplicate != nil) {
                                ForEach(self.duplicates[self.selectedDuplicate!] ?? []) { duplicate in
                                    VStack {
                                        getThumnail(asset: duplicate.image).padding()
                                        getImageLabel(duplicate: duplicate).padding()
                                    }
                                }
                            }
                        }
                    }
                    
                }
                
                // ensure we fill the rest with empty space!
                Spacer()
                
            }
            
        }
            
    }
    
    func getImageLabel(duplicate: DuplicateItem) -> Text {
        
        if (duplicate.image.creationDate == nil) {
            return Text("No Image META")
        }
        
        let RFC3339DateFormatter = DateFormatter()
        RFC3339DateFormatter.locale = Locale(identifier: "en_US_POSIX")
        RFC3339DateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        RFC3339DateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        return Text("\(RFC3339DateFormatter.string(from: duplicate.image.creationDate!))")
        
    }
    
    func getThumnail(asset: PHAsset) -> Image? {
        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        let size = CGSize(width: 138, height: 138)
        option.isSynchronous = true

        var thumbnail: Image? = nil
        option.isSynchronous = true
        manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: option, resultHandler: {(result, info)->Void in
            thumbnail = Image(nsImage: result!)
                .renderingMode(.original)
        })
        
        return thumbnail
    }
        
    // work out if an image is a duplicate!
    func imageIsDuplicate(lhs: PHAsset, rhs: PHAsset) -> Bool {
        // if they have the exact same date, they might be a duplicate!
        // ensure we compare the media subtypes, so that HDR copies aren'tmarked as duplicates
        // check the dimensions of the image as well, just so crops don't appear as duplicates.
        return lhs.creationDate == rhs.creationDate && lhs.mediaSubtypes == rhs.mediaSubtypes &&
            lhs.pixelWidth == rhs.pixelWidth && lhs.pixelHeight == rhs.pixelHeight
    }

    func runDuplicateCheck() {
        
        let allPhotosOptions = PHFetchOptions()
        allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let allPhotos = PHAsset.fetchAssets(with: allPhotosOptions)
        
        // update our max value
        self.photoCount = allPhotos.count
        
        // empty the duplicates list!
        self.duplicates = [:]
        self.duplicateItems = []
        
        allPhotos.enumerateObjects({ (toMatch, matchIndex, stop) in
            
            if (!self.running) {
                print("Stopping inner")
                stop.pointee = true
                return
            }
                                    
            checkSingleImage(matchIndex: matchIndex, toMatch: toMatch, allPhotos: allPhotos)

            self.currentPhotoIndex = matchIndex + 1
            
        })
        
        self.running = false

    }
    
    // if we've aleady found this iamge!
    func imageAlreadyInDuplicates(toMatch: PHAsset) -> Bool {
        
        var alreadyFound = false
        for (duplicate, _) in self.duplicates {
            if imageIsDuplicate(lhs: toMatch, rhs: duplicate) {
                alreadyFound = true
                break
            }
        }
        
        return alreadyFound
        
    }
    
    // the image reverse is alredy in the duplicates!
    func imageReverseAlreadyInDuplicates(toCompare: PHAsset, toMatch: PHAsset) -> Bool {
        
        // if we've already got the to match image in here, and the opposite duplicate, continue!
        var alreadyFound = false
        if (self.duplicates.keys.contains(toCompare)) {
            self.duplicates[toCompare]!.forEach( { duplicate in
                if imageIsDuplicate(lhs: toMatch, rhs: duplicate.image) {
                    alreadyFound = true
                }
            })
        }
        
        return alreadyFound
        
    }
    
    // check a single image!
    func checkSingleImage(matchIndex: Int, toMatch: PHAsset, allPhotos: PHFetchResult<PHAsset>) {
        
        // if the image is aleady in the duplicates!
        if imageAlreadyInDuplicates(toMatch: toMatch) {
            return
        }
        
        // go through each of the photos
        allPhotos.enumerateObjects({ (toCompare, compareIndex, stop) in
            
            // if we've stopped already!
            if (!self.running) {
                print("Stopping outer")
                stop.pointee = true
                return
            }

            // ignore images with the same index (we don't want to mark the image as a duplicate of itself!
            // also ignore cases where the reverse is already in the duplicates (I.E. if we already have A -> B in our duplicates, we should not add B -> A)
            // finally make sure this is actually a duplicate!
            if
                compareIndex != matchIndex &&
                !imageReverseAlreadyInDuplicates(toCompare: toCompare, toMatch: toMatch) &&
                imageIsDuplicate(lhs: toMatch, rhs: toCompare)
            {
                
                // if the duplicates doesn't already contain this key
                if (!self.duplicates.keys.contains(toMatch)) {
                    self.duplicates[toMatch] = []
                    self.duplicateItems.append(DuplicateItem(image: toMatch))
                }
                
                // add this into the list!
                self.duplicates[toMatch]!.append(DuplicateItem(image: toCompare))
                
            }
            
        })
        
    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        }
            
    }
}
