//
//  CustomCacheDemoViewController.swift
//  Nuke Demo
//
//  Created by Alexander Grebenyuk on 18/03/16.
//  Copyright © 2016 CocoaPods. All rights reserved.
//

import Foundation
import Nuke
import DFCache

class CustomCacheDemoViewController: BasicDemoViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let loader = ImageLoader(dataLoader: DataLoader(), dataDecoder: DataDecoder(), dataCache: DFDiskCache(name: "test"))
        imageManager =  ImageManager(loader: loader, cache: ImageCache())
    }

}
