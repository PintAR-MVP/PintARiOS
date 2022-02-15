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
	private var addedAnchors = Set<ARAnchor>()
	private var sessionState: SessionState = .settingUp
	private var distanceToPlane = Float()
	private var anchorCount = Int()
    private var detectedAngles = [DetectedAngle]()

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
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		self.viewportSize = sceneView.frame.size
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

        self.addedAnchors.removeAll()
		// Create a session configuration
		let configuration = ARWorldTrackingConfiguration()
		configuration.planeDetection = .horizontal

		// Run the view's session
		self.sceneView.session.run(configuration, options: [.removeExistingAnchors, .resetTracking])
        // Set up coaching overlay.
        self.setupCoachingOverlay()
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

			let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -sceneView.bounds.height)
			let scale = CGAffineTransform.identity.scaledBy(x: sceneView.bounds.width, y: sceneView.bounds.height)
			let bounds = observation.boundingBox.applying(scale).applying(transform)
			let midPoint = CGPoint(x: bounds.midX, y: bounds.midY)

            let boxLayer = CAShapeLayer()
            boxLayer.frame = bounds
            boxLayer.cornerRadius = 10
            boxLayer.opacity = 1
            boxLayer.borderColor = UIColor.clear.cgColor
            boxLayer.borderWidth = 6.0

            self.rectangleMaskLayer.addSublayer(boxLayer)

            self.sceneView.layer.addSublayer(self.rectangleMaskLayer)
			let query = self.sceneView.raycastQuery(from: midPoint, allowing: .estimatedPlane, alignment: .vertical)
			guard
				let resultQuery = query,
				let result = self.sceneView.session.raycast(resultQuery).first else {
					debugPrint("missed")
					continue
			}

            self.viewModel.stop = self.addedAnchors.count > 2

			let anchor = ARAnchor(name: observation.id.uuidString, transform: result.worldTransform)
//            anchor = zNormalization(anchor: anchor)

            if observation.highestScoreProduct == nil, isNewAnchor(newResult: result) {
                // Observe API response and add
                observation.$highestScoreProduct
                    .sink(receiveValue: { value in
                        if value != nil {
                            self.sceneView.session.add(anchor: anchor)
                            self.addedAnchors.insert(anchor)
                        }
                    }).store(in: &cancellableSet)
            } else if self.isNewAnchor(newResult: result) == true {
                let visAngle = findVisAngle(newAnchor: anchor)
                detectedAngles.append(DetectedAngle(id: observation.id, visAngle: visAngle))
				self.sceneView.session.add(anchor: anchor)
				self.addedAnchors.insert(anchor)
			} else {
				debugPrint("Drop anchor because it is to close to another anchor")
			}
		}
	}

    func zNormalization(anchor: ARAnchor) -> ARAnchor {
        if self.anchorCount > 0 {
            let zPos = anchor.transform.columns.3.z
            self.distanceToPlane = (self.distanceToPlane * Float(self.anchorCount - 1) + zPos) / Float(self.anchorCount)
            self.anchorCount += 1
            var translation = matrix_identity_float4x4
            translation.columns.3.z = self.distanceToPlane
            let transform = simd_mul(anchor.transform, translation)
            return ARAnchor(transform: transform)
        }
        return anchor
    }

	func isNewAnchor(newResult: ARRaycastResult) -> Bool {
		let minDistanceX: Float = 0.05
		let minDistanceY: Float = 0.1
		let minDistanceZ: Float = 0.2
		var minDistance: Float = 1
		var nearestNeighbor = simd_float4x4()
		let newAnchor = newResult.worldTransform
		var nearNeighbor = false

		for oldResult in self.addedAnchors {
			let oldAnchor = oldResult.transform
			//not taken into account z direction (towards camera) because that is shifted sometimes.
			let oldAnchorX = oldAnchor.columns.3.x
			let oldAnchorY = oldAnchor.columns.3.y
            if (oldAnchorX != 0) && (oldAnchorY != 0) {
                let startPoint = SCNVector3(newAnchor.columns.3.x, newAnchor.columns.3.y, 0)
                let endPoint = SCNVector3(oldAnchorX, oldAnchorY, 0)
                let newDistance = startPoint.distance(vector: endPoint)
                if newDistance < minDistance {
                    minDistance = newDistance
                    nearestNeighbor = oldAnchor
                    nearNeighbor = true
                }
            }
        }

		guard nearNeighbor else {
			return true
		}

		let xDist = abs(newAnchor.columns.3.x - nearestNeighbor.columns.3.x)
		let yDist = abs(newAnchor.columns.3.y - nearestNeighbor.columns.3.y)
		let zDist = abs(newAnchor.columns.3.z)

		debugPrint("xDist: ", xDist)
		debugPrint("yDist: ", yDist)
		debugPrint("zDist: ", zDist)
		if ((xDist < minDistanceX) && (yDist < minDistanceY)) || (zDist < minDistanceZ) {
			debugPrint("nearest neighbor x: ", nearestNeighbor.columns.3.x)
			debugPrint("nearest neighbor y: ", nearestNeighbor.columns.3.y)
			return false
		} else {
			return true
		}
	}
    
    func findVisAngle(newAnchor: ARAnchor) -> Int {
        // Return quarant which is best to visualize (default: 1 - top-right)
        var visQuadrantList: [Double] = [0, 0, 0, 0] //top-left, top-right, bottom-right, bottom-left
        let newAnchorX = newAnchor.transform.columns.3.x
        let newAnchorY = newAnchor.transform.columns.3.y
        if self.addedAnchors.isEmpty {
            debugPrint("No anchors yet, default")
            return 1
        } else {
            for oldAnchor in self.addedAnchors {
                //not taken into account z direction (towards camera) because that is shifted sometimes.
                let oldAnchorX = oldAnchor.transform.columns.3.x
                let oldAnchorY = oldAnchor.transform.columns.3.y
                if(oldAnchorX != 0) && (oldAnchorY != 0) {
                    let startPoint = SCNVector3(newAnchorX, newAnchorY, 0)
                    let endPoint = SCNVector3(oldAnchorX, oldAnchorY, 0)
                    let distance = startPoint.distance(vector: endPoint)
                    if distance < 0.7 {
                        guard let currentObservation = self.detectedAngles.first(where: { $0.id.uuidString == oldAnchor.name }) else {
                            debugPrint("Could not load current visAngle")
                            return 1
                        }

                        let oldVisAngle = currentObservation.visAngle
                        let intersectQuadrantList = isVisOverlapping(visQuadrant: oldVisAngle, newAnchorX: Double(newAnchorX), newAnchorY: Double(newAnchorY), oldAnchorX: Double(oldAnchorX), oldAnchorY: Double(oldAnchorY))
                        visQuadrantList = zip(visQuadrantList, intersectQuadrantList).map(+)
                    }
                }
                debugPrint(newAnchorX, newAnchorY, oldAnchorX, oldAnchorY, visQuadrantList)
            }
            if let maxValue = visQuadrantList.min(), let index = visQuadrantList.firstIndex(of: maxValue) {
                debugPrint("Best Quadrant for vis is: ", index)
                return index
            } else {
                debugPrint("Couldn't find optimal vis Quadrant, default")
                return 1
            }
        }
    }

    func isVisOverlapping(visQuadrant: Int, newAnchorX: Double, newAnchorY: Double, oldAnchorX: Double, oldAnchorY: Double) -> [Double] {
        // Calculate Intersection between Visualisation of old and possible new Anchors
        var visQuadrantList: [Double] = [0, 0, 0, 0] //top-left, top-right, bottom-right, bottom-left
        let oldQuadrants = makeQuadrants(x: oldAnchorX, y: oldAnchorY)
        let newQuadrants = makeQuadrants(x: newAnchorX, y: newAnchorY)

        for (i, newQuadrant) in newQuadrants.enumerated() {
            visQuadrantList[i] += newQuadrant.rectIntersectionInPerc(r: oldQuadrants[visQuadrant])
        }
        return visQuadrantList
    }

     func makeQuadrants(x: Double, y: Double) -> [CGRect] {
         // making array of four CGRects where a visualisation is possible (top-left, top-right, bottom-right, bottom-left)
         let w = 0.30
         let h = 0.05
         let space = 0.04
         let topleft = CGRect(x: -w + x, y: y + space, width: w, height: h)
         let topright = CGRect(x: x, y: y + space, width: w, height: h)
         let bottomright = CGRect(x: x, y: -h + y - space, width: w, height: h)
         let bottomleft = CGRect(x: -w + x, y: -h + y - space, width: w, height: h)
         return [topleft, topright, bottomright, bottomleft]
     }

	func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard
            let observationId = anchor.name,
            let currentObservation = self.viewModel.accurateObjects.first(where: { $0.id.uuidString == observationId }) else {
                return nil
        }

        let visAngle = self.detectedAngles.first(where: { $0.id.uuidString == observationId })?.visAngle
        let plane = SCNPlane(width: 0.6, height: 0.1)
        let material = SCNMaterial()
        material.isDoubleSided = true
        switch visAngle {
        case 0:
            material.diffuse.contents = UIImage(named: "vis1.png")
        case 1:
            material.diffuse.contents = UIImage(named: "vis2.png")
        case 2:
            material.diffuse.contents = UIImage(named: "vis3.png")
        case 3:
            material.diffuse.contents = UIImage(named: "vis4.png")
        default:
            debugPrint("found no vis angle")
            material.diffuse.contents = UIImage(named: "vis2.png")
        }

        material.transparencyMode = .aOne
        plane.materials = [material]
        let planeNode = SCNNode(geometry: plane)

        //rotate with respect to camera
        planeNode.rotation = SCNVector4Make(-1, 0, 0, .pi / 2)

        let node = SCNNode()
        node.addChildNode(planeNode)

        let bioNode = textNode(currentObservation.highestScoreProduct?.name ?? "Unknown", font: UIFont.systemFont(ofSize: 10), maxWidth: nil)
        bioNode.pivotOnTopLeft()
        switch visAngle {
        case 0:
            bioNode.position.x -= 0.25
            bioNode.position.y += 0.06
        case 1:
            bioNode.position.x += 0.05
            bioNode.position.y += 0.06
        case 2:
            bioNode.position.x += 0.05
            bioNode.position.y -= 0.017
        case 3:
            bioNode.position.x -= 0.25
            bioNode.position.y -= 0.017
        default:
            debugPrint("found no vis angle")
        }
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
		self.addedAnchors.removeAll()
		let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
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
	func setGoal() {
		self.coachingOverlay.goal = .tracking
	}
}
