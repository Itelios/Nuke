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
        
        let loader = Nuke.Loader(loader: Nuke.DataLoader(), decoder: Nuke.DataDecoder(), cache: DFDiskCache(name: "test"))
        imageManager =  Nuke.Manager(loader: loader, cache: Nuke.Cache())
    }

}
