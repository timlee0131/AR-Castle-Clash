/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 ARSCNViewDelegate interactions for `ViewController`.
 */

import ARKit
import SceneKit

extension ViewController: ARSCNViewDelegate, ARSessionDelegate {
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        
        let isAnyObjectInView = virtualObjectLoader.loadedObjects.contains { object in
            return sceneView.isNode(object, insideFrustumOf: sceneView.pointOfView!)
        }
        
        DispatchQueue.main.async {
            self.updateFocusSquare(isObjectVisible: isAnyObjectInView)
            
            // If the object selection menu is open, update availability of items
            if self.objectsViewController?.viewIfLoaded?.window != nil {
                self.objectsViewController?.updateObjectAvailability()
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARPlaneAnchor else { return }
        DispatchQueue.main.async {
            self.statusViewController.cancelScheduledMessage(for: .planeEstimation)
            self.statusViewController.showMessage("SURFACE DETECTED")
            if self.virtualObjectLoader.loadedObjects.isEmpty {
                self.statusViewController.scheduleMessage("TAP + TO PLACE AN OBJECT", inSeconds: 7.5, messageType: .contentPlacement)
            }
        }
        if(!plane_added){
            /// plane visualize
            // Place content only for anchors found by plane detection.
            guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
            
            // Create a custom object to visualize the plane geometry and extent.
            let plane = Plane(anchor: planeAnchor, in: sceneView)
            
            // Add the visualization to the ARKit-managed node so that it tracks
            // changes in the plane anchor as plane estimation continues.
            node.addChildNode(plane)
            plane_added = true
        }
        
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        updateQueue.async {
            if let objectAtAnchor = self.virtualObjectLoader.loadedObjects.first(where: { $0.anchor == anchor }) {
                objectAtAnchor.simdPosition = anchor.transform.translation
                objectAtAnchor.anchor = anchor
            }
        }
        
        if(!plane_locked){
            /// plane visualize
            // Update only anchors and nodes set up by `renderer(_:didAdd:for:)`.
            guard let planeAnchor = anchor as? ARPlaneAnchor,
                  let plane = node.childNodes.first as? Plane
            else { return }
            
            // Update ARSCNPlaneGeometry to the anchor's new estimated shape.
            if let planeGeometry = plane.meshNode.geometry as? ARSCNPlaneGeometry {
                planeGeometry.update(from: planeAnchor.geometry)
                plane.initializePhysicsBody()
            }
            
            // Update extent visualization to the anchor's new bounding rectangle.
            if let extentGeometry = plane.extentNode.geometry as? SCNPlane {
                extentGeometry.width = CGFloat(planeAnchor.extent.x)
                extentGeometry.height = CGFloat(planeAnchor.extent.z)
                plane.extentNode.simdPosition = planeAnchor.center
            }
        }
        
    }
    
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
        
        DispatchQueue.main.async { [self] in
            if thumbTip != nil && indexTip != nil {
                var distance:CGFloat = hypot(thumbTip!.x - indexTip!.x, thumbTip!.y - indexTip!.y)
                
                //if pinch
                if distance < 0.10 {
                    indexTip!.y = 1-indexTip!.y
                    var newPoint:CGPoint = CGPoint(x:indexTip!.y,y:indexTip!.x)
                    let point = VNImagePointForNormalizedPoint(newPoint, Int(sceneView.frame.size.width), Int(sceneView.frame.size.height))
                    //if moving object with pinch
                    if lastObjectPinched == nil{
                        if let object = self.sceneView.virtualObject(at: point) {
                            //print("object pinched")
                            object.childNodes[0].physicsBody?.type = .kinematic
                            lastObjectPinched = object
                        }
                    }else{
                        virtualObjectInteraction.translate(lastObjectPinched!, basedOn: point)
                        lastObjectPinched!.childNodes[0].worldPosition.y = height_offset
                    }
                    
                }else{
                    if lastObjectPinched != nil{
                        print("Unpinched")
                        lastObjectPinched!.childNodes[0].physicsBody?.type = .dynamic
                        lastObjectPinched = nil
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
    /// - Tag: ShowVirtualContent
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        statusViewController.showTrackingQualityInfo(for: camera.trackingState, autoHide: true)
        switch camera.trackingState {
        case .notAvailable, .limited:
            statusViewController.escalateFeedback(for: camera.trackingState, inSeconds: 3.0)
        case .normal:
            statusViewController.cancelScheduledMessage(for: .trackingStateEscalation)
            showVirtualContent()
        }
    }
    
    func showVirtualContent() {
        virtualObjectLoader.loadedObjects.forEach { $0.isHidden = false }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            self.displayErrorMessage(title: "The AR session failed.", message: errorMessage)
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Hide content before going into the background.
        hideVirtualContent()
    }
    
    /// - Tag: HideVirtualContent
    func hideVirtualContent() {
        virtualObjectLoader.loadedObjects.forEach { $0.isHidden = true }
    }
    
    /*
     Allow the session to attempt to resume after an interruption.
     This process may not succeed, so the app must be prepared
     to reset the session if the relocalizing status continues
     for a long time -- see `escalateFeedback` in `StatusViewController`.
     */
    /// - Tag: Relocalization
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        return true
    }
}
