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
//        configuration.worldAlignment = .gravity

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
          let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -sceneView.bounds.height)
          let scale = CGAffineTransform.identity.scaledBy(x: sceneView.bounds.width, y: sceneView.bounds.height)
			// Get the affine transform to convert between normalized image coordinates and view coordinates
//			let fromCameraImageToViewTransform = currentFrame.displayTransform(for: .portrait, viewportSize: viewportSize)
			// The observation's bounding box in normalized image coordinates
			let boundingBox = observation.boundingBox

            /*
			// Transform the latter into normalized view coordinates
			let viewNormalizedBoundingBox = boundingBox.applying(fromCameraImageToViewTransform)
			// The affine transform for view coordinates
			let t = CGAffineTransform(scaleX: viewportSize.width, y: viewportSize.height)
			// Scale up to view coordinates
			let viewBoundingBox = viewNormalizedBoundingBox.applying(t)

			let midPoint = CGPoint(x: viewBoundingBox.midX, y: viewBoundingBox.midY)

//          Visiulize Center of bounding Boxes
            
            let boxLayer = CAShapeLayer()
            let bounds = boundingBox.applying(scale).applying(transform)
            boxLayer.frame = bounds
            boxLayer.cornerRadius = 10
            boxLayer.opacity = 1
            boxLayer.borderColor = UIColor.systemBlue.cgColor
            boxLayer.borderWidth = 6.0

            self.rectangleMaskLayer.addSublayer(boxLayer)
            
            let midPoint2 = CGPoint(x: bounds.midX, y: bounds.midY)
            let circleLayer = CAShapeLayer()
            circleLayer.path = UIBezierPath(ovalIn: CGRect(x: midPoint2.x, y: midPoint2.y, width: 20, height: 20)).cgPath
            circleLayer.fillColor = UIColor.red.cgColor
            self.rectangleMaskLayer.addSublayer(circleLayer)
*/
            let bounds = boundingBox.applying(scale).applying(transform)
            let midPoint2 = CGPoint(x: bounds.midX, y: bounds.midY)
			let query = sceneView.raycastQuery(from: midPoint2, allowing: .estimatedPlane, alignment: .any)

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

            let rotate = simd_float4x4(SCNMatrix4MakeRotation(currentFrame.camera.eulerAngles.y, 0, 1, 0))
            let rotateAnchor = simd_mul(result.worldTransform, rotate)
            let anchor = ARAnchor(name: observation.text ?? "nop", transform: rotateAnchor)
            anchor.box = bounds
			if addedAnchors.contains(observation) == false {
				sceneView.session.add(anchor: anchor)
				self.addedAnchors.insert(observation)
			}

			// detectRemoteControl = false
		}
        view.layer.insertSublayer(self.rectangleMaskLayer, at: 1)
	}

	private func removeRectangleMask() {
        self.rectangleMaskLayer.sublayers?.removeAll()
        self.rectangleMaskLayer.removeFromSuperlayer()
	}

	func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
	}

    enum CError: Error {
        case CurrentFrameError
    }

	func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let plane = SCNPlane(width: (anchor.box.width / 5000), height: (anchor.box.height / 5000))
//        let plane = SCNPlane(width: 0.015, height: 0.01)
        plane.firstMaterial?.diffuse.contents = UIColor.red

        let planeNode = SCNNode(geometry: plane)
        //rotate with respect to camera

        planeNode.rotation = SCNVector4Make(-1, 0, 0, .pi / 2)
        planeNode.pivotOnTopCenter()

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
    @IBAction private func resetTrackingButton(_ sender: UIButton) {
        resetTracking()
    }
    func resetTracking() {
        addedAnchors = Set<DetectedObject>()
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration, options: [.removeExistingAnchors, .resetTracking])
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
