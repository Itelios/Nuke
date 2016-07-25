//
//  AlamofireDemoViewController.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 18/09/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import Foundation
import Nuke
import NukeAlamofirePlugin

class AlamofireDemoViewController: BasicDemoViewController {    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let loader = Nuke.Loader(loader: NukeAlamofirePlugin.DataLoader(), decoder: Nuke.ImageDataDecoder())
        imageManager = Nuke.Manager(loader: loader, cache: Nuke.Cache())
    }
}
