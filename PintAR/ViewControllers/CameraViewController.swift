//
//  CameraViewController.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 18.11.21.
//

import UIKit
import AVFoundation

class CameraViewController: UIViewController {

    // MARK: - Properties

    private let cameraView = UIView()
    private let takePhotoButton = UIButton()
    private let imagePickerButton = UIButton()
    private var imagePicker = UIImagePickerController()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .light))

    private var stillImageOutput: AVCapturePhotoOutput = AVCapturePhotoOutput()
    private var cameraLiveViewLayer: AVCaptureVideoPreviewLayer?
    private let captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        return session
    }()

    private var didShowAlert: Bool = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        #if targetEnvironment(simulator)
        showNotSupportedAlert()
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        cameraLiveViewLayer?.frame = cameraView.bounds

        blur.frame = takePhotoButton.bounds
        blur.layer.cornerRadius = 0.5 * takePhotoButton.bounds.size.width
    }

    // MARK: - UI Setup

    private func setupUI() {
        setupCameraView()
        setupTakePhotoButton()
        setupImageGalleryButton()
    }

    private func setupCameraView() {
        view.addSubview(cameraView)

        cameraView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupTakePhotoButton() {
        view.addSubview(takePhotoButton)

        takePhotoButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            takePhotoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            takePhotoButton.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
            takePhotoButton.heightAnchor.constraint(equalToConstant: 70),
            takePhotoButton.widthAnchor.constraint(equalTo: takePhotoButton.heightAnchor),
        ])

        var image = UIImage(systemName: "camera", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular))
        image = image?.withRenderingMode(.alwaysTemplate)

        takePhotoButton.setImage(image, for: .normal)
        takePhotoButton.imageView?.tintColor = UIColor.white

        blur.isUserInteractionEnabled = false
        blur.clipsToBounds = true
        blur.layer.borderWidth = 2
        blur.layer.borderColor = UIColor.white.cgColor
        takePhotoButton.insertSubview(blur, at: 0)
        if let imageView = takePhotoButton.imageView{
            takePhotoButton.bringSubviewToFront(imageView)
        }

        takePhotoButton.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
    }

    private func setupImageGalleryButton() {
        view.addSubview(imagePickerButton)

        imagePickerButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imagePickerButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            imagePickerButton.centerYAnchor.constraint(equalTo: takePhotoButton.centerYAnchor),
            imagePickerButton.heightAnchor.constraint(equalToConstant: 40),
            imagePickerButton.widthAnchor.constraint(equalTo: takePhotoButton.heightAnchor),
        ])

        var galleryImage = UIImage(systemName: "photo.on.rectangle.angled", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular))
        galleryImage = galleryImage?.withRenderingMode(.alwaysTemplate)

        imagePickerButton.setImage(galleryImage, for: .normal)
        imagePickerButton.imageView?.tintColor = UIColor.white

        imagePickerButton.addTarget(self, action: #selector(openImageGallery), for: .touchUpInside)
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        guard let camera = AVCaptureDevice.default(for: .video) else {
            return
        }

        let input = try? AVCaptureDeviceInput(device: camera)

        stillImageOutput = AVCapturePhotoOutput()

        if let input = input, captureSession.canAddInput(input), captureSession.canAddOutput(stillImageOutput) {
            captureSession.addInput(input)
            captureSession.addOutput(stillImageOutput)

            cameraLiveViewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            cameraLiveViewLayer?.videoGravity = .resize
            cameraLiveViewLayer?.connection?.videoOrientation = .portrait

            if let cameraLiveViewLayer = cameraLiveViewLayer {
                cameraView.layer.addSublayer(cameraLiveViewLayer)
                captureSession.startRunning()
            }
        }
    }

    // MARK: - Actions

    @objc private func openImageGallery() {
        imagePicker.sourceType = .photoLibrary
        imagePicker.allowsEditing = false
        imagePicker.delegate = self
        present(self.imagePicker, animated: true, completion: nil)
    }

    @objc private func takePhoto() {
        #if targetEnvironment(simulator)
        #else
        let cameraSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        stillImageOutput.capturePhoto(with: cameraSettings, delegate: self)
        #endif
    }

    private func showNotSupportedAlert() {
        guard didShowAlert == false else { return }
        didShowAlert = true
        let alert = UIAlertController(title: "Camera Not Supported", message: "The camera is not supported on the Xcode Simulator. Use a real device or choose an image from your gallery.", preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        alert.addAction(okAction)
        present(alert, animated: true)
    }

    // MARK: - Helper

    private func showDetailImageView(with image: UIImage?) {
        let vc = ImageDetailViewController()
        vc.setImage(image: image)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true, completion: nil)
    }
}

// MARK: - UIImagePickerControllerDelegate

extension CameraViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true, completion: {
            if let pickedImage = info[.originalImage] as? UIImage {
                self.showDetailImageView(with: pickedImage)
            }
        })
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraViewController: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {

        guard let imageData = photo.fileDataRepresentation()
        else { return }

        let image = UIImage(data: imageData)
        showDetailImageView(with: image)
    }
}
