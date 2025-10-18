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
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
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
        newBird.physicsBody?.allowsRotation = false
        newBird.physicsBody?.isDynamic = false
        newBird.physicsBody?.restitution = 0
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
        bird = newBird
        BuildConfiguration.debugAssert(newBird.physicsBody != nil, "Bird should have physics configured after recreation.")
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
        BuildConfiguration.debugAssert(isSceneReady, "Menu presented without core nodes configured.")
    }

    private func startGame() {
        guard ensureSceneReady() else { return }
        stateLabel?.removeFromParent()
        score = 0
        updateScoreLabel()
        bird?.physicsBody?.isDynamic = true
        bird?.physicsBody?.velocity = .zero
        bird?.physicsBody?.applyImpulse(CGVector(dx: 0, dy: 260))
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

        let distance = configuredSize.width + pipeWidth * 2
        let rawDuration = TimeInterval(distance / 160)
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
        return pipe
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard ensureSceneReady() else { return }
        switch gameState {
        case .menu:
            startGame()
        case .playing:
            bird?.physicsBody?.velocity = CGVector(dx: 0, dy: 0)
            bird?.physicsBody?.applyImpulse(CGVector(dx: 0, dy: 260))
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
