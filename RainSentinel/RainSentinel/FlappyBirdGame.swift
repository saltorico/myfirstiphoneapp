import SpriteKit
import SwiftUI

struct FlappyBirdGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scene = FlappyBirdScene()

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        LinearGradient(colors: [Color(red: 0.53, green: 0.81, blue: 0.98),
                                                 Color(red: 0.3, green: 0.6, blue: 0.95)],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    )
                    .ignoresSafeArea()
                    .onAppear {
                        scene.configure(for: geometry.size)
                        scene.startIfNeeded()
                    }
                    .onChange(of: geometry.size) { newSize in
                        scene.configure(for: newSize)
                    }
            }
            .navigationTitle("Rain Delay Bird")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    Text("Tap to flap, dodge the pipes, and pass the rainy wait time.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                }
            }
        }
        .onDisappear {
            scene.resetToMenu()
        }
    }
}

final class FlappyBirdScene: SKScene, SKPhysicsContactDelegate {
    private enum GameState {
        case menu
        case playing
        case gameOver
    }

    private enum PhysicsTuning {
        static let gravity = CGVector(dx: 0, dy: -18.0)
        static let flapImpulse = CGVector(dx: 0, dy: 215)
        static let maxDownwardVelocity: CGFloat = -520
        static let maxUpwardVelocity: CGFloat = 480
        static let pipeTravelSpeed: CGFloat = 160
    }

    private let birdCategory: UInt32 = 0x1 << 0
    private let obstacleCategory: UInt32 = 0x1 << 1
    private let scoreCategory: UInt32 = 0x1 << 2
    private let groundCategory: UInt32 = 0x1 << 3

    private var bird: SKSpriteNode?
    private var scoreLabel: SKLabelNode?
    private var stateLabel: SKLabelNode?
    private var gameState: GameState = .menu
    private var score = 0
    private var spawnActionKey = "pipeSpawn"
    private var groundNode = SKNode()
    private var configuredSize: CGSize = .zero

    override init() {
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 1.0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(for size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        configuredSize = size
        self.size = size
        if children.isEmpty {
            setupScene()
        } else {
            repositionLayout()
            BuildConfiguration.debugAssert(isSceneReady, "Scene expected core nodes after layout change but found them missing.")
        }
    }

    func startIfNeeded() {
        if gameState == .menu {
            ensureSceneReady()
            showMenu()
        }
    }

    func resetToMenu() {
        ensureSceneReady()
        removeAction(forKey: spawnActionKey)
        removeAllObstacles()
        score = 0
        updateScoreLabel()
        gameState = .menu
        bird?.position = startingBirdPosition()
        bird?.physicsBody?.velocity = .zero
        bird?.zRotation = 0
        bird?.physicsBody?.isDynamic = false
        showMenu()
    }

    override func didMove(to view: SKView) {
        physicsWorld.gravity = PhysicsTuning.gravity
        physicsWorld.contactDelegate = self
        if children.isEmpty {
            setupScene()
        }
        showMenu()
        BuildConfiguration.debugAssert(isSceneReady, "Scene failed to configure bird and score label after didMove invocation.")
    }

    private func setupScene() {
        if configuredSize == .zero {
            configuredSize = size
        }
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        createGround()
        recreateBirdIfNeeded()
        recreateScoreLabelIfNeeded()
        BuildConfiguration.debugAssert(isSceneReady, "Setup scene finished without required nodes.")
    }

    private func createGround() {
        groundNode.removeFromParent()
        groundNode = SKNode()
        let groundHeight = max(configuredSize.height * 0.1, 60)
        let ground = SKSpriteNode(color: SKColor(red: 0.37, green: 0.75, blue: 0.3, alpha: 1), size: CGSize(width: configuredSize.width, height: groundHeight))
        ground.anchorPoint = CGPoint(x: 0.5, y: 0)
        ground.position = CGPoint(x: 0, y: -configuredSize.height / 2)
        ground.physicsBody = SKPhysicsBody(rectangleOf: ground.size, center: CGPoint(x: 0, y: ground.size.height / 2))
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.categoryBitMask = groundCategory
        ground.physicsBody?.contactTestBitMask = birdCategory
        ground.physicsBody?.collisionBitMask = birdCategory
        groundNode.addChild(ground)
        addChild(groundNode)
    }

    private func repositionLayout() {
        if let ground = groundNode.children.first as? SKSpriteNode {
            ground.position = CGPoint(x: 0, y: -configuredSize.height / 2)
            ground.size.width = configuredSize.width
        }
        scoreLabel?.position = CGPoint(x: 0, y: configuredSize.height / 2 - 80)
        if gameState == .menu || gameState == .gameOver {
            stateLabel?.position = CGPoint(x: 0, y: configuredSize.height / 4)
        }
        if gameState != .playing {
            bird?.position = startingBirdPosition()
        }
        BuildConfiguration.debugAssert(isSceneReady, "Reposition layout expected configured nodes for state \(gameState).")
    }

    private func recreateBirdIfNeeded() {
        if let existingBird = bird {
            existingBird.removeAllActions()
            existingBird.removeFromParent()
        }
        let birdSize = CGSize(width: 48, height: 36)
        let newBird = SKSpriteNode(color: .clear, size: birdSize)
        newBird.position = startingBirdPosition()
        newBird.physicsBody = SKPhysicsBody(circleOfRadius: birdSize.height / 2.2)
        newBird.physicsBody?.categoryBitMask = birdCategory
        newBird.physicsBody?.contactTestBitMask = obstacleCategory | scoreCategory | groundCategory
        newBird.physicsBody?.collisionBitMask = obstacleCategory | groundCategory
        newBird.physicsBody?.allowsRotation = true
        newBird.physicsBody?.isDynamic = false
        newBird.physicsBody?.restitution = 0
        newBird.physicsBody?.friction = 0
        newBird.physicsBody?.linearDamping = 0.05
        newBird.physicsBody?.angularDamping = 0.8
        newBird.physicsBody?.usesPreciseCollisionDetection = true
        addChild(newBird)

        let bodyShape = SKShapeNode(ellipseOf: birdSize)
        bodyShape.fillColor = SKColor(red: 0.97, green: 0.83, blue: 0.18, alpha: 1)
        bodyShape.strokeColor = .clear
        bodyShape.zPosition = 1
        newBird.addChild(bodyShape)

        let eye = SKShapeNode(circleOfRadius: 5)
        eye.fillColor = .white
        eye.strokeColor = .black
        eye.lineWidth = 1
        eye.position = CGPoint(x: birdSize.width * 0.1, y: birdSize.height * 0.15)
        let pupil = SKShapeNode(circleOfRadius: 2)
        pupil.fillColor = .black
        pupil.strokeColor = .clear
        pupil.position = CGPoint(x: 1, y: -1)
        eye.addChild(pupil)
        addChild(eye)
        eye.zPosition = newBird.zPosition + 1
        eye.removeFromParent()
        newBird.addChild(eye)

        let beak = SKShapeNode(path: {
            let rect = CGRect(x: 0, y: -4, width: 14, height: 8)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }())
        beak.fillColor = SKColor(red: 1.0, green: 0.57, blue: 0.0, alpha: 1)
        beak.strokeColor = .clear
        beak.position = CGPoint(x: birdSize.width / 2.5, y: 0)
        newBird.addChild(beak)

        let wing = createWingNode(birdSize: birdSize)
        newBird.addChild(wing)

        let tail = createTailNode(birdSize: birdSize)
        newBird.addChild(tail)

        startWingAnimation(on: wing)
        bird = newBird
        BuildConfiguration.debugAssert(newBird.physicsBody != nil, "Bird should have physics configured after recreation.")
    }

    private func createWingNode(birdSize: CGSize) -> SKShapeNode {
        let wingPath = CGMutablePath()
        wingPath.move(to: CGPoint(x: -birdSize.width * 0.1, y: 0))
        wingPath.addQuadCurve(to: CGPoint(x: birdSize.width * 0.25, y: birdSize.height * 0.05), control: CGPoint(x: birdSize.width * 0.05, y: birdSize.height * 0.38))
        wingPath.addQuadCurve(to: CGPoint(x: -birdSize.width * 0.1, y: 0), control: CGPoint(x: birdSize.width * 0.15, y: -birdSize.height * 0.2))

        let wing = SKShapeNode(path: wingPath)
        wing.fillColor = SKColor(red: 0.96, green: 0.76, blue: 0.12, alpha: 1)
        wing.strokeColor = SKColor(red: 0.91, green: 0.6, blue: 0.05, alpha: 1)
        wing.lineWidth = 2
        wing.position = CGPoint(x: -birdSize.width * 0.15, y: -birdSize.height * 0.05)
        wing.zPosition = 0.5
        wing.name = "wing"
        return wing
    }

    private func createTailNode(birdSize: CGSize) -> SKShapeNode {
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: -birdSize.width / 2.2, y: -birdSize.height * 0.15))
        tailPath.addLine(to: CGPoint(x: -birdSize.width / 2.8, y: 0))
        tailPath.addLine(to: CGPoint(x: -birdSize.width / 2.2, y: birdSize.height * 0.18))
        tailPath.closeSubpath()

        let tail = SKShapeNode(path: tailPath)
        tail.fillColor = SKColor(red: 0.97, green: 0.83, blue: 0.18, alpha: 1)
        tail.strokeColor = SKColor(red: 0.91, green: 0.6, blue: 0.05, alpha: 1)
        tail.lineWidth = 2
        tail.zPosition = 0.4
        tail.name = "tail"
        return tail
    }

    private func startWingAnimation(on wing: SKNode) {
        let flapUp = SKAction.rotate(toAngle: .pi / 7, duration: 0.12, shortestUnitArc: true)
        let flapDown = SKAction.rotate(toAngle: -.pi / 6, duration: 0.12, shortestUnitArc: true)
        let pause = SKAction.wait(forDuration: 0.02)
        let sequence = SKAction.sequence([flapUp, pause, flapDown, pause])
        wing.run(SKAction.repeatForever(sequence), withKey: "flap")
    }

    private func startingBirdPosition() -> CGPoint {
        CGPoint(x: -configuredSize.width * 0.2, y: 0)
    }

    private func recreateScoreLabelIfNeeded() {
        scoreLabel?.removeFromParent()
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.fontSize = 36
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: configuredSize.height / 2 - 80)
        label.text = "0"
        label.zPosition = 10
        addChild(label)
        scoreLabel = label
    }

    private func showMenu() {
        stateLabel?.removeFromParent()
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = "Tap to start"
        label.fontColor = .white
        label.fontSize = 28
        label.position = CGPoint(x: 0, y: configuredSize.height / 4)
        label.zPosition = 10
        addChild(label)
        stateLabel = label
        resumeWingAnimationIfNeeded()
        BuildConfiguration.debugAssert(isSceneReady, "Menu presented without core nodes configured.")
    }

    private func startGame() {
        guard ensureSceneReady() else { return }
        stateLabel?.removeFromParent()
        score = 0
        updateScoreLabel()
        bird?.physicsBody?.isDynamic = true
        bird?.physicsBody?.velocity = .zero
        bird?.zRotation = 0
        applyFlapImpulse()
        resumeWingAnimationIfNeeded()
        gameState = .playing
        spawnPipes()
        BuildConfiguration.debugAssert(gameState == .playing, "Game state should be playing after startGame.")
    }

    private func spawnPipes() {
        removeAction(forKey: spawnActionKey)
        let wait = SKAction.wait(forDuration: 1.8)
        let spawn = SKAction.run { [weak self] in
            self?.createPipePair()
        }
        run(SKAction.repeatForever(SKAction.sequence([spawn, wait])), withKey: spawnActionKey)
    }

    private func createPipePair() {
        guard gameState == .playing else { return }
        BuildConfiguration.debugAssert(isSceneReady, "Pipe spawn attempted while scene not ready.")
        BuildConfiguration.debugAssert(configuredSize != .zero, "Configured size should be known when spawning pipes.")
        let pipeWidth: CGFloat = 70
        let gapHeight = max(configuredSize.height * 0.28, 160)
        let maxOffset = max(configuredSize.height * 0.25, 100)
        let verticalOffset = CGFloat.random(in: -maxOffset...maxOffset)

        let minimumPipeHeight = max(configuredSize.height * 0.2, 120)
        let topPipeHeight = max(configuredSize.height / 2 + gapHeight / 2 + verticalOffset, minimumPipeHeight)
        let bottomPipeHeight = max(configuredSize.height / 2 + gapHeight / 2 - verticalOffset, minimumPipeHeight)

        let topPipe = pipeNode(height: topPipeHeight, anchorY: 0, centerOffsetY: topPipeHeight / 2)
        topPipe.position = CGPoint(x: configuredSize.width / 2 + pipeWidth, y: gapHeight / 2 + verticalOffset)

        let bottomPipe = pipeNode(height: bottomPipeHeight, anchorY: 1, centerOffsetY: -bottomPipeHeight / 2)
        bottomPipe.position = CGPoint(x: configuredSize.width / 2 + pipeWidth, y: -gapHeight / 2 + verticalOffset)

        let gapNode = SKNode()
        gapNode.name = "gap"
        gapNode.position = CGPoint(x: configuredSize.width / 2 + pipeWidth, y: verticalOffset)
        gapNode.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: pipeWidth, height: gapHeight))
        gapNode.physicsBody?.isDynamic = false
        gapNode.physicsBody?.categoryBitMask = scoreCategory
        gapNode.physicsBody?.contactTestBitMask = birdCategory
        gapNode.physicsBody?.collisionBitMask = 0
        gapNode.physicsBody?.usesPreciseCollisionDetection = true

        let distance = configuredSize.width + pipeWidth * 2
        let rawDuration = TimeInterval(distance / PhysicsTuning.pipeTravelSpeed)
        let duration = min(max(rawDuration, 1.6), 3.4)
        let move = SKAction.moveBy(x: -distance, y: 0, duration: duration)
        let remove = SKAction.removeFromParent()
        let pipeSequence = SKAction.sequence([move, remove])

        topPipe.run(pipeSequence)
        bottomPipe.run(pipeSequence)
        gapNode.run(pipeSequence)

        addChild(topPipe)
        addChild(bottomPipe)
        addChild(gapNode)
    }

    private func pipeNode(height: CGFloat, anchorY: CGFloat, centerOffsetY: CGFloat) -> SKSpriteNode {
        let pipeColor = SKColor(red: 0.37, green: 0.75, blue: 0.3, alpha: 1)
        let pipe = SKSpriteNode(color: pipeColor, size: CGSize(width: 70, height: height))
        pipe.name = "pipe"
        pipe.anchorPoint = CGPoint(x: 0.5, y: anchorY)
        pipe.zPosition = 5
        let body = SKPhysicsBody(rectangleOf: pipe.size, center: CGPoint(x: 0, y: centerOffsetY))
        body.isDynamic = false
        body.categoryBitMask = obstacleCategory
        body.contactTestBitMask = birdCategory
        body.collisionBitMask = birdCategory
        pipe.physicsBody = body
        decoratePipe(pipe, anchorY: anchorY)
        return pipe
    }

    private func decoratePipe(_ pipe: SKSpriteNode, anchorY: CGFloat) {
        let lipColor = SKColor(red: 0.30, green: 0.62, blue: 0.23, alpha: 1)
        let highlightColor = SKColor(red: 0.56, green: 0.84, blue: 0.44, alpha: 1)

        let lipHeight: CGFloat = 18
        let lip = SKSpriteNode(color: lipColor, size: CGSize(width: pipe.size.width + 18, height: lipHeight))
        lip.zPosition = pipe.zPosition + 1
        lip.position = anchorY == 0
            ? CGPoint(x: 0, y: lipHeight / 2)
            : CGPoint(x: 0, y: -lipHeight / 2)
        pipe.addChild(lip)

        let stripeWidth: CGFloat = 12
        let stripe = SKSpriteNode(color: highlightColor, size: CGSize(width: stripeWidth, height: pipe.size.height))
        stripe.anchorPoint = CGPoint(x: 0, y: anchorY)
        stripe.position = CGPoint(x: pipe.size.width / 4, y: 0)
        stripe.alpha = 0.55
        stripe.zPosition = pipe.zPosition + 0.5
        pipe.addChild(stripe)

        let shadow = SKSpriteNode(color: lipColor.withAlphaComponent(0.7), size: CGSize(width: stripeWidth, height: pipe.size.height))
        shadow.anchorPoint = CGPoint(x: 1, y: anchorY)
        shadow.position = CGPoint(x: -pipe.size.width / 2.5, y: 0)
        shadow.alpha = 0.45
        shadow.zPosition = pipe.zPosition + 0.4
        pipe.addChild(shadow)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard ensureSceneReady() else { return }
        switch gameState {
        case .menu:
            startGame()
        case .playing:
            applyFlapImpulse()
        case .gameOver:
            resetToMenu()
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if categories == birdCategory | scoreCategory {
            handleScoreContact(contact)
        } else if categories & (obstacleCategory | groundCategory) != 0 {
            handleCrash()
        }
    }

    private func handleScoreContact(_ contact: SKPhysicsContact) {
        guard gameState == .playing else { return }
        score += 1
        updateScoreLabel()
        BuildConfiguration.debugAssert(score > 0, "Score should stay positive after clearing a gate.")
        if contact.bodyA.categoryBitMask == scoreCategory {
            contact.bodyA.node?.removeFromParent()
        }
        if contact.bodyB.categoryBitMask == scoreCategory {
            contact.bodyB.node?.removeFromParent()
        }
    }

    private func handleCrash() {
        guard gameState == .playing else { return }
        BuildConfiguration.debugAssert(isSceneReady, "Crash handling expected active scene nodes.")
        gameState = .gameOver
        removeAction(forKey: spawnActionKey)
        bird?.physicsBody?.collisionBitMask = groundCategory | obstacleCategory
        bird?.childNode(withName: "wing")?.removeAction(forKey: "flap")
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = "Game over • Tap to retry"
        label.fontColor = .white
        label.fontSize = 26
        label.position = CGPoint(x: 0, y: configuredSize.height / 4)
        label.zPosition = 10
        addChild(label)
        stateLabel = label
    }

    private func updateScoreLabel() {
        scoreLabel?.text = "\(score)"
        BuildConfiguration.debugAssert(scoreLabel?.parent === self, "Score label should remain attached to the scene when updated.")
    }

    private func removeAllObstacles() {
        children.filter { $0.name == "pipe" || $0.name == "gap" }.forEach { $0.removeFromParent() }
    }

    private func applyFlapImpulse() {
        guard let physicsBody = bird?.physicsBody else { return }
        var newVelocity = physicsBody.velocity
        newVelocity.dy = max(newVelocity.dy, 0)
        newVelocity.dy = min(newVelocity.dy, PhysicsTuning.maxUpwardVelocity)
        physicsBody.velocity = newVelocity
        physicsBody.applyImpulse(PhysicsTuning.flapImpulse)
        if physicsBody.velocity.dy > PhysicsTuning.maxUpwardVelocity {
            physicsBody.velocity.dy = PhysicsTuning.maxUpwardVelocity
        }
        if let wing = bird?.childNode(withName: "wing"), wing.action(forKey: "flap") == nil {
            startWingAnimation(on: wing)
        }
    }

    private func resumeWingAnimationIfNeeded() {
        guard let wing = bird?.childNode(withName: "wing") else { return }
        if wing.action(forKey: "flap") == nil {
            startWingAnimation(on: wing)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        guard gameState == .playing else { return }
        guard let bird = bird, let physicsBody = bird.physicsBody else { return }

        if physicsBody.velocity.dy < PhysicsTuning.maxDownwardVelocity {
            physicsBody.velocity.dy = PhysicsTuning.maxDownwardVelocity
        }

        let normalizedTilt = max(min(physicsBody.velocity.dy / 600.0, 0.45), -0.65)
        bird.zRotation = normalizedTilt

        let verticalLimit = configuredSize.height / 2
        if bird.position.y > verticalLimit || bird.position.y < -verticalLimit {
            handleCrash()
        }
    }

    private var isSceneReady: Bool {
        bird != nil && bird?.physicsBody != nil && scoreLabel != nil
    }

    @discardableResult
    private func ensureSceneReady() -> Bool {
        if isSceneReady {
            return true
        }

        BuildConfiguration.debugAssert(false, "FlappyBirdScene interaction occurred before nodes were configured. configuredSize=\(configuredSize)")

        if children.isEmpty {
            setupScene()
        } else {
            if bird == nil { recreateBirdIfNeeded() }
            if scoreLabel == nil { recreateScoreLabelIfNeeded() }
        }

        return isSceneReady
    }
}
