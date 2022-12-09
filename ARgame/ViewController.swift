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
    //    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var errorView: UIView!
    @IBOutlet var errorLabel: UILabel!
    
    /*
     //i. ar resource group images, for display of information plane upon detection
     let imageDescriptions = ["cannonfire": "a castle offense weapon", "castle1": "a castle defense", "castle2": "a castle defense"]
     //ii. gallery images, in collectionview
     let images: [String] = ["img_1", "img_2", "img_3", "img_4", "img_5", "img_6", "img_7", "img_8"]
     //iii. collection view cell(custom image) selection results in image anchor on scene, and will be stored as unique uuid along with the proper image: custom image will then be displayed on scene
     var imageNodes = [UUID:UIImage]()
     */
    
    
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
        
        /*
         //collectionView no longer used
         collectionView.delegate = self
         collectionView.dataSource = self
         */
        
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
        
        /*
         //2a. read reference images from app bundle
         let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "CastleComponents", bundle: Bundle.main)
         //2b. create ARWorldTrackingConfiguration(tracks device orientation + user movement), configure to track horizontal + vertical planes + reference images
         */
        
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
    
    /*
     //used for 7: adding new image anchor to worldmap
     func storeWorldMap() {
     arScene.session.getCurrentWorldMap { worldMap, error in
     guard let map = worldMap
     else { return }
     
     let data = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
     UserDefaults.standard.set(data, forKey: "ARgame.worldmap")
     }
     }
     */
    
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
//         boxNode.name = boxNodeName
         
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
        
        /*
         //check if anchor that was discovered is an imageanchor, add image anchor
         if let imageAnchor = anchor as? ARImageAnchor{
         placeImageInformation(withNode: node, for: imageAnchor)
         
         //custom imagenode added to scene
         } else if let customImage = imageNodes[anchor.identifier]{
         placeCustomImage(customImage, withNode: node)
         
         //if planeanchor discovered, visualize plane
         } else if let planeAnchor = anchor as? ARPlaneAnchor{
         drawPlane(node, for: planeAnchor)
         }
         */
        
        if let planeAnchor = anchor as? ARPlaneAnchor{
            drawPlane(node, for: planeAnchor)
        }else{return}
        
    }
    /*
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        
        if let planeAnchor = anchor as? ARPlaneAnchor,
           var planeNode = node.childNodes.first,
           let plane = planeNode.geometry as? SCNPlane{
            
            let planeWidth = CGFloat(planeAnchor.extent.x)
            let planeHeight = CGFloat(planeAnchor.extent.z)
            plane.width = planeWidth
            plane.height = planeHeight
            
            let x = CGFloat(planeAnchor.center.x)
            let y = CGFloat(planeAnchor.center.y)
            let z = CGFloat(planeAnchor.center.z)
            planeNode.position = SCNVector3(x, y, z)
            
            update(&planeNode, withGeometry: plane, type: .static)
        }
        else{return}
        
    }
     */
    
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
    
    /*
     
     //5b. when scene detects image you are tracking, display image info
     func placeImageInformation(withNode node: SCNNode, for anchor: ARImageAnchor){
     let referenceImage = anchor.referenceImage
     //create instance of SCNplane
     let infoPlane = SCNPlane(width: 15, height: 10)
     infoPlane.firstMaterial?.diffuse.contents = UIColor.white
     infoPlane.firstMaterial?.transparency = 0.5
     infoPlane.cornerRadius = 0.5
     //add plane to SCNNode, position plane above image, rotate a bit to make it nice looking
     let infoNode = SCNNode(geometry: infoPlane)
     infoNode.localTranslate(by: SCNVector3(0, 10, -referenceImage.physicalSize.height / 2 + 0.5))
     infoNode.eulerAngles.x = -.pi / 4
     //?? is nil coalescing operator, if referenceImage.name is nil then "castlewall" is returned
     let textGeometry = SCNText(string: imageDescriptions[referenceImage.name ?? "castlewall"], extrusionDepth: 0.2)
     textGeometry.firstMaterial?.diffuse.contents = UIColor.red
     textGeometry.font = UIFont.systemFont(ofSize: 1.3)
     textGeometry.isWrapped = true
     textGeometry.containerFrame = CGRect(x: -6.5, y: -4, width: 13, height: 8)
     //create textnode
     let textNode = SCNNode(geometry: textGeometry)
     node.addChildNode(infoNode)
     infoNode.addChildNode(textNode)
     }
     
     //8. helper methods to place custom image in scene
     func placeCustomImage(_ image: UIImage, withNode node: SCNNode){
     let plane = SCNPlane(width: image.size.width/5000, height: image.size.height/5000)
     plane.firstMaterial?.diffuse.contents = image
     
     //made a bandaid fix here, because matrix transformation in collectionView hitTest(7.1) resulting in node position(0, 0, 0) always; anchor position getting rounded to zero
     let imageNode = SCNNode(geometry: plane)
     imageNode.position = SCNVector3(x: 0, y: 0, z: -6)
     node.addChildNode(imageNode)
     }
     */
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

/*
 extension ViewController: UICollectionViewDelegate, UICollectionViewDataSource{
 
 //6. add protocol stubs for collectionview
 func numberOfSections(in collectionView: UICollectionView) -> Int {
 return 1
 }
 
 func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
 return images.count
 }
 func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
 let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CollectionCell", for: indexPath)
 
 if let imageCell = cell as? CollectionCell{
 imageCell.imageView?.image = UIImage(named: images[indexPath.row])
 }
 return cell
 }
 
 //7. implement method to respond to user tapping on collection view item
 //there is problem with matrix transformation, anchor always stores position as (0, 0, 0); currently, the only function of this method is to pass on imageNode
 func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
 //take current position of user in environment and insert new ARAnchor that corresponds to location where new item should be added
 
 //7.1 get camera from current frame in AR session, will be used later to determine user location in scene
 guard let camera = arScene.session.currentFrame?.camera
 else{return}
 //7.2 hit test to see if any horizontal/vertical planes detected in scene;
 let hitTestResult = arScene.hitTest(CGPoint(x: 0.5, y: 0.5), types:[.existingPlane])
 let firstVerticalPlane = hitTestResult.first(where: {result in
 guard let planeAnchor = result.anchor as? ARPlaneAnchor
 else{return false}
 return planeAnchor.alignment == .vertical
 })
 
 
 //7.3 location of every ARAnchor is represented as transformation from world origin, so now determine the right transformation to apply- in order to position the new image
 //world origin is where ar session first activated
 //create default translation, adjust z value(so object is in front of user or against nearest vertical plane)
 var translation = matrix_identity_float4x4
 translation.columns.3.z = -Float(firstVerticalPlane?.distance ?? -5)
 //get current user position(thru camera)
 //adjust camera rotation, because camera doesn't follow device orientation(camera assumes that x axis is along length of device)
 let cameraTransform = camera.transform
 let rotation = matrix_float4x4(cameraAdjustmentMatrix)
 let transform = matrix_multiply(cameraTransform, matrix_multiply(translation, rotation))
 
 //7.4 correct transformation is set up for anchor, now create ARAnchor instance
 //unique identifier and image that user tapped is stored into imageNodes dictionary, so then image can be added to scene after new anchor is registered on scene
 
 let anchor = ARAnchor(transform: transform)
 imageNodes[anchor.identifier] = UIImage(named: images[indexPath.row])
 arScene.session.add(anchor: anchor)
 
 storeWorldMap()
 }
 
 //method used to determine camera rotation, used in 7.3
 var cameraAdjustmentMatrix: SCNMatrix4 {
 switch UIDevice.current.orientation {
 case .portrait:
 return SCNMatrix4MakeRotation(.pi/2, 0, 0, 1)
 case .landscapeRight:
 return SCNMatrix4MakeRotation(.pi, 0, 0, 1)
 default:
 return SCNMatrix4MakeRotation(0, 0, 0, 0)
 }
 }
 }
 */
