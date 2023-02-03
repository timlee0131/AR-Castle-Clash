/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import ARKit
import SceneKit
import UIKit

@available(iOS 14.0, *)
class ViewController: UIViewController {
//    UI ELEMENTS
    @IBOutlet var sceneView: VirtualObjectARView!
    @IBOutlet weak var addObjectButton: UIButton!
    @IBOutlet weak var blurView: UIVisualEffectView!
    @IBOutlet weak var spinner: UIActivityIndicatorView!
    @IBOutlet weak var upperControlsView: UIView!
    @IBOutlet weak var heightSlider: UISlider!{
        didSet{
            heightSlider.transform = CGAffineTransform(rotationAngle: -Double.pi/2)
        }
    }
    let coachingOverlay = ARCoachingOverlayView()
    var focusSquare = FocusSquare()
//    STATUS: DETECTED SURFACE
    lazy var statusViewController: StatusViewController = {
        return children.lazy.compactMap({ $0 as? StatusViewController }).first!
    }()
//    MORE UI ELEMENTS, FOR PLANE
    @IBOutlet weak var planeLockBtn: UIButton!
    var plane_locked = false
    var plane_added = false
    var groundHeight = 0.0
    @IBAction func PlaneLock(_ sender: Any) {
        plane_locked = true
        //planeLockBtn.isEnabled = false
        planeLockBtn.isHidden = true
        addObjectButton.isHidden = false
        
    }
    var height_offset = Float(0.0)
    @IBAction func setHeight(_ sender: Any) {
        height_offset = heightSlider.value
    }


//    MENU ITEMS FOR LEGO PIECES
    var objectsViewController: VirtualObjectSelectionViewController?
    
//  GESTURE MANIPULATION
    lazy var virtualObjectInteraction = VirtualObjectInteraction(sceneView: sceneView, viewController: self)
    
//  LOAD VIRTUAL OBJECTS TO WORLD
    let virtualObjectLoader = VirtualObjectLoader()
    
//  RESTART AVAILABLE IF LOST FOCUS OF PLANE
    var isRestartAvailable = true
    
//  QUEUE TO ADD/REMOVE NODES FROM SCENE
    let updateQueue = DispatchQueue(label: "com.example.apple-samplecode.arkitexample.serialSceneKitQueue")
    
//  RETURN SCENEVIEW SESSION
    var session: ARSession {
        return sceneView.session
    }
    
    // hand gesture stuff
    var currentBuffer: CVPixelBuffer?
    var handPoseRequest = VNDetectHumanHandPoseRequest()
    var lastObjectPinched:VirtualObject?
    override func viewDidLoad() {
        super.viewDidLoad()
        handPoseRequest.maximumHandCount = 1
        addObjectButton.isHidden = true
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        setupCoachingOverlay()
        sceneView.scene.rootNode.addChildNode(focusSquare)

//      RESTART GAME IF BUTTON PRESSED
        statusViewController.restartExperienceHandler = { [unowned self] in
            self.restartExperience()
        }
//      SET UP TAP GESTURE RECOGNIZER
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(showVirtualObjectSelectionViewController))
        tapGesture.delegate = self
        sceneView.addGestureRecognizer(tapGesture)
    }

//    CONFIGURATION STUFF
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        resetTracking()
    }
    
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    override func viewWillAppear(_ animated: Bool){
        super.viewWillAppear(animated)
        self.sceneView.debugOptions = [SCNDebugOptions.showPhysicsShapes]
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
    }

//  SESSION FUNCTIONS
    func resetTracking() {
        virtualObjectInteraction.selectedObject = nil
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
//        if #available(iOS 12.0, *) {
//            configuration.environmentTexturing = .automatic
//        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        statusViewController.scheduleMessage("FIND A SURFACE TO PLACE AN OBJECT", inSeconds: 7.5, messageType: .planeEstimation)
        
        plane_locked = false
        plane_added = false
        planeLockBtn.isHidden = false
        addObjectButton.isHidden = true
    }

    // MARK: - Focus Square
    func updateFocusSquare(isObjectVisible: Bool) {
        if isObjectVisible || coachingOverlay.isActive {
            focusSquare.hide()
        } else {
            focusSquare.unhide()
            statusViewController.scheduleMessage("TRY MOVING LEFT OR RIGHT", inSeconds: 5.0, messageType: .focusSquare)
        }
        
        // Perform ray casting only when ARKit tracking is in a good state.
        if let camera = session.currentFrame?.camera, case .normal = camera.trackingState,
            let query = sceneView.getRaycastQuery(),
            let result = sceneView.castRay(for: query).first {
            
            updateQueue.async {
                self.sceneView.scene.rootNode.addChildNode(self.focusSquare)
                self.focusSquare.state = .detecting(raycastResult: result, camera: camera)
            }
            if !coachingOverlay.isActive && plane_locked {
                addObjectButton.isHidden = false
            }
            statusViewController.cancelScheduledMessage(for: .focusSquare)
        } else {
            updateQueue.async {
                self.focusSquare.state = .initializing
                self.sceneView.pointOfView?.addChildNode(self.focusSquare)
            }
            addObjectButton.isHidden = true
            objectsViewController?.dismiss(animated: false, completion: nil)
        }
    }
    
    // MARK: - Error handling
    
    func displayErrorMessage(title: String, message: String) {
        // Blur the background.
        blurView.isHidden = false
        
        // Present an alert informing about the error that has occurred.
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.blurView.isHidden = true
            self.resetTracking()
        }
        alertController.addAction(restartAction)
        present(alertController, animated: true, completion: nil)
    }

    
}


