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
        VStack {

            Button("Look for duplicates") {
                self.running = true
                DispatchQueue.global(qos: .background).async {
                    runDuplicateCheck()
                }
            }.padding()

            if self.running {
                
                Button("Stop Duplicate Check") {
                    self.running = false
                }
                
                ProgressBar(
                    value: currentPhotoIndex,
                    maxValue: photoCount,
                    foregroundColor: .green
                ).frame(height: 10)
                    .padding()
                
                Text("\(currentPhotoIndex) of \(photoCount)")
                    .padding()
                
                Text("Found \(self.duplicateItems.count) Duplicates")
                    .padding()
                
            } else {
                
                HStack {
                    
                    List(self.duplicateItems) { duplicate in
                                        
                        HStack {
                            Button(action: {
                                self.selectedDuplicate = duplicate.image
                            }) {
                                getThumnail(asset: duplicate.image)
                            }.buttonStyle(PlainButtonStyle())
                            getImageLabel(asset: duplicate.image)
                        }
                    }
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 138))]) {
                            if (selectedDuplicate != nil) {
                                ForEach(self.duplicates[self.selectedDuplicate!] ?? []) { duplicate in
                                    VStack {
                                        getThumnail(asset: duplicate.image).padding()
                                        getImageLabel(asset: duplicate.image).padding()
                                    }
                                }
                            }
                        }
                    }
                    
                }
                .frame(height: 138 * 4)
                
            }
            
        }
        
    }


    
    func getImageLabel(asset: PHAsset) -> Text {
        
        if (asset.creationDate == nil) {
            return Text("No Image META")
        }
        
        let RFC3339DateFormatter = DateFormatter()
        RFC3339DateFormatter.locale = Locale(identifier: "en_US_POSIX")
        RFC3339DateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        RFC3339DateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return Text(RFC3339DateFormatter.string(from: asset.creationDate!))
        
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
    
    func runDuplicateCheck() {
        
        let allPhotosOptions = PHFetchOptions()
        allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let allPhotos = PHAsset.fetchAssets(with: allPhotosOptions)
        
        // update our max value
        self.photoCount = allPhotos.count
        
        var innerCount = 0
        var outerCount = 0

        // empty the duplicates list!
        self.duplicates = [:]
        self.duplicateItems = []
        
        while (innerCount < allPhotos.count) {
            
            if (!self.running) {
                print("Stopping inner")
                return
            }
            
            // dump this onto the main thread, we've updated things!
            DispatchQueue.main.async {
                self.currentPhotoIndex = innerCount + 1
            }
            
            // the one to match!
            let toMatch = allPhotos.object(at: innerCount)
            
            var alreadyFound = false
            for (duplicate, _) in self.duplicates {
                if (duplicate.creationDate == toMatch.creationDate && duplicate.mediaSubtypes == toMatch.mediaSubtypes) {
                    self.duplicates[duplicate]!.append(DuplicateItem(image: toMatch))
                    alreadyFound = true
                    break
                }
            }
            
            if (alreadyFound) {
                innerCount += 1
                continue
            }
            
            while (outerCount < allPhotos.count) {
                
                // we don't want to mark ourself as a duplicate!
                if (outerCount == innerCount) {
                    outerCount += 1
                    continue
                }
                
                if (!self.running) {
                    print("Stopping outer")
                    return
                }
                
                // the one to compare
                let toCompare = allPhotos.object(at: outerCount)
                
                // if we've already got the to match image in here, and the opposite duplicate, continue!
                if (self.duplicates.keys.contains(toCompare)) {
                    if (self.duplicates[toCompare]!.contains(DuplicateItem(image: toMatch))) {
                        outerCount += 1
                        continue
                    }
                }
                
                // if they have the exact same date, they might be a duplicate!
                // ensure we compare the media subtypes, so that HDR copies aren'tmarked as duplicates
                if (toCompare.creationDate == toMatch.creationDate && toCompare.mediaSubtypes == toMatch.mediaSubtypes) {
                    
                    // if the duplicates doesn't already contain this key
                    if (!self.duplicates.keys.contains(toMatch)) {
                        self.duplicates[toMatch] = []
                        self.duplicateItems.append(DuplicateItem(image: toMatch))
                    }
                    
                    // add this into the list!
                    self.duplicates[toMatch]!.append(DuplicateItem(image: toMatch))
                    
                }
                
                // increase the counter
                outerCount += 1
                
            }
            
            // increase the counter!
            innerCount += 1
            outerCount = 0
            
        }
        
        self.running = false

    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
