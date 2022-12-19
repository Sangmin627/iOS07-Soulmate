//
//  LaunchViewController.swift
//  Soulmate
//
//  Created by termblur on 2022/11/29.
//

import UIKit

import SnapKit

final class LaunchViewController: UIViewController {
    
    private lazy var logo: UIImageView = {
        let imageView = UIImageView()
        view.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(named: "logo")
        
        return imageView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        
        logo.snp.makeConstraints {
            $0.width.equalTo(192)
            $0.centerX.equalTo(view.snp.centerX)
            $0.centerY.equalTo(view.snp.centerY)
        }
    }
}
