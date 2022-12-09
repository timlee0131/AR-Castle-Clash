//
//  GalleryCell.swift
//  ARgallery
//
//  Created by zhongyuan liu on 12/7/22.
//

import UIKit

class CollectionCell: UICollectionViewCell {
    
    
    @IBOutlet weak var imageView: UIImageView!
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }
    
}
