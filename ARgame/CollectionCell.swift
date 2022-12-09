//
//  GalleryCell.swift
//  ARgallery
//
//  Created by zhongyuan liu on 12/7/22.
//

//THIS CLASS IS NO LONGER IN USE

import UIKit

class CollectionCell: UICollectionViewCell {
    
    
    @IBOutlet weak var imageView: UIImageView!
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }
    
}
