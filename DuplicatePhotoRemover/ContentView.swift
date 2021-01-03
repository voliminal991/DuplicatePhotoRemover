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

struct DuplicateItem: Identifiable {
  var id = UUID()
  var image: PHAsset
}

struct ContentView: View {
    
    @State private var currentPhotoIndex: Int = 0
    @State private var photoCount: Int = 1
    
    @State private var running = false
    
    @State private var duplicates: [PHAsset: [PHAsset]] = [:]
    @State private var duplicateItems: [DuplicateItem] = []
    
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
                
            }
            
            List(self.duplicateItems) { duplicate in
                Text("\(duplicate.image.creationDate!)")
            }
        }
        
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
                
                // if they have the exact same date, they might be a duplicate!
                if (toCompare.creationDate == toMatch.creationDate) {
                    
                    // if the duplicates doesn't already contain this key
                    if (!self.duplicates.keys.contains(toMatch)) {
                        self.duplicates[toMatch] = []
                        self.duplicateItems.append(DuplicateItem(image: toMatch))
                    }
                    
                    // add this into the list!
                    self.duplicates[toMatch]!.append(toCompare)
                    
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
