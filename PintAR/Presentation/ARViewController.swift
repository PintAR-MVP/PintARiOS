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

	// we keep track of this to determine nearby anchors
	private var rayCastResults = Set<ARRaycastResult>()
	private var sessionState: SessionState = .settingUp
	private var distanceToPlane = Float()
	private var anchorCount = Int()

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
		self.viewportSize = sceneView.frame.size
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		// Create a session configuration
		let configuration = ARWorldTrackingConfiguration()
		configuration.planeDetection = .horizontal
		self.sceneView.debugOptions = [.showFeaturePoints, .showWorldOrigin]

		// Run the view's session
		self.sceneView.session.run(configuration)
	}

	private func setupSubscribers() {
		self.viewModel.$accurateObjects
			.receive(on: DispatchQueue.main)
			.sink { [weak self] accurateObjects in
				self?.removeRectangleMask()
				self?.configureAnchors(detectedObjects: accurateObjects)
				self?.currentBuffer = nil
			}
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

	private func configureAnchors(detectedObjects: [DetectedObject]) {
		for observation in detectedObjects {
			guard self.sceneView.session.currentFrame != nil else {
				debugPrint("skip current frame")
				continue
			}

			let midPoint = self.calculateMidPointForRayCast(for: observation.boundingBox)
			self.drawCurrentBoundingBox(box: observation.boundingBox)
			let query = self.sceneView.raycastQuery(from: midPoint, allowing: .estimatedPlane, alignment: .vertical)
			guard
				let resultQuery = query,
				let result = self.sceneView.session.raycast(resultQuery).first else {
					debugPrint("missed")
					continue
			}

			var anchor = ARAnchor(transform: result.worldTransform)
			anchor = self.zNormalization(anchor: anchor, for: observation.id.uuidString)

			if self.isNewAnchor(newResult: result) == true {
				self.sceneView.session.add(anchor: anchor)
				self.rayCastResults.insert(result)
			} else {
				debugPrint("Drop anchor because it is to close to another anchor")
			}
		}

		// stop recognition and trigger backend call
		// self.viewModel.stop = self.viewModel.accurateObjects.count > 3
	}

	private func calculateMidPointForRayCast(for box: CGRect) -> CGPoint {
		let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.sceneView.bounds.height)
		let scale = CGAffineTransform.identity.scaledBy(x: self.sceneView.bounds.width, y: self.sceneView.bounds.height)
		let bounds = box.applying(scale).applying(transform)
		let midPoint = CGPoint(x: bounds.midX, y: bounds.midY)
		return midPoint
	}

	private func drawCurrentBoundingBox(box: CGRect) {
		let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.sceneView.bounds.height)
		let scale = CGAffineTransform.identity.scaledBy(x: self.sceneView.bounds.width, y: self.sceneView.bounds.height)

		let boxLayer = CAShapeLayer()
		let bounds = box.applying(scale).applying(transform)
		boxLayer.frame = bounds
		boxLayer.cornerRadius = 10
		boxLayer.opacity = 1
		boxLayer.borderColor = UIColor.systemBlue.cgColor
		boxLayer.borderWidth = 6.0

		self.rectangleMaskLayer.addSublayer(boxLayer)
		self.sceneView.layer.addSublayer(self.rectangleMaskLayer)
	}

	private func zNormalization(anchor: ARAnchor, for detectedObjectId: String) -> ARAnchor {
		if self.anchorCount > 0 {
			let zPos = anchor.transform.columns.3.z
			self.distanceToPlane = (self.distanceToPlane * Float(self.anchorCount - 1) + zPos) / Float(self.anchorCount)
			self.anchorCount += 1
			var translation = matrix_identity_float4x4
			translation.columns.3.z = self.distanceToPlane
			let transform = simd_mul(anchor.transform, translation)
			let newAnchor = ARAnchor(name: detectedObjectId, transform: transform)
			return newAnchor
		}

		return anchor
	}

	/// Determine if the newRayCast result will produce a new anchor matching the minimum distance threshold
	/// - Parameter newResult: new rayCast result
	/// - Returns: true if the new anchor fulfils the minimum distance requirements otherwise false
	private func isNewAnchor(newResult: ARRaycastResult) -> Bool {
		let minDistanceX: Float = 0.05
		let minDistanceY: Float = 0.1
		let minDistanceZ: Float = 0.3
		var minDistance: Float = 1
		var nearestNeighbor = simd_float4x4()
		let newAnchor = newResult.worldTransform

		for oldResult in self.rayCastResults {
			let oldAnchor = oldResult.worldTransform
			//not taken into account z direction (towards camera) because that is shifted sometimes.
			let startPoint = SCNVector3(newAnchor.columns.3.x, newAnchor.columns.3.y, 0)
			let endPoint = SCNVector3(oldAnchor.columns.3.x, oldAnchor.columns.3.y, 0)
			let newDistance = startPoint.distance(vector: endPoint)
			if newDistance < minDistance {
				minDistance = newDistance
				nearestNeighbor = oldAnchor
			}
		}

		let xDist = abs(newAnchor.columns.3.x - nearestNeighbor.columns.3.x)
		let yDist = abs(newAnchor.columns.3.y - nearestNeighbor.columns.3.y)
		let zDist = abs(newAnchor.columns.3.z)

		debugPrint("xDist: ", xDist)
		debugPrint("yDist: ", yDist)
		debugPrint("zDist: ", zDist)
		if ((xDist < minDistanceX) && (yDist < minDistanceY)) || (zDist < minDistanceZ) {
			return false
		} else {
			return true
		}
	}

	func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
		guard
			let observationId = anchor.name,
			let currentObservation = self.viewModel.accurateObjects.first(where: { $0.id.uuidString == observationId })  else {
				return nil
		}

		let plane = SCNPlane(width: 0.6, height: 0.1)

		let material = SCNMaterial()
		material.isDoubleSided = true
		material.diffuse.contents = UIImage(named: "vis.png")
		material.transparencyMode = .aOne

		plane.materials = [material]

		let planeNode = SCNNode(geometry: plane)

		//rotate with respect to camera
		planeNode.rotation = SCNVector4Make(-1, 0, 0, .pi / 2)
//		planeNode.pivotOnTopLeft()

		let node = SCNNode()
		node.addChildNode(planeNode)

		let bioNode = textNode(currentObservation.text ?? "test", font: UIFont.systemFont(ofSize: 10), maxWidth: nil)
		bioNode.pivotOnTopLeft()

		bioNode.position.x += 0.05
		bioNode.position.y += 0.06

		planeNode.addChildNode(bioNode)
		return node
	}

	func textNode(_ str: String, font: UIFont, maxWidth: Int? = nil) -> SCNNode {
		let text = SCNText(string: str, extrusionDepth: 0)

		text.flatness = 0.1
		text.font = font
		text.firstMaterial?.diffuse.contents = UIColor.red

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

	/// Resets all tracking
	private func resetTracking() {
		self.rayCastResults.removeAll()
		let configuration = ARWorldTrackingConfiguration()
		configuration.planeDetection = .horizontal
		self.sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
		self.sceneView.session.run(configuration, options: [.removeExistingAnchors, .resetTracking])
		self.viewModel.stop = false
		self.setupCoachingOverlay()
		self.anchorCount = 0
	}

	/// Removes the bounding box layer
	private func removeRectangleMask() {
		self.rectangleMaskLayer.sublayers?.removeAll()
		self.rectangleMaskLayer.removeFromSuperlayer()
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
		self.sceneView.scene.rootNode.enumerateChildNodes { currentNode, _ in
			self.distanceToPlane = currentNode.simdPosition.z
			debugPrint("Distance to plane: ", self.distanceToPlane)
		}

		self.viewModel.stop = false
		self.currentBuffer = nil
		self.sessionState = .ready
		debugPrint("detected a Plane")
	}

	/// - Tag: StartOver
	func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
		self.resetTracking()
	}

	private func setupCoachingOverlay() {
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
		self.coachingOverlay.setActive(true, animated: true)

		// Most of the virtual objects in this sample require a horizontal surface,
		// therefore coach the user to find a horizontal plane.
		self.setGoal()
	}

	/// - Tag: CoachingActivatesAutomatically
	private func setActivatesAutomatically() {
		self.coachingOverlay.activatesAutomatically = true
	}

	/// - Tag: CoachingGoal
	private func setGoal() {
		self.coachingOverlay.goal = .verticalPlane
	}
}
