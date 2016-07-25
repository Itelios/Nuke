//
//  AnimatedImageDemoViewController.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 18/09/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import UIKit
import Nuke
import NukeAnimatedImagePlugin
import FLAnimatedImage

private let textViewCellReuseID = "textViewReuseID"
private let imageCellReuseID = "imageCellReuseID"

class AnimatedImageDemoViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    var imageURLs = [URL]()
    
    var imageManager: Nuke.Manager {
        let decoder = NukeAnimatedImagePlugin.DataDecoderComposition(decoders: [AnimatedImageDecoder(), Nuke.ImageDataDecoder()])
        let loader = Nuke.Loader(dataLoader: Nuke.DataLoader(), dataDecoder: decoder)
        // FIXME: Configure image manager to prevent animated image processing
        return Nuke.Manager(loader: loader, cache: AnimatedImageCache())
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        collectionView?.register(UICollectionViewCell.self, forCellWithReuseIdentifier: textViewCellReuseID)
        collectionView?.register(AnimatedImageCell.self, forCellWithReuseIdentifier: imageCellReuseID)
        collectionView?.backgroundColor = UIColor.white()
        
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        layout.sectionInset = UIEdgeInsetsMake(8, 8, 8, 8)
        layout.minimumInteritemSpacing = 8
        
        let root = "https://cloud.githubusercontent.com/assets"
        imageURLs = [
            URL(string: "\(root)/1567433/6505557/77ff05ac-c2e7-11e4-9a09-ce5b7995cad0.gif")!,
            URL(string: "\(root)/1567433/6505565/8aa02c90-c2e7-11e4-8127-71df010ca06d.gif")!,
            URL(string: "\(root)/1567433/6505571/a28a6e2e-c2e7-11e4-8161-9f39cc3bb8df.gif")!,
            URL(string: "\(root)/1567433/6505576/b785a8ac-c2e7-11e4-831a-666e2b064b95.gif")!,
            URL(string: "\(root)/1567433/6505579/c88c77ca-c2e7-11e4-88ad-d98c7360602d.gif")!,
            URL(string: "\(root)/1567433/6505595/def06c06-c2e7-11e4-9cdf-d37d28618af0.gif")!,
            URL(string: "\(root)/1567433/6505634/26e5dad2-c2e8-11e4-89c3-3c3a63110ac0.gif")!,
            URL(string: "\(root)/1567433/6505643/42eb3ee8-c2e8-11e4-8666-ac9c8e1dc9b5.gif")!
        ]
    }
    
    // MARK: Collection View
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return section == 0 ? 1 : imageURLs.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.section == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: textViewCellReuseID, for: indexPath)
            var textView: UITextView! = cell.viewWithTag(14) as? UITextView
            if textView == nil {
                textView = UITextView()
                textView.textColor = UIColor.black()
                textView.font = UIFont.systemFont(ofSize: 16)
                textView.isEditable = false
                textView.textAlignment = .center
                textView.dataDetectorTypes = .link
                
                cell.contentView.addSubview(textView)
                textView.frame = cell.contentView.bounds
                textView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
                
                textView.text = "Images by Florian de Looij\n http://flrn.nl/gifs/"
            }
            return cell
        } else {
            let cell: AnimatedImageCell = collectionView.dequeueReusableCell(withReuseIdentifier: imageCellReuseID, for: indexPath) as! AnimatedImageCell
            cell.imageView.nk_imageLoadingController.manager = imageManager
            cell.setImage(with: imageURLs[indexPath.row])
            return cell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        let width = view.bounds.size.width - layout.sectionInset.left - layout.sectionInset.right
        if indexPath.section == 0 {
            return CGSize(width: width, height: 50)
        } else {
            return CGSize(width: width, height: width)
        }
    }
}

private class AnimatedImageCell: UICollectionViewCell {
    private let imageView = FLAnimatedImageView(frame: CGRect.zero)
    private let progressView = UIProgressView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = UIColor(white: 235.0 / 255.0, alpha: 1)
        
        addSubview(imageView)
        addSubview(progressView)
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        
        let views = ["imageView": imageView, "progressView": progressView]
        
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|[imageView]|", options: NSLayoutFormatOptions(), metrics: nil, views: views))
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[imageView]|", options: NSLayoutFormatOptions(), metrics: nil, views: views))
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|[progressView]|", options: NSLayoutFormatOptions(), metrics: nil, views: views))
        addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[progressView(==4)]", options: NSLayoutFormatOptions(), metrics: nil, views: views))
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func setImage(with url: Foundation.URL) {
        setImage(with: Request(url: url))
    }
    
    func setImage(with request: Request) {
        imageView.nk_setImage(with: request)
        if let task = imageView.nk_imageTask {
            task.progressHandler = { [weak self, weak task] completed, total in
                guard let task = task, task == self?.imageView.nk_imageTask else {
                    return
                }
                let fractionCompleted = total == 0 ? 0.0 : Float(completed) / Float(total)
                self?.progressView.setProgress(fractionCompleted, animated: true)
                if fractionCompleted == 1 {
                    UIView.animate(withDuration: 0.2) {
                        self?.progressView.alpha = 0
                    }
                }
            }
        }
    }
    
    private override func prepareForReuse() {
        super.prepareForReuse()
        progressView.progress = 0
        progressView.alpha = 1
        imageView.nk_display(nil)
        imageView.nk_cancelLoading()
    }
}
