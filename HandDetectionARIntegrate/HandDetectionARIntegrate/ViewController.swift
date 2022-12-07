//
//  ViewController.swift
//  HandDetectionARIntegrate
//
//  Created by Tim Lee on 12/7/22.
//

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
//    private var cameraView: CameraView!
    
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //detect single hand
        handPoseRequest.maximumHandCount = 1
        
        // Set the view's delegate
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        // Create a new scene
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        
        // Set the scene to the view
        sceneView.scene = scene
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()

        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }

    // MARK: - ARSCNViewDelegate
    
/*
    // Override to create and configure nodes for anchors added to the view's session.
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let node = SCNNode()
     
        return node
    }
*/
    var currentBuffer: CVPixelBuffer?
    
    // MARK: analyze AR Frames
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
//        guard currentBuffer == nil, case .normal = frame.camera.trackingState else {
//            return
//        }
        
        // retain the image buffer for vision processing
        currentBuffer = frame.capturedImage
        if currentBuffer == nil {
            print("nil")
            return
        }
        
        var info = CMSampleTimingInfo()
        info.presentationTimeStamp = CMTime.zero
        info.duration = CMTime.invalid
        info.decodeTimeStamp = CMTime.invalid
        var formatDesc: CMFormatDescription? = nil
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: currentBuffer!, formatDescriptionOut: &formatDesc)
        var sampleBuffer: CMSampleBuffer? = nil

        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: currentBuffer!, formatDescription: formatDesc!, sampleTiming: &info, sampleBufferOut: &sampleBuffer)
        
        var thumbTip: CGPoint?
        var indexTip: CGPoint?
        
        defer{
            DispatchQueue.main.async {
//                print(thumbTip!.x)
//                print(indexTip!.y)
//                self.processPoints([thumbTip, indexTip])
                print("no pinch")
                if thumbTip != nil && indexTip != nil {
                    var distance:CGFloat = hypot(thumbTip!.x - indexTip!.x, thumbTip!.y - indexTip!.y)
                    if distance < 0.10 {
//                        self.processPointsTouching([thumbTip, indexTip])
                        print("PINCH")
                    }
                }
            }
        }
        
        if let sampleBuffer = sampleBuffer {
            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([handPoseRequest])
                guard let observation = handPoseRequest.results?.first else{return}
                
                let thumbPoints = try observation.recognizedPoints(.thumb)
                let indexFingerPoints = try observation.recognizedPoints(.indexFinger)
                guard let indexTipPoint = indexFingerPoints[.indexTip],
                      let thumbTipPoint = thumbPoints[.thumbTip]
                else {return}
                
                thumbTip = CGPoint(x: thumbTipPoint.location.x, y: 1 - thumbTipPoint.location.y)
                indexTip = CGPoint(x: indexTipPoint.location.x, y: 1 - indexTipPoint.location.y)
            } catch {
                return
            }
        }
    }
//
//    func processPoints(_ fingerTips: [CGPoint?]) {
//        //process detected points, ie display detected points
//
//        //1. convert AVFoundation Coordinates to UIKit Coordinates(by performing 'map' over AV-coordinates)
//        let previewLayer = cameraView.previewLayer
//        let convertedPoints = fingerTips
//          .compactMap {$0}
//          .compactMap {previewLayer.layerPointConverted(fromCaptureDevicePoint: $0)}
//
//        //2. display converted points in overlay
//        cameraView.showPoints(convertedPoints, color: .red)
//    }
//
//   func processPointsTouching(_ fingerTips: [CGPoint?]) {
//       //process detected points, ie display detected points
//
//       //1. convert AVFoundation Coordinates to UIKit Coordinates(by performing 'map' over AV-coordinates)
//       let previewLayer = cameraView.previewLayer
//       let convertedPoints = fingerTips
//         .compactMap {$0}
//         .compactMap {previewLayer.layerPointConverted(fromCaptureDevicePoint: $0)}
//
//       //2. display converted points in overlay
//       cameraView.showPointsTouching(convertedPoints, color: .green)
//   }
//
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
}
