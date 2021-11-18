//
//  ImageDetailViewController.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 18.11.21.
//

import UIKit

class ImageDetailViewController: UIViewController {

    // MARK: - Properties

    private let imageView = UIImageView()
    private let closeButton = UIButton()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        blur.frame = closeButton.bounds
        blur.layer.cornerRadius = 0.5 * closeButton.bounds.size.width
    }

    // MARK: - Configuration

    func setImage(image: UIImage?) {
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
    }

    // MARK: - UI Setup

    private func setupUI() {
        setupImageView()
        setupCloseButton()
    }

    private func setupImageView() {
        view.addSubview(imageView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupCloseButton() {
        view.addSubview(closeButton)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            closeButton.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            closeButton.heightAnchor.constraint(equalToConstant: 34),
            closeButton.widthAnchor.constraint(equalTo: closeButton.heightAnchor)
        ])

        var image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold))
        image = image?.withRenderingMode(.alwaysTemplate)
        closeButton.setImage(image, for: .normal)
        closeButton.imageView?.tintColor = UIColor.white

        blur.isUserInteractionEnabled = false
        blur.clipsToBounds = true
        closeButton.insertSubview(blur, at: 0)
        if let imageView = closeButton.imageView {
            closeButton.bringSubviewToFront(imageView)
        }

        closeButton.addTarget(self, action: #selector(dismissView), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func dismissView() {
        dismiss(animated: true)
    }
}
