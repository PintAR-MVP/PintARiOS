//
//  ARViewController.swift
//  PintAR
//
//  Created by Daniel Klinkert on 16.01.22.
//

import UIKit
import ARKit
import Combine
import RealityKit

class ARViewController: UIViewController, UIGestureRecognizerDelegate, ARSessionDelegate, ARSCNViewDelegate {

	private enum SessionState {
		case settingUp
		case ready
	}

	@IBOutlet private var sceneView: ARSCNView!

	private var viewportSize: CGSize = .zero
	private var cameraLiveViewLayer: SKScene?
	private var rectangleMaskLayer = CAShapeLayer()
	private var addedAnchors = Set<DetectedObject>()
	private var sessionState: SessionState = .settingUp

	// The pixel buffer being held for analysis; used to serialize Vision requests.
	private var currentBuffer: CVPixelBuffer?
	private lazy var viewModel = CameraViewModel(detectObjectUseCase: DetectObjectUseCase(detectionTypes: [.rectangles(model: .yoloV5)]))
	var bufferSize: CGSize = .zero
	var cancellableSet: Set<AnyCancellable> = []
	private let coachingOverlay = ARCoachingOverlayView()

	override func viewDidLoad() {
		super.viewDidLoad()

		self.viewModel.configureVision()
		self.setupSubscribers()
		self.sceneView.showsStatistics = true
		self.sceneView.delegate = self
		self.sceneView.session.delegate = self
		self.viewportSize = sceneView.frame.size
		// Set up coaching overlay.
		self.setupCoachingOverlay()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		viewportSize = sceneView.frame.size
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		// Create a session configuration
		let configuration = ARWorldTrackingConfiguration()
		configuration.planeDetection = .vertical

		// Run the view's session
		self.sceneView.session.run(configuration)
	}

	private func setupSubscribers() {
		self.viewModel.$objectFrame
			.receive(on: DispatchQueue.main)
			.sink(receiveValue: { frame in
				//self.removeRectangleMask()
				self.drawBoundingBox(boundingBox: frame)
				self.currentBuffer = nil
			})
			.store(in: &cancellableSet)
	}

	// Pass camera frames received from ARKit to Vision (when not already processing one)
	/// - Tag: ConsumeARFrames
	func session(_ session: ARSession, didUpdate frame: ARFrame) {
		// Do not enqueue other buffers for processing while another Vision task is still running.
		// The camera stream has only a finite amount of buffers available; holding too many buffers for analysis would starve the camera.
		guard
			currentBuffer == nil,
			case .normal = frame.camera.trackingState,
			case .ready = self.sessionState else {
				return
		}

		// Retain the image buffer for Vision processing.
		self.currentBuffer = frame.capturedImage
		self.viewModel.recognizeObject(image: frame.capturedImage)
	}

	private func drawBoundingBox(boundingBox: [CGRect]) {
		for observation in self.viewModel.accurateObjects {
			guard let currentFrame = sceneView.session.currentFrame else {
				debugPrint("skip current frame")
				continue
			}

			guard self.addedAnchors.contains(observation) == false else {
				continue
			}

			let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -sceneView.bounds.height)
			let scale = CGAffineTransform.identity.scaledBy(x: sceneView.bounds.width, y: sceneView.bounds.height)
			let bounds = observation.boundingBox.applying(scale).applying(transform)
			let midPoint2 = CGPoint(x: bounds.midX, y: bounds.midY)

//			// Get the affine transform to convert between normalized image coordinates and view coordinates
//			let fromCameraImageToViewTransform = currentFrame.displayTransform(for: .portrait, viewportSize: self.viewportSize)
//			// The observation's bounding box in normalized image coordinates
//			let boundingBox = observation.boundingBox
//			// Transform the latter into normalized view coordinates
//			let viewNormalizedBoundingBox = boundingBox.applying(fromCameraImageToViewTransform)
//			// The affine transform for view coordinates
//			let t = CGAffineTransform(scaleX: viewportSize.width, y: self.viewportSize.height)
//			// Scale up to view coordinates
//			let viewBoundingBox = viewNormalizedBoundingBox.applying(t)
//
//			let midPoint = CGPoint(x: viewBoundingBox.midX, y: viewBoundingBox.midY)

			let query = self.sceneView.raycastQuery(from: midPoint2, allowing: .estimatedPlane, alignment: .vertical)

			guard
				let resultQuery = query,
				let result = self.sceneView.session.raycast(resultQuery).first else {
					debugPrint("missed")
					continue
			}

			let anchor = ARAnchor(name: observation.id.uuidString, transform: result.worldTransform)
			anchor.box = bounds
			self.sceneView.session.add(anchor: anchor)
			self.addedAnchors.insert(observation)
		}

		self.viewModel.stop = self.viewModel.accurateObjects.count > 3
	}

	func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
		guard
			let observationId = anchor.name,
			let currentObservation = self.viewModel.accurateObjects.first(where: { $0.id.uuidString == observationId })  else {
				return nil
		}

		let plane = SCNPlane(width: (anchor.box.width / 5000), height: (anchor.box.height / 5000))
		plane.firstMaterial?.diffuse.contents = UIColor.red

		let planeNode = SCNNode(geometry: plane)
		//rotate with respect to camera

		planeNode.rotation = SCNVector4Make(-1, 0, 0, .pi / 2)
		planeNode.pivotOnTopLeft()

		let node = SCNNode()
		node.addChildNode(planeNode)

		let spacing: Float = 0.005

		let bioNode = textNode(currentObservation.text ?? "test", font: UIFont.systemFont(ofSize: 4), maxWidth: nil)
		bioNode.pivotOnTopLeft()

		bioNode.position.x += Float(plane.width / 2) + spacing
		bioNode.position.y += Float(plane.height / 2)

		planeNode.addChildNode(bioNode)
		return node
	}

	func textNode(_ str: String, font: UIFont, maxWidth: Int? = nil) -> SCNNode {
		let text = SCNText(string: str, extrusionDepth: 0)

		text.flatness = 0.1
		text.font = font
		text.firstMaterial?.diffuse.contents = UIColor.black

		if let maxWidth = maxWidth {
			text.containerFrame = CGRect(origin: .zero, size: CGSize(width: maxWidth, height: 100))
			text.isWrapped = true
		}

		let textNode = SCNNode(geometry: text)
		textNode.scale = SCNVector3(0.002, 0.002, 0.002)

		return textNode
	}

	@IBAction private func resetTrackingButton(_ sender: UIButton) {
		self.resetTracking()
	}

	private func resetTracking() {
		self.addedAnchors.removeAll()
		let configuration = ARWorldTrackingConfiguration()
		self.sceneView.session.run(configuration, options: [.removeExistingAnchors, .resetTracking])
		self.viewModel.stop = false
	}
}

extension ARAnchor {

	struct Holder {
		static var _box:CGRect = CGRect()
	}

	var box:CGRect {
		get {
			return Holder._box
		}
		set(newValue) {
			Holder._box = newValue
		}
	}
}

/// - Tag: CoachingOverlayViewDelegate
extension ARViewController: ARCoachingOverlayViewDelegate {

	/// - Tag: HideUI
	func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
		self.sceneView.scene.rootNode.enumerateChildNodes { currentNode, _ in
			currentNode.removeFromParentNode()
		}

		self.sessionState = .settingUp
	}

	/// - Tag: PresentUI
	func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
		self.viewModel.stop = false
		self.currentBuffer = nil
		self.sessionState = .ready
	}

	/// - Tag: StartOver
	func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
		// restartExperience()
	}

	func setupCoachingOverlay() {
		// Set up coaching view
		self.coachingOverlay.session = sceneView.session
		self.coachingOverlay.delegate = self

		self.coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
		self.sceneView.addSubview(self.coachingOverlay)

		NSLayoutConstraint.activate([
			self.coachingOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			self.coachingOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
			self.coachingOverlay.widthAnchor.constraint(equalTo: view.widthAnchor),
			self.coachingOverlay.heightAnchor.constraint(equalTo: view.heightAnchor)
		])

		self.setActivatesAutomatically()

		// Most of the virtual objects in this sample require a horizontal surface,
		// therefore coach the user to find a horizontal plane.
		self.setGoal()
	}

	/// - Tag: CoachingActivatesAutomatically
	func setActivatesAutomatically() {
		self.coachingOverlay.activatesAutomatically = true
	}

	/// - Tag: CoachingGoal
	func setGoal() {
		coachingOverlay.goal = .verticalPlane
	}
}
