//
//  CameraViewController.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 18.11.21.
//

import UIKit
import AVFoundation
import Vision
import Combine

class CameraViewController: UIViewController {

	// MARK: - Properties

	private let cameraView = UIView()
	private let takePhotoButton = UIButton()
	private let imagePickerButton = UIButton()
	private let recognizedTextLabel = UILabel()
	private lazy var imagePicker = UIImagePickerController()
	private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .light))
	private var inputDevice: AVCaptureDeviceInput?

	private var videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
	private var cameraLiveViewLayer: AVCaptureVideoPreviewLayer?
	private let captureSession: AVCaptureSession = {
		let session = AVCaptureSession()
		session.sessionPreset = .high
		return session
	}()

	private lazy var viewModel = CameraViewModel(detectObjectUseCase: DetectObjectUseCase(detectionTypes: [.rectangles(model: .yoloV5)]))

	private var rectangleMaskLayer = CAShapeLayer()

	private var didShowAlert: Bool = false
	private var isTapped = false

	var bufferSize: CGSize = .zero
	var cancellableSet: Set<AnyCancellable> = []

	// MARK: - Lifecycle
	override func viewDidLoad() {
		super.viewDidLoad()

		self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "frame_processing_queue"))
		self.setupUI()
		self.setupSubscribers()
		self.setupCameraInput()
		self.setupCameraOutput()
		self.viewModel.configureVision()
		self.startCaptureSession()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		self.cameraLiveViewLayer?.frame = self.cameraView.bounds

		self.blur.frame = self.takePhotoButton.bounds
		self.blur.layer.cornerRadius = 0.5 * self.takePhotoButton.bounds.size.width
	}

	// MARK: - UI Setup
	private func setupUI() {
		self.setupCameraView()
		self.setupTakePhotoButton()
		self.setupRecognizedTextLabel()
		self.setupImageGalleryButton()
	}

	private func setupSubscribers() {
		self.viewModel.$accurateObjects
			.receive(on: DispatchQueue.main)
			.sink(receiveValue: { accurateObjects in
				let boxes = accurateObjects.map { $0.boundingBox }
				self.removeRectangleMask()
				self.drawBoundingBox(boundingBox: boxes)
			})
			.store(in: &cancellableSet)
	}

	private func setupCameraView() {
		view.addSubview(self.cameraView)

		self.cameraView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			self.cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			self.cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			self.cameraView.topAnchor.constraint(equalTo: view.topAnchor),
			self.cameraView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
	}

	private func setupTakePhotoButton() {
		self.view.addSubview(takePhotoButton)

		self.takePhotoButton.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			self.takePhotoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			self.takePhotoButton.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
			self.takePhotoButton.heightAnchor.constraint(equalToConstant: 70),
			self.takePhotoButton.widthAnchor.constraint(equalTo: self.takePhotoButton.heightAnchor)
		])

		var image = UIImage(systemName: "record.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular))
		image = image?.withRenderingMode(.alwaysTemplate)

		self.takePhotoButton.setImage(image, for: .normal)
		self.takePhotoButton.imageView?.tintColor = UIColor.white

		self.blur.isUserInteractionEnabled = false
		self.blur.clipsToBounds = true
		self.blur.layer.borderWidth = 2
		self.blur.layer.borderColor = UIColor.white.cgColor
		self.takePhotoButton.insertSubview(blur, at: 0)
		if let imageView = self.takePhotoButton.imageView {
			self.takePhotoButton.bringSubviewToFront(imageView)
		}

		self.takePhotoButton.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
	}

	private func setupRecognizedTextLabel() {
		self.view.addSubview(recognizedTextLabel)

		self.recognizedTextLabel.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			self.recognizedTextLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
			self.recognizedTextLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
			self.recognizedTextLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 20)
		])

		self.recognizedTextLabel.textAlignment = .center
		self.recognizedTextLabel.textColor = .white
		self.recognizedTextLabel.numberOfLines = 0
		self.recognizedTextLabel.font = .preferredFont(forTextStyle: .caption1)
	}

	private func setupImageGalleryButton() {
		self.view.addSubview(self.imagePickerButton)

		self.imagePickerButton.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			self.imagePickerButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
			self.imagePickerButton.centerYAnchor.constraint(equalTo: self.takePhotoButton.centerYAnchor),
			self.imagePickerButton.heightAnchor.constraint(equalToConstant: 40),
			self.imagePickerButton.widthAnchor.constraint(equalTo: self.takePhotoButton.heightAnchor)
		])

		var galleryImage = UIImage(systemName: "photo.on.rectangle.angled", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular))
		galleryImage = galleryImage?.withRenderingMode(.alwaysTemplate)

		self.imagePickerButton.setImage(galleryImage, for: .normal)
		self.imagePickerButton.imageView?.tintColor = UIColor.white

		self.imagePickerButton.addTarget(self, action: #selector(openImageGallery), for: .touchUpInside)
	}

	// MARK: - Camera Setup
	private func setupCameraInput() {
		guard let camera = AVCaptureDevice.default(for: .video) else {
			return
		}

		try? camera.lockForConfiguration()
		camera.focusMode = .autoFocus
		camera.unlockForConfiguration()
		let dimensions = CMVideoFormatDescriptionGetDimensions((camera.activeFormat.formatDescription))
		self.bufferSize.width = CGFloat(dimensions.width)
		self.bufferSize.height = CGFloat(dimensions.height)
		self.inputDevice = try? AVCaptureDeviceInput(device: camera)

		guard
			let input = self.inputDevice,
			self.captureSession.canAddInput(input) else {
				return
		}

		self.captureSession.addInput(input)
		self.cameraLiveViewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
		self.cameraLiveViewLayer?.videoGravity = .resize
		self.cameraLiveViewLayer?.connection?.videoOrientation = .portrait
	}

	private func setupCameraOutput() {
		self.videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString): NSNumber(value: kCVPixelFormatType_32BGRA)] as [String: Any]
		self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
		self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
		self.captureSession.addOutput(self.videoDataOutput)

		guard
			let connection = self.videoDataOutput.connection(with: AVMediaType.video),
			connection.isVideoOrientationSupported else {
				return
			}

		connection.videoOrientation = .portrait
	}

	func startCaptureSession() {
		guard let cameraLiveViewLayer = self.cameraLiveViewLayer else {
			return
		}

		self.cameraView.layer.addSublayer(cameraLiveViewLayer)
		self.captureSession.startRunning()
	}

	// MARK: - Focus
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesBegan(touches, with: event)

		guard let touch = touches.first else {
			return
		}

		let location = touch.location(in: self.cameraView)
		try? self.inputDevice?.device.lockForConfiguration()
		self.inputDevice?.device.focusPointOfInterest = location
		self.inputDevice?.device.unlockForConfiguration()
	}

	// MARK: - Actions
	@objc private func openImageGallery() {
		self.imagePicker.sourceType = .photoLibrary
		self.imagePicker.allowsEditing = false
		self.imagePicker.delegate = self
		present(self.imagePicker, animated: true, completion: nil)
	}

	@objc private func takePhoto() {
		self.isTapped.toggle()
        // Start backend calls
        for detectedObject in viewModel.accurateObjects {
            isTapped ? detectedObject.queryBackend() : detectedObject.cancelRequest()
        }
	}

	private func showDetailImageView(with image: UIImage?) {
		let imageDetailController = ImageDetailViewController()
		imageDetailController.setImage(image: image)
		imageDetailController.modalPresentationStyle = .fullScreen
		present(imageDetailController, animated: true, completion: nil)
	}
}

// MARK: - UIImagePickerControllerDelegate
extension CameraViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

	func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
		picker.dismiss(animated: true) { [weak self] in
			guard let pickedImage = info[.originalImage] as? UIImage else {
				return
			}

			self?.showDetailImageView(with: pickedImage)
		}
	}
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraViewController: AVCapturePhotoCaptureDelegate {

	func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
		guard let imageData = photo.fileDataRepresentation() else {
			return
		}

		let image = UIImage(data: imageData)
		self.showDetailImageView(with: image)
	}
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
			return
		}

		self.viewModel.recognizeObject(image: pixelBuffer)
	}
}

// MARK: - Draw overlays
extension CameraViewController {

	private func drawBoundingBox(boundingBox: [CGRect]) {
		guard
			let cameraLiveViewLayer = self.cameraLiveViewLayer,
			boundingBox.isEmpty == false else {
				return
		}

		let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -cameraLiveViewLayer.bounds.height)
		let scale = CGAffineTransform.identity.scaledBy(x: cameraLiveViewLayer.bounds.width, y: cameraLiveViewLayer.bounds.height)

		for box in boundingBox {
			let boxLayer = CAShapeLayer()
			let bounds = box.applying(scale).applying(transform)
			boxLayer.frame = bounds
			boxLayer.cornerRadius = 10
			boxLayer.opacity = 1
			boxLayer.borderColor = UIColor.systemBlue.cgColor
			boxLayer.borderWidth = 6.0

			self.rectangleMaskLayer.addSublayer(boxLayer)
		}

		self.cameraLiveViewLayer?.insertSublayer(self.rectangleMaskLayer, at: 1)
	}

	private func removeRectangleMask() {
		self.rectangleMaskLayer.sublayers?.removeAll()
		self.rectangleMaskLayer.removeFromSuperlayer()
	}
}
