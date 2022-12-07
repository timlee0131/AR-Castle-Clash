//
//  ViewController.swift
//  test
//
//  Created by zhongyuan liu on 12/5/22.
//

import UIKit
import AVFoundation
import Vision
import ARKit

class ViewController: UIViewController {
    //class to detect hand landmarks using front camera
    
    //define 4 properties:
    //1. handPoseRequest to detect fingers on each frame; if detected, will display points in the overlay to show hand landmarks(fingers)
    //2. property to work with front video queue: videoDataOutputQueue
    //3. property to work with overlay: cameraView
    //4. property to work with video stream: cameraFeedSession

    // Vision hand pose request, detect hand landmarks
     private var handPoseRequest = VNDetectHumanHandPoseRequest()

     // Video, view and camera feed properties
    //cameraView to work with overlay
     private var cameraView: CameraView { view as! CameraView }
    //videoDataOutputQueue to work with front video queue
     private let videoDataOutputQueue = DispatchQueue(label: "CameraFeedDataOutput", qos: .userInteractive)
    //cameraFeedSession to work with video stream
     private var cameraFeedSession: AVCaptureSession?

    //create/start AVCaptureSession for camera
     override func viewDidAppear(_ animated: Bool) {
       super.viewDidAppear(animated)

       // Setup video session and camera overlay
       if cameraFeedSession == nil {
         cameraView.previewLayer.videoGravity = .resizeAspectFill
         setupAVSession()
         cameraView.previewLayer.session = cameraFeedSession
       }
       cameraFeedSession?.startRunning()
     }

    //end AVCaptureSession for camera
     override func viewWillDisappear(_ animated: Bool) {
       cameraFeedSession?.stopRunning()
       super.viewWillDisappear(animated)
     }

    //--------------------------FUNCTIONS-------------------------
    //create video session, detect hand, do hand detection on video session, process and display detected points
     override func viewDidLoad() {
       super.viewDidLoad()
         //detect single hand
         handPoseRequest.maximumHandCount = 1

     }

     func setupAVSession() {
         //create video session, and set as cameraFeedSession
         
         //1. use back camera as input, AVCaptureDevice instance
         guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else{
             fatalError("no front camera!")
         }
         //2. capture input from camera, created videoDevice instance
         guard let deviceInput = try? AVCaptureDeviceInput(device: videoDevice) else{
             fatalError("no camera input available!")
         }
         
         //3. create new session
         let session = AVCaptureSession()
         session.beginConfiguration()
         session.sessionPreset = AVCaptureSession.Preset.high
         
         //4. add video input to session
         guard session.canAddInput(deviceInput) else{
             fatalError("could not add video input to session")
         }
         session.addInput(deviceInput)
         
         //5. configure data output to handle video stream, add data output
         let dataOutput = AVCaptureVideoDataOutput()
         if session.canAddOutput(dataOutput){
             session.addOutput(dataOutput)
             
             dataOutput.alwaysDiscardsLateVideoFrames = true
             dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
             //when camera caputres new frames, our session handles frames - sends frames to our delegate method
             dataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
         } else{
             fatalError("could not add video output to session")
         }
         
         session.commitConfiguration()
         
         cameraFeedSession = session
         
     }


     func processPoints(_ fingerTips: [CGPoint?]) {
         //process detected points, ie display detected points
         
         //1. convert AVFoundation Coordinates to UIKit Coordinates(by performing 'map' over AV-coordinates)
         let previewLayer = cameraView.previewLayer
         let convertedPoints = fingerTips
           .compactMap {$0}
           .compactMap {previewLayer.layerPointConverted(fromCaptureDevicePoint: $0)}
         
         //2. display converted points in overlay
         cameraView.showPoints(convertedPoints, color: .red)
     }
    
    func processPointsTouching(_ fingerTips: [CGPoint?]) {
        //process detected points, ie display detected points
        
        //1. convert AVFoundation Coordinates to UIKit Coordinates(by performing 'map' over AV-coordinates)
        let previewLayer = cameraView.previewLayer
        let convertedPoints = fingerTips
          .compactMap {$0}
          .compactMap {previewLayer.layerPointConverted(fromCaptureDevicePoint: $0)}
        
        //2. display converted points in overlay
        cameraView.showPointsTouching(convertedPoints, color: .green)
    }
     
   }

//make vision request from ARKit
   extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
     public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
         //do hand detection on video session
         
         //1. store finger tip points
         var thumbTip: CGPoint?
         var indexTip: CGPoint?
//         var ringTip: CGPoint?
//         var middleTip: CGPoint?
//         var littleTip: CGPoint?
         
         //5. processPoints in main thread because working with UI
         //use defer up here, so if there are no hands detected, processPoints will happen with empty values
         defer{
             DispatchQueue.main.sync {
//                 self.processPoints([thumbTip, indexTip, ringTip, middleTip, littleTip])
                 self.processPoints([thumbTip, indexTip])
                 if thumbTip != nil && indexTip != nil {
                     var distance:CGFloat = hypot(thumbTip!.x - indexTip!.x, thumbTip!.y - indexTip!.y)
                     if distance < 0.10 {
                         self.processPointsTouching([thumbTip, indexTip])
                     }
                 }
             }
         }
         
         //2. execute handPoseRequest over the video stream(sampleBuffer)
         let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
         do{
             try handler.perform([handPoseRequest])
             guard let observation = handPoseRequest.results?.first else{
                 return //return if no hands are detected
             }
             
             //3. get observation points if hand is detected
             let thumbPoints = try observation.recognizedPoints(.thumb)
             let indexFingerPoints = try observation.recognizedPoints(.indexFinger)
             let ringFingerPoints = try observation.recognizedPoints(.ringFinger)
             let middleFingerPoints = try observation.recognizedPoints(.middleFinger)
             let littleFingerPoints = try observation.recognizedPoints(.littleFinger)
             
             guard let littleTipPoint = littleFingerPoints[.littleTip],
                   let middleTipPoint = middleFingerPoints[.middleTip],
                   let ringTipPoint = ringFingerPoints[.ringTip],
                   let indexTipPoint = indexFingerPoints[.indexTip],
                   let thumbTipPoint = thumbPoints[.thumbTip]
             else{
                 return
             }
             
             //4. transform Vision coordinates to AVFoundation coordinates
             //Vision origin is at bottom left, AVFoundation top left
             thumbTip = CGPoint(x: thumbTipPoint.location.x, y: 1 - thumbTipPoint.location.y)
             indexTip = CGPoint(x: indexTipPoint.location.x, y: 1 - indexTipPoint.location.y)
//             ringTip = CGPoint(x: ringTipPoint.location.x, y: 1 - ringTipPoint.location.y)
//             middleTip = CGPoint(x: middleTipPoint.location.x, y: 1 - middleTipPoint.location.y)
//             littleTip = CGPoint(x: littleTipPoint.location.x, y: 1 - littleTipPoint.location.y)
             
         } catch{
             cameraFeedSession?.stopRunning()
             fatalError(error.localizedDescription)
         }
         

     }
}

