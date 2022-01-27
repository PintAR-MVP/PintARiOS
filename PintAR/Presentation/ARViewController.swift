//
//  ARViewController.swift
//  PintAR
//
//  Created by Daniel Klinkert on 16.01.22.
//

import UIKit
import ARKit
import Combine

class ARViewController: UIViewController, UIGestureRecognizerDelegate, ARSessionDelegate, ARSCNViewDelegate {

	@IBOutlet private var sceneView: ARSCNView!

	private var viewportSize: CGSize = .zero
	private var cameraLiveViewLayer: SKScene?
	private var rectangleMaskLayer = CAShapeLayer()
	private var addedAnchors = Set<DetectedObject>()

	// The pixel buffer being held for analysis; used to serialize Vision requests.
	private var currentBuffer: CVPixelBuffer?
	private lazy var viewModel = CameraViewModel(detectObjectUseCase: DetectObjectUseCase(detectionTypes: [.rectangles(model: .yoloV5)]))
	var bufferSize: CGSize = .zero
	var cancellableSet: Set<AnyCancellable> = []

	override func viewDidLoad() {
		super.viewDidLoad()

		self.viewModel.configureVision()
		self.setupSubscribers()
		self.sceneView.showsStatistics = true
		self.sceneView.delegate = self
		self.sceneView.session.delegate = self
		viewportSize = sceneView.frame.size
		sceneView.debugOptions = [.showFeaturePoints]
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		viewportSize = sceneView.frame.size
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		// Create a session configuration
		let configuration = ARWorldTrackingConfiguration()

		// Run the view's session
		self.sceneView.session.run(configuration)
	}

	private func setupSubscribers() {
		self.viewModel.$objectFrame
			.receive(on: DispatchQueue.main)
			.sink(receiveValue: { frame in
				self.removeRectangleMask()
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

		guard currentBuffer == nil, case .normal = frame.camera.trackingState else {
			return
		}

		// Retain the image buffer for Vision processing.
		self.currentBuffer = frame.capturedImage
		guard let buff = self.sceneView.snapshot().transformImageToBuffer() else {
			debugPrint("Nop")
			return
		}
		self.viewModel.recognizeObject(image: buff)
	}

	private func drawBoundingBox(boundingBox: [CGRect]) {
		for observation in self.viewModel.detectedObjects where observation.image != nil && observation.text != nil && addedAnchors.contains(observation) == false {
			guard let currentFrame = sceneView.session.currentFrame else {
				debugPrint("skip current frame")
				continue
			}

			// Get the affine transform to convert between normalized image coordinates and view coordinates
			let fromCameraImageToViewTransform = currentFrame.displayTransform(for: .portrait, viewportSize: viewportSize)
			// The observation's bounding box in normalized image coordinates
			let boundingBox = observation.boundingBox
			// Transform the latter into normalized view coordinates
			let viewNormalizedBoundingBox = boundingBox.applying(fromCameraImageToViewTransform)
			// The affine transform for view coordinates
			let t = CGAffineTransform(scaleX: viewportSize.width, y: viewportSize.height)
			// Scale up to view coordinates
			let viewBoundingBox = viewNormalizedBoundingBox.applying(t)

			let midPoint = CGPoint(x: viewBoundingBox.midX, y: viewBoundingBox.midY)

			let query = sceneView.raycastQuery(from: midPoint, allowing: .estimatedPlane, alignment: .vertical)

//			let results = sceneView.hitTest(midPoint, types: .featurePoint)
//
//			guard let result = results.first else {
//				debugPrint("missed")
//				continue
//			}
			guard
				let resultQuery = query,
				let result = sceneView.session.raycast(resultQuery).first else {
					debugPrint("missed")
					continue
			}

			debugPrint("not missed")
			let anchor = ARAnchor(name: observation.text ?? "nop", transform: result.worldTransform)
			if addedAnchors.contains(observation) == false {
				sceneView.session.add(anchor: anchor)
				self.addedAnchors.insert(observation)
			}

			// detectRemoteControl = false
		}
	}

	private func removeRectangleMask() {
		self.rectangleMaskLayer.sublayers?.removeAll()
		self.rectangleMaskLayer.removeFromSuperlayer()
	}

	func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
	}

	func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
		let plane = SCNPlane(width: 0.010, height: 0.015)
		plane.firstMaterial?.diffuse.contents = UIColor.red

		let planeNode = SCNNode(geometry: plane)
		planeNode.eulerAngles.y = .pi

		let node = SCNNode()
		node.addChildNode(planeNode)

		let spacing: Float = 0.005

		let bioNode = textNode(anchor.name ?? "test", font: UIFont.systemFont(ofSize: 4), maxWidth: 100)
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

		if let maxWidth = maxWidth {
			text.containerFrame = CGRect(origin: .zero, size: CGSize(width: maxWidth, height: 500))
			text.isWrapped = true
		}

		let textNode = SCNNode(geometry: text)
		textNode.scale = SCNVector3(0.002, 0.002, 0.002)

		return textNode
	}
}

extension SCNNode {
	var height: Float {
		return (boundingBox.max.y - boundingBox.min.y) * scale.y
	}

	func pivotOnTopLeft() {
		let (min, max) = boundingBox
		pivot = SCNMatrix4MakeTranslation(min.x, max.y, 0)
	}

	func pivotOnTopCenter() {
		let (_, max) = boundingBox
		pivot = SCNMatrix4MakeTranslation(0, max.y, 0)
	}
}
