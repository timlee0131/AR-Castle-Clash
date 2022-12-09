//
//  ViewController.swift
//  ARgallery
//
//  Created by zhongyuan liu on 12/7/22.
//

//1...10 FIRST FUNCTION SET: (most removed)setup ARKit session to implement image tracking, plane recognition, placement of custom images(from collection view)
//A...Z SECOND FUNCTION SET: add, delete, move around nodes without using AR session(scene delegate, session delegate)
//a...z: THIRD FUNCTION SET: integrate coreML, vision, and AR: use Vision (algorithms) to classify elements of image frames, AR classifies elements in video frames for real-time feedback


import UIKit
import ARKit
import Vision

class ViewController: UIViewController {
    
    @IBOutlet var arScene: ARSCNView!
    @IBOutlet var errorView: UIView!
    @IBOutlet var errorLabel: UILabel!
    
    //a, b: create image analysis for coreml model
    private lazy var visionCoreMLRequest: VNCoreMLRequest = {
        //a. lazy load visioncoreml request to create property only when needed
        do{
            //a1. do-catch, attempt to load the MLModel
            let mlModel = try MLModel(contentsOf: Gesture.urlOfModelInThisBundle)
            let visionModel = try VNCoreMLModel(for: mlModel)
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                self.handleObservationClassification(request: request, error: error)
            }
            //a2. the typical scaling method for ML models(built to recognize square bound boxes)
            request.imageCropAndScaleOption = .centerCrop
            return request
        }catch{
            fatalError(error.localizedDescription)
        }
    }()
    
    //c, d, e: classify camera's pixel buffer from AR video frame
    //c1. cvPixelBuffer property references captured image from ARFrame for image analysis, also used to handle vision requests
    private var cvPixelBuffer: CVPixelBuffer?
    private var requestHandler: VNImageRequestHandler?{
        //c2. load pixelBuffer into cvPixelBuffer
        guard let pixelBuffer = cvPixelBuffer,
              //c3. initialize image property orientation(right image orientation for better classification)
              let orientation = CGImagePropertyOrientation(rawValue: UInt32(UIDevice.current.orientation.rawValue))
        else{return nil}
        //c4. return image request handler(used by Vision to classify image)
        return VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
    }
    
    //f, g: control ship model with hand gesture classification result
    private let modelNode: SCNReferenceNode = {
        //g1. add model upon plane detection
        guard let url = Bundle.main.url(
            forResource: "ship", withExtension: "scn"),
              let referenceNode = SCNReferenceNode(url: url)
        else { fatalError("failed to load model.") }
        referenceNode.load()
        return referenceNode
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //1. set up ARKit session: make viewController delegate for both scene and scene session
        //1a. scene delegate responds to specific events, ie when new content added to scene; debug options will show feature points in world(to find place with enough feature points to detect a plane)
        //1b. session delegate does more fine grained control of scene content(used a lot to build your own rendering); since we are using sceneKit, the only reason we adopt sessiondelegate is to respond to changes in session's tracking state
        arScene.delegate = self
        arScene.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        arScene.session.delegate = self
        
        //1c. A-E methods: configure scene lighting; add, delete, move around nodes in ar scene
        configureLighting()
        addTapGestureToScene()
        addPanGestureToScene()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        //2. configure ARSession that is part of the scene to begin using ARKit; set things up right before viewcontroller becomes visible
        super.viewWillAppear(animated)
    
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        
        //configuration.detectionImages = referenceImages
        //2c. pass configuration to arsession run() method
        arScene.session.run(configuration, options: [])
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        //3. wasteful to keep ar session alive when view is not visible anymore, so pause session if app is closed or if view controller that contains ar scene becomes invisible
        super.viewWillDisappear(animated)
        arScene.session.pause()
    }
    
    //------------------SECOND FUNCTION SET-------------------------------------
    //------------------ADD, DELETE, MOVE AROUND MODELS AND BOXES---------------
    func addBox(x: Float = 0, y: Float = 0, z: Float = -0.5){
        //A. add a box to scene
        let box = SCNBox(width: 0.05, height: 0.05, length: 0.05, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = UIColor.orange
        box.firstMaterial?.transparency = 0.8
        
        let boxNode = SCNNode()
        boxNode.geometry = box
        boxNode.position = SCNVector3(x, y, z)
        
         //physicsbody box not a great idea, too much movement, difficult to stack
         let physicsBody = SCNPhysicsBody(type: .static, shape: nil)
         physicsBody.restitution = 1.5
         boxNode.physicsBody = physicsBody
         
        arScene.scene.rootNode.addChildNode(boxNode)
    }
    
    @IBAction func addModelButtonPressed(_ sender: Any) {
        //A1. button pressed, add ship model to scene
        addBox()
    }
    
    func addSCN(x: Float = 0, y: Float = -0.5, z: Float = -1){
        //A1. add ship.scn to scene
        guard let modelScene = SCNScene(named: "ship.scn"),
              let modelNode = modelScene.rootNode.childNode(withName: "ship", recursively: true)
        else{return}
        
        modelNode.position = SCNVector3(x, y, z)
        arScene.scene.rootNode.addChildNode(modelNode)
    }
    
    func configureLighting(){
        //A3. configure lighting for models
        arScene.autoenablesDefaultLighting = true
        arScene.automaticallyUpdatesLighting = true
    }
    
    func addTapGestureToScene(){
        //B. add tap gesture recognition
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(ViewController.didTap(withGestureRecognizer:)))
        arScene.addGestureRecognizer(tapGestureRecognizer)
    }
    
    @objc func didTap(withGestureRecognizer recognizer: UIGestureRecognizer){
        //C. get user tap location relative to scene view and hit test to see if you tapped on any nodes
        let tapLocation = recognizer.location(in: arScene)
        let hitTestResults = arScene.hitTest(tapLocation)
        
        //unwrap first node from hit test, remove first node we tapped on
        guard let node = hitTestResults.first?.node
        else {
            //...or add a bunch of boxes to scene
            
            //specify featurePoint result type(search for objects/surfaces/features)
            let hitTestResults = arScene.hitTest(tapLocation, types: .featurePoint)
            //unwrap first hit test result
            if let hitTestResult = hitTestResults.first {
                //matrix transformation, get xyz real-world coordinates using the extension
                let translation = hitTestResult.worldTransform.translation
                //tap on a detected feature point to add new box
                addBox(x: translation.x, y: translation.y, z: translation.z)
            }
            return
        }
        node.removeFromParentNode()
    }
    
    @objc func addPanGestureToScene(){
        //D. add pan gesture recognition to scene
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(didPan(withGestureRecognizer:)))
        arScene.addGestureRecognizer(panGestureRecognizer)
    }
    @objc func didPan(withGestureRecognizer recognizer: UIPanGestureRecognizer){
        //E. detect a node and feature point, pan node to new feature point
        switch recognizer.state{
        case .began:
            print("begin panning")
        case .changed:
            print("pan changed")
            let tapLocation = recognizer.location(in: arScene)
            //hit test for node, hit test for feature point
            //if both node and feature point exists, set node's world position to the feature point's world position
            let hitTestResults = arScene.hitTest(tapLocation)
            guard let node = hitTestResults.first?.node,
                  let hitTestResultWithFeaturePoints = arScene.hitTest(tapLocation, types: .featurePoint).first
            else{
                return
            }
            let worldTransform = SCNMatrix4(hitTestResultWithFeaturePoints.worldTransform)
            node.setWorldTransform(worldTransform)
        case .ended:
            print("end panning")
        default:
            break
        }
    }
    
    //------------------THIRD FUNCTION SET-------------------------------------
    //------------------INTEGRATE COREML AND VISION----------------------------
    //a, b: create image analysis request for coreml model
    
    //b. instruction label to user(open hand, close fist, confidence)
    @IBOutlet weak var instructionLabel: UILabel!
    
    private func handleObservationClassification(request: VNRequest, error: Error?){
        //b1. cast request results as array of VNClassificationObservation; each observation is classification model with identifier + confidence
        guard let observations = request.results as? [VNClassificationObservation],
              //b2. take first observation with 80%+ confidence
              let observation = observations.first(
                where: {$0.confidence > 0.8})
        else{return}
        
        //b3. observation identifier and confidence
        let identifier = observation.identifier
        let confidence = observation.confidence
        
        //b4. update user about confidence and classification
        var text = "Show hand."
        if identifier.lowercased().contains("five"){
            text = "open hand confidence: \(confidence)"
            //f4. move model forward
            self.moveModel(isForward: true)
        } else if identifier.lowercased().contains("fist"){
            text = "closed fist confidence: \(confidence)"
            //f4. move model backward
            self.moveModel(isForward: false)
        }
        DispatchQueue.main.async {
            self.instructionLabel.text = text
        }
    }
    
    //c, d, e: classify camera pixel buffer from AR video frame
    private func classifyFrame(_ frame: ARFrame){
        //d. take ARFrame from scene's ARSession
        //d1. update pixel buffer from current frame
        cvPixelBuffer = frame.capturedImage
        //d2. run classification on background thread(don't block main thread); device runs 60-120 fps, running classification for every frame is just going to drain battery
        DispatchQueue.global(qos: .background).async {
            [weak self] in
            guard let self = self
            else{return}
            //d3. do the visionCoreMLRequst
            do{
                defer{
                    //d4. while there is ongoing request, no other pixelbuffer will be requested for classification
                    self.cvPixelBuffer = nil
                }
                try self.requestHandler?.perform([self.visionCoreMLRequest])
            }catch{
                print(error.localizedDescription)
            }
        }
    }
    
    //f: control model with hand gesture classification result
    //f1. decide forward or backward movement
    private var isMoving = false
    private var isModelAdded = false
    
    private func moveModel(isForward: Bool){
        //f2. don't queue another animation if model is still moving
        guard !isMoving else{return}
        isMoving = true
        //f3. forward 6cm or back 5cm
        let z: CGFloat = isForward ? 0.06 : -0.06
        let moveAction = SCNAction.moveBy(x: 0, y: 0, z: z, duration: 1)
        
        let physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        physicsBody.restitution = 1.5
        modelNode.physicsBody = physicsBody
        
        modelNode.runAction(moveAction){
            self.isMoving = false
        }
    }
    
}

extension float4x4{
    //used in C for the addition of new boxes upon tap
    //transforms matrix to float3; transforms feature point coordinates to real world coordinates
    var translation: SIMD3<Float>{
        let translation = self.columns.3
        return SIMD3<Float>(translation.x, translation.y, translation.z)
    }
}

extension UIColor {
    public class var customLightBlue: UIColor {
        return UIColor(red: 99/255, green: 225/255, blue: 254/255, alpha: 0.85)
    }
}


//------------------FIRST FUNCTION SET-------------------------------------
//------------------IMAGE TRACKING AND PLACEMENT---------------------------
extension ViewController: ARSessionDelegate{
    //4. set up sessionDelegate to respond to changes in tracking state
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState{
        case .normal:
            errorView.isHidden = true
        case .notAvailable:
            errorLabel.text = "world tracking not available right now"
        case let .limited(reason):
            errorView.isHidden = false
            switch reason {
            case .initializing:
                errorLabel.text = "session initializing"
            case .relocalizing:
                errorLabel.text = "session resuming after interruption"
            case .excessiveMotion:
                errorLabel.text = "device is moving too much!"
            case .insufficientFeatures:
                errorLabel.text = "not enough features in the scene"
            @unknown default:
                fatalError()
            }
        }
    }
    //c, d, e: classify camera pixel buffer from AR video frame
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        //e. pass frame explicitly
        guard cvPixelBuffer == nil else{return}
        classifyFrame(frame)
    }
}

extension ViewController: ARSCNViewDelegate{
    //5. set up scenedelegate to respond to scene events: when image is identified, trigger addition of a new SCNNode
    
    //5a. renderer() is called on scenedelegate when a new scnnode is added to view;
    //ie when AR session finds flat surface, it adds node for ARPlaneAnchor,
    //when it detects an image you are tracking, node for ARImageAnchor is added
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor{
            drawPlane(node, for: planeAnchor)
        }else{return}
        
    }
    
    //g. method triggered when new anchor added on scene
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors{
            //only one model in scene
            guard !isModelAdded,
                  anchor is ARPlaneAnchor else {continue}
            //add instruction label
            isModelAdded = true
            instructionLabel.isHidden = false
            //position model with respoect to anchor
            modelNode.simdTransform = anchor.transform
            //add model to scene
            DispatchQueue.main.async {
                self.arScene.scene.rootNode.addChildNode(self.modelNode)
            }
        }
    }
    //8a. helper method to more easily visualize planes
    //take node and anchor to create new SCNPlane, and put SCNPlane at exact position where plane anchor was found
    func drawPlane(_ node: SCNNode, for planeAnchor: ARPlaneAnchor){
        let width = CGFloat(planeAnchor.extent.x)
        let height = CGFloat(planeAnchor.extent.z)
        let plane = SCNPlane(width: width, height: height)
        
        plane.firstMaterial?.diffuse.contents = UIColor.customLightBlue
        var planeNode = SCNNode(geometry: plane)
        
        let x = CGFloat(planeAnchor.center.x)
        let y = CGFloat(planeAnchor.center.y)
        let z = CGFloat(planeAnchor.center.z)
        planeNode.position = SCNVector3(x,y,z)
        planeNode.eulerAngles.x = -.pi / 2
        
        //make plane a static physics body
        update(&planeNode, withGeometry: plane, type: .static)
        
        node.addChildNode(planeNode)
    }
    
    func update(_ node: inout SCNNode, withGeometry geometry: SCNGeometry, type: SCNPhysicsBodyType) {
        let shape = SCNPhysicsShape(geometry: geometry, options: nil)
        let physicsBody = SCNPhysicsBody(type: type, shape: shape)
        node.physicsBody = physicsBody
        
    }
    
}
