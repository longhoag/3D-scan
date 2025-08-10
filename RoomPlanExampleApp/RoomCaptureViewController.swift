import UIKit
import RoomPlan
import RealityKit
import SceneKit
import ModelIO

class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    
    @IBOutlet var exportButton: UIButton?
    
    @IBOutlet var doneButton: UIBarButtonItem?
    @IBOutlet var cancelButton: UIBarButtonItem?
    @IBOutlet var activityIndicator: UIActivityIndicatorView?
    
    private var isScanning: Bool = false
    
    private var roomCaptureView: RoomCaptureView!
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()
    
    private var finalResults: CapturedRoom?
    private var sceneView: SCNView?
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up after loading the view.
        setupRoomCaptureView()
        activityIndicator?.stopAnimating()
    }
    
    private func setupRoomCaptureView() {
        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        
        view.insertSubview(roomCaptureView, at: 0)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }
    
    override func viewWillDisappear(_ flag: Bool) {
        super.viewWillDisappear(flag)
        stopSession()
    }
    
    private func startSession() {
        isScanning = true
        roomCaptureView?.captureSession.run(configuration: roomCaptureSessionConfig)
        
        setActiveNavBar()
    }
    
    private func stopSession() {
        isScanning = false
        roomCaptureView?.captureSession.stop()
        
        setCompleteNavBar()
    }
    
    // MARK: - RoomCaptureViewDelegate & RoomCaptureSessionDelegate
    
    // Decide to post-process and show the final results.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }
    
    // Access the final post-processed results.
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        finalResults = processedResult
        self.exportButton?.isEnabled = true
        self.activityIndicator?.stopAnimating()
    }
    
    // MARK: - Action Methods
    
    @IBAction func doneScanning(_ sender: UIBarButtonItem) {
        if isScanning { stopSession() } else { cancelScanning(sender) }
        self.exportButton?.isEnabled = false
        self.activityIndicator?.startAnimating()
    }

    @IBAction func cancelScanning(_ sender: UIBarButtonItem) {
        navigationController?.dismiss(animated: true)
    }
    
    // Export the USDZ output with custom shaped objects instead of blocks
    @IBAction func exportResults(_ sender: UIButton) {
        let destinationFolderURL = FileManager.default.temporaryDirectory.appending(path: "Export")
        let destinationURL = destinationFolderURL.appending(path: "Room.usdz")
        let capturedRoomURL = destinationFolderURL.appending(path: "Room.json")
        do {
            try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true)
            let jsonEncoder = JSONEncoder()
            let jsonData = try jsonEncoder.encode(finalResults)
            try jsonData.write(to: capturedRoomURL)
            
            // Create custom scene with shaped objects instead of using default export
            let customScene = createCustomSceneWithShapedObjects()
            try customScene.write(to: destinationURL, options: nil, delegate: nil, progressHandler: nil)
            
            let activityVC = UIActivityViewController(activityItems: [destinationFolderURL], applicationActivities: nil)
            activityVC.modalPresentationStyle = .popover
            
            present(activityVC, animated: true, completion: nil)
            if let popOver = activityVC.popoverPresentationController {
                popOver.sourceView = self.exportButton
            }
        } catch {
            print("Error = \(error)")
        }
    }
    
    // Add this new function to create a custom scene with shaped objects
    private func createCustomSceneWithShapedObjects() -> SCNScene {
        let scene = SCNScene()
        
        guard let finalResults = finalResults else { return scene }
        
        // Add walls
        let walls = getAllNodes(for: finalResults.walls,
                                length: 0.1,
                                contents: UIColor.lightGray)
        walls.forEach { scene.rootNode.addChildNode($0) }
        
        // Add doors
        let doors = getAllNodes(for: finalResults.doors,
                                length: 0.11,
                                contents: UIColor.brown)
        doors.forEach { scene.rootNode.addChildNode($0) }
        
        // Add windows
        let windows = getAllNodes(for: finalResults.windows,
                                  length: 0.11,
                                  contents: UIColor.cyan.withAlphaComponent(0.7))
        windows.forEach { scene.rootNode.addChildNode($0) }
        
        // Add openings
        let openings = getAllNodes(for: finalResults.openings,
                                   length: 0.11,
                                   contents: UIColor.blue.withAlphaComponent(0.5))
        openings.forEach { scene.rootNode.addChildNode($0) }
        
        // Add objects with custom shapes
        getAllRoomObjectsCategory().forEach { category in
            let scannedObjects = finalResults.objects.filter { $0.category == category }
            let objectsNode = getAllNodes(for: scannedObjects, category: category)
            objectsNode.forEach { scene.rootNode.addChildNode($0) }
        }
        
        return scene
    }
    
    // MARK: - Navigation Bar Actions
    
    private func setActiveNavBar() {
        UIView.animate(withDuration: 1.0, animations: {
            self.cancelButton?.tintColor = .white
            self.doneButton?.tintColor = .white
            self.exportButton?.alpha = 0.0
        }, completion: { complete in
            self.exportButton?.isHidden = true
        })
    }
    
    private func setCompleteNavBar() {
        self.exportButton?.isHidden = false
        UIView.animate(withDuration: 1.0) {
            self.cancelButton?.tintColor = .systemBlue
            self.doneButton?.tintColor = .systemBlue
            self.exportButton?.alpha = 1.0
        }
    }
    
    // MARK: - Scene Generation and Geometry Helpers
    
    // Visualization helper for displaying the captured room model
    private func onModelReady(model: CapturedRoom) {
        let walls = getAllNodes(for: model.walls,
                                length: 0.1,
                                contents: UIImage(named: "wallTexture"))
        walls.forEach { sceneView?.scene?.rootNode.addChildNode($0) }
        let doors = getAllNodes(for: model.doors,
                                length: 0.11,
                                contents: UIImage(named: "doorTexture"))
        doors.forEach { sceneView?.scene?.rootNode.addChildNode($0) }
        let windows = getAllNodes(for: model.windows,
                                  length: 0.11,
                                  contents: UIImage(named: "windowTexture"))
        windows.forEach { sceneView?.scene?.rootNode.addChildNode($0) }
        let openings = getAllNodes(for: model.openings,
                                   length: 0.11,
                                   contents: UIColor.blue.withAlphaComponent(0.5))
        openings.forEach { sceneView?.scene?.rootNode.addChildNode($0) }
        
        // for objects
        getAllRoomObjectsCategory().forEach { category in
            let scannedObjects = model.objects.filter { $0.category == category }
            let objectsNode = getAllNodes(for: scannedObjects, category: category)
            objectsNode.forEach { sceneView?.scene?.rootNode.addChildNode($0) }
        }
    }
    
    private func getAllNodes(for surfaces: [CapturedRoom.Surface], length: CGFloat, contents: Any?) -> [SCNNode] {
        var nodes: [SCNNode] = []
        surfaces.forEach { surface in
            let width = CGFloat(surface.dimensions.x)
            let height = CGFloat(surface.dimensions.y)
            let node = SCNNode()
            node.geometry = SCNBox(width: width, height: height, length: length, chamferRadius: 0.0)
            node.geometry?.firstMaterial?.diffuse.contents = contents
            node.transform = SCNMatrix4(surface.transform)
            nodes.append(node)
        }
        return nodes
    }
    
    // Add this helper function to get proper geometry for each object category
    private func getGeometryForObject(category: CapturedRoom.Object.Category, dimensions: simd_float3) -> SCNGeometry {
        let width = CGFloat(dimensions.x)
        let height = CGFloat(dimensions.y)
        let length = CGFloat(dimensions.z)
        
        switch category {
        case .chair:
            return createChairGeometry(width: width, height: height, length: length)
            
        case .table:
            return createTableGeometry(width: width, height: height, length: length)
            
        case .bed:
            return createBedGeometry(width: width, height: height, length: length)
            
        case .sofa:
            return createSofaGeometry(width: width, height: height, length: length)
            
        case .toilet:
            return createToiletGeometry(width: width, height: height, length: length)
            
        case .bathtub:
            return createBathtubGeometry(width: width, height: height, length: length)
            
        case .oven:
            return createOvenGeometry(width: width, height: height, length: length)
            
        case .dishwasher:
            return createDishwasherGeometry(width: width, height: height, length: length)
            
        case .refrigerator:
            return createRefrigeratorGeometry(width: width, height: height, length: length)
            
        case .stove:
            return createStoveGeometry(width: width, height: height, length: length)
            
        case .television:
            return createTelevisionGeometry(width: width, height: height, length: length)
            
        case .fireplace:
            return createFireplaceGeometry(width: width, height: height, length: length)
            
        case .washerDryer:
            return createWasherDryerGeometry(width: width, height: height, length: length)
            
        default:
            return SCNBox(width: width, height: height, length: length, chamferRadius: 0.02)
        }
    }
    
    // Updated to use proper shapes for objects
    private func getAllNodes(for objects: [CapturedRoom.Object], category: CapturedRoom.Object.Category) -> [SCNNode] {
        var nodes: [SCNNode] = []
        
        objects.forEach { object in
            let geometry = getGeometryForObject(category: category, dimensions: object.dimensions)
            let node = SCNNode(geometry: geometry)
            
            // Set material based on category
            let material = SCNMaterial()
            switch category {
            case .chair, .table, .bed, .sofa:
                material.diffuse.contents = UIColor.brown
            case .toilet, .bathtub:
                material.diffuse.contents = UIColor.white
            case .oven, .dishwasher, .washerDryer, .refrigerator, .stove:
                material.diffuse.contents = UIColor.lightGray
            case .television:
                material.diffuse.contents = UIColor.black
            case .fireplace:
                material.diffuse.contents = UIColor.darkGray
            default:
                material.diffuse.contents = UIColor.gray
            }
            
            geometry.firstMaterial = material
            node.transform = SCNMatrix4(object.transform)
            nodes.append(node)
        }
        
        return nodes
    }
    
    // Get all room object categories
    private func getAllRoomObjectsCategory() -> [CapturedRoom.Object.Category] {
        return [
            .chair, .table, .bed, .sofa, .toilet, .bathtub,
            .oven, .dishwasher, .washerDryer, .refrigerator,
            .stove, .television, .fireplace
        ]
    }
    
    // MARK: - Detailed Geometry Creation Functions
    
    // Detailed chair geometry with legs, seat, and backrest
    private func createChairGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        let chairNode = SCNNode()
        
        // Seat
        let seatGeometry = SCNBox(width: width * 0.9, height: height * 0.05, length: length * 0.9, chamferRadius: 0.01)
        let seatNode = SCNNode(geometry: seatGeometry)
        seatNode.position = SCNVector3(0, height * 0.4, 0)
        
        // Backrest
        let backrestGeometry = SCNBox(width: width * 0.9, height: height * 0.5, length: length * 0.1, chamferRadius: 0.01)
        let backrestNode = SCNNode(geometry: backrestGeometry)
        backrestNode.position = SCNVector3(0, height * 0.65, -length * 0.4)
        
        // Legs (4 legs)
        let legRadius: CGFloat = 0.02
        let legHeight = height * 0.4
        
        for i in 0..<4 {
            let legGeometry = SCNCylinder(radius: legRadius, height: legHeight)
            let legNode = SCNNode(geometry: legGeometry)
            
            let xPos = (i % 2 == 0) ? -width * 0.4 : width * 0.4
            let zPos = (i < 2) ? -length * 0.4 : length * 0.4
            
            legNode.position = SCNVector3(xPos, legHeight * 0.5, zPos)
            chairNode.addChildNode(legNode)
        }
        
        chairNode.addChildNode(seatNode)
        chairNode.addChildNode(backrestNode)
        
        // Return seat geometry as primary
        return seatGeometry
    }
    
    // Detailed table geometry with legs and surface
    private func createTableGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        let tableNode = SCNNode()
        
        // Table top
        let topGeometry = SCNBox(width: width, height: height * 0.1, length: length, chamferRadius: 0.02)
        let topNode = SCNNode(geometry: topGeometry)
        topNode.position = SCNVector3(0, height * 0.9, 0)
        
        // Legs (4 legs)
        let legRadius: CGFloat = 0.03
        let legHeight = height * 0.85
        
        for i in 0..<4 {
            let legGeometry = SCNCylinder(radius: legRadius, height: legHeight)
            let legNode = SCNNode(geometry: legGeometry)
            
            let xPos = (i % 2 == 0) ? -width * 0.45 : width * 0.45
            let zPos = (i < 2) ? -length * 0.45 : length * 0.45
            
            legNode.position = SCNVector3(xPos, legHeight * 0.5, zPos)
            tableNode.addChildNode(legNode)
        }
        
        tableNode.addChildNode(topNode)
        
        return topGeometry
    }
    
    // Detailed bed geometry with frame and mattress
    private func createBedGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        let bedNode = SCNNode()
        
        // Mattress
        let mattressGeometry = SCNBox(width: width * 0.95, height: height * 0.3, length: length * 0.95, chamferRadius: 0.05)
        let mattressNode = SCNNode(geometry: mattressGeometry)
        mattressNode.position = SCNVector3(0, height * 0.6, 0)
        
        // Bed frame
        let frameGeometry = SCNBox(width: width, height: height * 0.4, length: length, chamferRadius: 0.02)
        let frameNode = SCNNode(geometry: frameGeometry)
        frameNode.position = SCNVector3(0, height * 0.3, 0)
        
        // Headboard
        let headboardGeometry = SCNBox(width: width, height: height * 0.6, length: length * 0.1, chamferRadius: 0.02)
        let headboardNode = SCNNode(geometry: headboardGeometry)
        headboardNode.position = SCNVector3(0, height * 0.7, -length * 0.45)
        
        bedNode.addChildNode(mattressNode)
        bedNode.addChildNode(frameNode)
        bedNode.addChildNode(headboardNode)
        
        return mattressGeometry
    }
    
    // Detailed sofa geometry
    private func createSofaGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        let sofaNode = SCNNode()
        
        // Base/seat
        let seatGeometry = SCNBox(width: width, height: height * 0.3, length: length * 0.8, chamferRadius: 0.05)
        let seatNode = SCNNode(geometry: seatGeometry)
        seatNode.position = SCNVector3(0, height * 0.4, 0)
        
        // Backrest
        let backrestGeometry = SCNBox(width: width, height: height * 0.6, length: length * 0.2, chamferRadius: 0.05)
        let backrestNode = SCNNode(geometry: backrestGeometry)
        backrestNode.position = SCNVector3(0, height * 0.65, -length * 0.3)
        
        // Armrests
        let armrestGeometry = SCNBox(width: width * 0.15, height: height * 0.4, length: length * 0.8, chamferRadius: 0.03)
        
        let leftArmrest = SCNNode(geometry: armrestGeometry)
        leftArmrest.position = SCNVector3(-width * 0.425, height * 0.55, 0)
        
        let rightArmrest = SCNNode(geometry: armrestGeometry)
        rightArmrest.position = SCNVector3(width * 0.425, height * 0.55, 0)
        
        sofaNode.addChildNode(seatNode)
        sofaNode.addChildNode(backrestNode)
        sofaNode.addChildNode(leftArmrest)
        sofaNode.addChildNode(rightArmrest)
        
        return seatGeometry
    }
    
    // Detailed toilet geometry
    private func createToiletGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        let toiletNode = SCNNode()
        
        // Bowl (main cylinder)
        let bowlGeometry = SCNCylinder(radius: min(width, length) * 0.4, height: height * 0.6)
        let bowlNode = SCNNode(geometry: bowlGeometry)
        bowlNode.position = SCNVector3(0, height * 0.3, 0)
        
        // Tank (back part)
        let tankGeometry = SCNBox(width: width * 0.6, height: height * 0.4, length: length * 0.3, chamferRadius: 0.02)
        let tankNode = SCNNode(geometry: tankGeometry)
        tankNode.position = SCNVector3(0, height * 0.7, -length * 0.25)
        
        // Seat
        let seatGeometry = SCNCylinder(radius: min(width, length) * 0.45, height: height * 0.05)
        let seatNode = SCNNode(geometry: seatGeometry)
        seatNode.position = SCNVector3(0, height * 0.65, 0)
        
        toiletNode.addChildNode(bowlNode)
        toiletNode.addChildNode(tankNode)
        toiletNode.addChildNode(seatNode)
        
        return bowlGeometry
    }
    
    // Bathtub geometry
    private func createBathtubGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        return SCNBox(width: width, height: height * 0.4, length: length, chamferRadius: 0.1)
    }
    
    // Oven geometry
    private func createOvenGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        return SCNBox(width: width, height: height, length: length, chamferRadius: 0.02)
    }
    
    // Dishwasher geometry
    private func createDishwasherGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        return SCNBox(width: width, height: height, length: length, chamferRadius: 0.02)
    }
    
    // Detailed refrigerator geometry
    private func createRefrigeratorGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        let fridgeNode = SCNNode()
        
        // Main body
        let bodyGeometry = SCNBox(width: width, height: height * 0.9, length: length, chamferRadius: 0.02)
        let bodyNode = SCNNode(geometry: bodyGeometry)
        bodyNode.position = SCNVector3(0, height * 0.45, 0)
        
        // Door handle
        let handleGeometry = SCNCylinder(radius: 0.01, height: height * 0.2)
        let handleNode = SCNNode(geometry: handleGeometry)
        handleNode.position = SCNVector3(width * 0.4, height * 0.5, length * 0.51)
        handleNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        
        fridgeNode.addChildNode(bodyNode)
        fridgeNode.addChildNode(handleNode)
        
        return bodyGeometry
    }
    
    // Detailed stove geometry
    private func createStoveGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        let stoveNode = SCNNode()
        
        // Base
        let baseGeometry = SCNBox(width: width, height: height * 0.8, length: length, chamferRadius: 0.02)
        let baseNode = SCNNode(geometry: baseGeometry)
        baseNode.position = SCNVector3(0, height * 0.4, 0)
        
        // Cooktop
        let cooktopGeometry = SCNBox(width: width * 0.95, height: height * 0.05, length: length * 0.95, chamferRadius: 0.01)
        let cooktopNode = SCNNode(geometry: cooktopGeometry)
        cooktopNode.position = SCNVector3(0, height * 0.825, 0)
        
        // Burners (4 burners)
        for i in 0..<4 {
            let burnerGeometry = SCNCylinder(radius: 0.08, height: 0.02)
            let burnerNode = SCNNode(geometry: burnerGeometry)
            
            let xPos = (i % 2 == 0) ? -width * 0.25 : width * 0.25
            let zPos = (i < 2) ? -length * 0.25 : length * 0.25
            
            burnerNode.position = SCNVector3(xPos, height * 0.85, zPos)
            stoveNode.addChildNode(burnerNode)
        }
        
        stoveNode.addChildNode(baseNode)
        stoveNode.addChildNode(cooktopNode)
        
        return cooktopGeometry
    }
    
    // Detailed television geometry
    private func createTelevisionGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        let tvNode = SCNNode()
        
        // Screen
        let screenGeometry = SCNBox(width: width, height: height * 0.9, length: length * 0.1, chamferRadius: 0.01)
        let screenNode = SCNNode(geometry: screenGeometry)
        
        // Stand
        let standGeometry = SCNBox(width: width * 0.3, height: height * 0.2, length: length * 0.8, chamferRadius: 0.02)
        let standNode = SCNNode(geometry: standGeometry)
        standNode.position = SCNVector3(0, -height * 0.35, 0)
        
        tvNode.addChildNode(screenNode)
        tvNode.addChildNode(standNode)
        
        return screenGeometry
    }
    
    // Fireplace geometry
    private func createFireplaceGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        return SCNBox(width: width, height: height, length: length * 0.3, chamferRadius: 0.02)
    }
    
    // Detailed washer/dryer geometry
    private func createWasherDryerGeometry(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNGeometry {
        let washerNode = SCNNode()
        
        // Main body
        let bodyGeometry = SCNBox(width: width, height: height * 0.9, length: length, chamferRadius: 0.02)
        let bodyNode = SCNNode(geometry: bodyGeometry)
        bodyNode.position = SCNVector3(0, height * 0.45, 0)
        
        // Door (circular)
        let doorGeometry = SCNCylinder(radius: min(width, height) * 0.3, height: 0.05)
        let doorNode = SCNNode(geometry: doorGeometry)
        doorNode.position = SCNVector3(0, height * 0.5, length * 0.51)
        doorNode.eulerAngles = SCNVector3(Float.pi/2, 0, 0)
        
        washerNode.addChildNode(bodyNode)
        washerNode.addChildNode(doorNode)
        
        return bodyGeometry
    }
}

