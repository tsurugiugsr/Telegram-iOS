import Foundation
import UIKit
import Display
import ComponentFlow
import AppBundle
import BundleIconComponent
import AccountContext
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import AvatarNode

private func calculateCircleIntersection(center: CGPoint, otherCenter: CGPoint, radius: CGFloat) -> (point1Angle: CGFloat, point2Angle: CGFloat)? {
    let distanceVector = CGPoint(x: otherCenter.x - center.x, y: otherCenter.y - center.y)
    let distance = sqrt(distanceVector.x * distanceVector.x + distanceVector.y * distanceVector.y)
    if distance > radius * 2.0 || distance == 0.0 {
        return nil
    }
    
    let x1 = center.x
    let y1 = center.y
    let x2 = otherCenter.x
    let y2 = otherCenter.y
    let r1 = radius
    let r2 = radius
    let R = distance
    
    let ix1: CGFloat = 0.5 * (x1 + x2) + (pow(r1, 2.0) - pow(r2, 2.0)) / (2 * pow(R, 2.0)) * (x2 - x1) + 0.5 * sqrt(2.0 * (pow(r1, 2.0) + pow(r2, 2.0)) / pow(R, 2.0) - pow((pow(r1, 2.0) - pow(r2, 2.0)), 2.0) / pow(R, 4.0) - 1) * (y2 - y1)
    let ix2: CGFloat = 0.5 * (x1 + x2) + (pow(r1, 2.0) - pow(r2, 2.0)) / (2 * pow(R, 2.0)) * (x2 - x1) - 0.5 * sqrt(2.0 * (pow(r1, 2.0) + pow(r2, 2.0)) / pow(R, 2.0) - pow((pow(r1, 2.0) - pow(r2, 2.0)), 2.0) / pow(R, 4.0) - 1) * (y2 - y1)
    
    let iy1: CGFloat = 0.5 * (y1 + y2) + (pow(r1, 2.0) - pow(r2, 2.0)) / (2 * pow(R, 2.0)) * (y2 - y1) + 0.5 * sqrt(2.0 * (pow(r1, 2.0) + pow(r2, 2.0)) / pow(R, 2.0) - pow((pow(r1, 2.0) - pow(r2, 2.0)), 2.0) / pow(R, 4.0) - 1) * (x1 - x2)
    let iy2: CGFloat = 0.5 * (y1 + y2) + (pow(r1, 2.0) - pow(r2, 2.0)) / (2 * pow(R, 2.0)) * (y2 - y1) - 0.5 * sqrt(2.0 * (pow(r1, 2.0) + pow(r2, 2.0)) / pow(R, 2.0) - pow((pow(r1, 2.0) - pow(r2, 2.0)), 2.0) / pow(R, 4.0) - 1) * (x1 - x2)
    
    var v1 = CGPoint(x: ix1 - center.x, y: iy1 - center.y)
    let length1 = sqrt(v1.x * v1.x + v1.y * v1.y)
    v1.x /= length1
    v1.y /= length1
    
    var v2 = CGPoint(x: ix2 - center.x, y: iy2 - center.y)
    let length2 = sqrt(v2.x * v2.x + v2.y * v2.y)
    v2.x /= length2
    v2.y /= length2
    
    var point1Angle = atan(v1.y / v1.x)
    var point2Angle = atan(v2.y / v2.x)
    
    if distanceVector.x < 0.0 {
        point1Angle += CGFloat.pi
        point2Angle += CGFloat.pi
    }
    
    return (point1Angle, point2Angle)
}

private func calculateMergingCircleShape(center: CGPoint, leftCenter: CGPoint?, rightCenter: CGPoint?, radius: CGFloat) -> CGPath {
    let leftAngles = leftCenter.flatMap { calculateCircleIntersection(center: center, otherCenter: $0, radius: radius) }
    let rightAngles = rightCenter.flatMap { calculateCircleIntersection(center: center, otherCenter: $0, radius: radius) }
    
    let path = CGMutablePath()
    
    if let leftAngles, let rightAngles {
        path.addArc(center: center, radius: radius, startAngle: leftAngles.point1Angle, endAngle: rightAngles.point2Angle, clockwise: true)
        
        path.move(to: CGPoint(x: center.x + cos(rightAngles.point1Angle) * radius, y: center.y + sin(rightAngles.point1Angle) * radius))
        path.addArc(center: center, radius: radius, startAngle: rightAngles.point1Angle, endAngle: leftAngles.point2Angle, clockwise: true)
    } else if let angles = leftAngles ?? rightAngles {
        path.addArc(center: center, radius: radius, startAngle: angles.point1Angle, endAngle: angles.point2Angle, clockwise: true)
    } else {
        path.addEllipse(in: CGRect(origin: CGPoint(x: center.x - radius, y: center.y - radius), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    }
    
    return path
}

private final class StoryProgressLayer: SimpleShapeLayer {
    private struct Params: Equatable {
        var size: CGSize
        var lineWidth: CGFloat
    }
    
    private var currentParams: Params?
    
    override init() {
        super.init()
        
        self.fillColor = UIColor.white.cgColor
        self.fillRule = .evenOdd
        
        self.fillColor = nil
        self.strokeColor = UIColor.white.cgColor
        self.lineWidth = 2.0
        self.lineCap = .round
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(size: CGSize, lineWidth: CGFloat) {
        let params = Params(
            size: size,
            lineWidth: lineWidth
        )
        if self.currentParams == params {
            return
        }
        self.currentParams = params
        
        let lineWidth: CGFloat = 2.0
        
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: size.width * 0.5, y: size.height * 0.5), radius: size.width * 0.5 - lineWidth * 0.5, startAngle: 0.0, endAngle: CGFloat.pi * 0.25, clockwise: false)
        
        self.path = path
        
        if self.animation(forKey: "rotation") == nil {
            let basicAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
            basicAnimation.duration = 2.0
            basicAnimation.fromValue = NSNumber(value: Float(0.0))
            basicAnimation.toValue = NSNumber(value: Float(Double.pi * 2.0))
            basicAnimation.repeatCount = Float.infinity
            basicAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
            self.add(basicAnimation, forKey: "rotation")
        }
    }
}

public final class StoryPeerListItemComponent: Component {
    public let context: AccountContext
    public let theme: PresentationTheme
    public let strings: PresentationStrings
    public let peer: EnginePeer
    public let hasUnseen: Bool
    public let hasItems: Bool
    public let progress: CGFloat?
    public let collapseFraction: CGFloat
    public let collapsedWidth: CGFloat
    public let leftNeighborDistance: CGFloat?
    public let rightNeighborDistance: CGFloat?
    public let action: (EnginePeer) -> Void
    
    public init(
        context: AccountContext,
        theme: PresentationTheme,
        strings: PresentationStrings,
        peer: EnginePeer,
        hasUnseen: Bool,
        hasItems: Bool,
        progress: CGFloat?,
        collapseFraction: CGFloat,
        collapsedWidth: CGFloat,
        leftNeighborDistance: CGFloat?,
        rightNeighborDistance: CGFloat?,
        action: @escaping (EnginePeer) -> Void
    ) {
        self.context = context
        self.theme = theme
        self.strings = strings
        self.peer = peer
        self.hasUnseen = hasUnseen
        self.hasItems = hasItems
        self.progress = progress
        self.collapseFraction = collapseFraction
        self.collapsedWidth = collapsedWidth
        self.leftNeighborDistance = leftNeighborDistance
        self.rightNeighborDistance = rightNeighborDistance
        self.action = action
    }
    
    public static func ==(lhs: StoryPeerListItemComponent, rhs: StoryPeerListItemComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.strings !== rhs.strings {
            return false
        }
        if lhs.peer != rhs.peer {
            return false
        }
        if lhs.hasUnseen != rhs.hasUnseen {
            return false
        }
        if lhs.hasItems != rhs.hasItems {
            return false
        }
        if lhs.progress != rhs.progress {
            return false
        }
        if lhs.collapseFraction != rhs.collapseFraction {
            return false
        }
        if lhs.collapsedWidth != rhs.collapsedWidth {
            return false
        }
        if lhs.leftNeighborDistance != rhs.leftNeighborDistance {
            return false
        }
        if lhs.rightNeighborDistance != rhs.rightNeighborDistance {
            return false
        }
        return true
    }
    
    public final class View: HighlightTrackingButton {
        private let avatarContainer: UIView
        private var avatarNode: AvatarNode?
        private var avatarAddBadgeView: UIImageView?
        private let avatarShapeLayer: SimpleShapeLayer
        private let indicatorMaskLayer: SimpleLayer
        private let indicatorColorLayer: SimpleGradientLayer
        private var progressLayer: StoryProgressLayer?
        private let indicatorShapeLayer: SimpleShapeLayer
        private let title = ComponentView<Empty>()
        
        private var component: StoryPeerListItemComponent?
        private weak var componentState: EmptyComponentState?
        
        public override init(frame: CGRect) {
            self.avatarContainer = UIView()
            self.avatarContainer.isUserInteractionEnabled = false
            
            self.avatarShapeLayer = SimpleShapeLayer()
            
            self.indicatorColorLayer = SimpleGradientLayer()
            self.indicatorColorLayer.type = .axial
            self.indicatorColorLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
            self.indicatorColorLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
            
            self.indicatorMaskLayer = SimpleLayer()
            self.indicatorShapeLayer = SimpleShapeLayer()
            
            super.init(frame: frame)
            
            self.addSubview(self.avatarContainer)
            
            self.layer.addSublayer(self.indicatorColorLayer)
            self.indicatorMaskLayer.addSublayer(self.indicatorShapeLayer)
            self.indicatorColorLayer.mask = self.indicatorMaskLayer
            
            self.avatarShapeLayer.fillColor = UIColor.white.cgColor
            self.avatarShapeLayer.fillRule = .evenOdd
            
            self.indicatorShapeLayer.fillColor = nil
            self.indicatorShapeLayer.strokeColor = UIColor.white.cgColor
            self.indicatorShapeLayer.lineWidth = 2.0
            self.indicatorShapeLayer.lineCap = .round
            
            self.highligthedChanged = { [weak self] highlighted in
                guard let self else {
                    return
                }
                if highlighted {
                    self.alpha = 0.7
                } else {
                    let previousAlpha = self.alpha
                    self.alpha = 1.0
                    self.layer.animateAlpha(from: previousAlpha, to: self.alpha, duration: 0.25)
                }
            }
            self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
        }
        
        required public init?(coder: NSCoder) {
            preconditionFailure()
        }
        
        @objc private func pressed() {
            guard let component = self.component else {
                return
            }
            component.action(component.peer)
        }
        
        public func transitionView() -> UIView? {
            return self.avatarNode?.view
        }
        
        func update(component: StoryPeerListItemComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: Transition) -> CGSize {
            let hadUnseen = self.component?.hasUnseen
            let hadProgress = self.component?.progress != nil
            let themeUpdated = self.component?.theme !== component.theme
            
            self.component = component
            self.componentState = state
            
            let effectiveWidth: CGFloat = (1.0 - component.collapseFraction) * availableSize.width + component.collapseFraction * component.collapsedWidth
            
            let effectiveScale: CGFloat = 1.0 * (1.0 - component.collapseFraction) + (24.0 / 52.0) * component.collapseFraction
            
            let avatarNode: AvatarNode
            if let current = self.avatarNode {
                avatarNode = current
            } else {
                avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 26.0))
                self.avatarNode = avatarNode
                avatarNode.layer.mask = self.avatarShapeLayer
                avatarNode.isUserInteractionEnabled = false
                self.avatarContainer.addSubview(avatarNode.view)
            }
            
            let avatarSize = CGSize(width: 52.0, height: 52.0)
            let avatarFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - avatarSize.width) * 0.5) + (effectiveWidth - availableSize.width) * 0.5, y: 4.0), size: avatarSize)
            
            transition.setFrame(view: avatarNode.view, frame: CGRect(origin: CGPoint(), size: avatarFrame.size))
            
            let indicatorFrame = avatarFrame.insetBy(dx: -4.0, dy: -4.0)
            
            let indicatorLineWidth: CGFloat = 2.0 * (1.0 - component.collapseFraction) + (1.33 * (1.0 / effectiveScale)) * (component.collapseFraction)
            
            avatarNode.setPeer(
                context: component.context,
                theme: component.theme,
                peer: component.peer
            )
            avatarNode.updateSize(size: avatarSize)
            transition.setPosition(view: self.avatarContainer, position: avatarFrame.center)
            transition.setBounds(view: self.avatarContainer, bounds: CGRect(origin: CGPoint(), size: avatarFrame.size))
            
            let scaledAvatarSize = effectiveScale * (avatarSize.width + 4.0 - indicatorLineWidth * 2.0)
            
            transition.setScale(view: self.avatarContainer, scale: scaledAvatarSize / avatarSize.width)
            
            if component.peer.id == component.context.account.peerId && !component.hasItems && component.progress == nil {
                self.indicatorColorLayer.isHidden = true
                
                let avatarAddBadgeView: UIImageView
                var avatarAddBadgeTransition = transition
                if let current = self.avatarAddBadgeView {
                    avatarAddBadgeView = current
                } else {
                    avatarAddBadgeTransition = .immediate
                    avatarAddBadgeView = UIImageView()
                    self.avatarAddBadgeView = avatarAddBadgeView
                    self.avatarContainer.addSubview(avatarAddBadgeView)
                }
                let badgeSize = CGSize(width: 16.0, height: 16.0)
                if avatarAddBadgeView.image == nil || themeUpdated {
                    avatarAddBadgeView.image = generateImage(badgeSize, rotatedContext: { size, context in
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(component.theme.list.itemCheckColors.fillColor.cgColor)
                        context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
                        
                        context.setStrokeColor(component.theme.list.itemCheckColors.foregroundColor.cgColor)
                        context.setLineWidth(UIScreenPixel * 3.0)
                        context.setLineCap(.round)
                        
                        let lineSize: CGFloat = 9.0 + UIScreenPixel
                        
                        context.move(to: CGPoint(x: size.width * 0.5, y: (size.height - lineSize) * 0.5))
                        context.addLine(to: CGPoint(x: size.width * 0.5, y: (size.height - lineSize) * 0.5 + lineSize))
                        context.strokePath()
                        
                        context.move(to: CGPoint(x: (size.width - lineSize) * 0.5, y: size.height * 0.5))
                        context.addLine(to: CGPoint(x: (size.width - lineSize) * 0.5 + lineSize, y: size.height * 0.5))
                        context.strokePath()
                    })
                }
                avatarAddBadgeTransition.setFrame(view: avatarAddBadgeView, frame: CGRect(origin: CGPoint(x: avatarFrame.width - 1.0 - badgeSize.width, y: avatarFrame.height - 1.0 - badgeSize.height), size: badgeSize))
            } else {
                if indicatorColorLayer.isHidden {
                    self.indicatorColorLayer.isHidden = false
                }
                
                if let avatarAddBadgeView = self.avatarAddBadgeView {
                    self.avatarAddBadgeView = nil
                    avatarAddBadgeView.removeFromSuperview()
                }
            }
            
            if hadUnseen != component.hasUnseen || hadProgress != (component.progress != nil) {
                let locations: [CGFloat] = [0.0, 1.0]
                let colors: [CGColor]
                
                if component.hasUnseen || component.progress != nil {
                    colors = [UIColor(rgb: 0x34C76F).cgColor, UIColor(rgb: 0x3DA1FD).cgColor]
                } else {
                    colors = [UIColor(rgb: 0xD8D8E1).cgColor, UIColor(rgb: 0xD8D8E1).cgColor]
                }
                
                self.indicatorColorLayer.locations = locations.map { $0 as NSNumber }
                self.indicatorColorLayer.colors = colors
            }
            
            transition.setPosition(layer: self.indicatorColorLayer, position: indicatorFrame.center)
            transition.setBounds(layer: self.indicatorColorLayer, bounds: CGRect(origin: CGPoint(), size: indicatorFrame.size))
            transition.setPosition(layer: self.indicatorShapeLayer, position: CGPoint(x: indicatorFrame.width * 0.5, y: indicatorFrame.height * 0.5))
            transition.setBounds(layer: self.indicatorShapeLayer, bounds: CGRect(origin: CGPoint(), size: indicatorFrame.size))
            transition.setScale(layer: self.indicatorColorLayer, scale: effectiveScale)
            
            let indicatorCenter = CGRect(origin: CGPoint(), size: indicatorFrame.size).center
            
            var mappedLeftCenter: CGPoint?
            var mappedRightCenter: CGPoint?
            
            if let leftNeighborDistance = component.leftNeighborDistance {
                mappedLeftCenter = CGPoint(x: indicatorCenter.x - leftNeighborDistance * (1.0 / effectiveScale), y: indicatorCenter.y)
            }
            if let rightNeighborDistance = component.rightNeighborDistance {
                mappedRightCenter = CGPoint(x: indicatorCenter.x + rightNeighborDistance * (1.0 / effectiveScale), y: indicatorCenter.y)
            }
            
            let avatarPath = CGMutablePath()
            avatarPath.addEllipse(in: CGRect(origin: CGPoint(), size: avatarSize).insetBy(dx: -1.0, dy: -1.0))
            if component.peer.id == component.context.account.peerId && !component.hasItems && component.progress == nil {
                let cutoutSize: CGFloat = 18.0 + UIScreenPixel * 2.0
                avatarPath.addEllipse(in: CGRect(origin: CGPoint(x: avatarSize.width - cutoutSize + UIScreenPixel, y: avatarSize.height - cutoutSize + UIScreenPixel), size: CGSize(width: cutoutSize, height: cutoutSize)))
            } else if let mappedRightCenter {
                avatarPath.addEllipse(in: CGRect(origin: CGPoint(), size: avatarSize).insetBy(dx: -indicatorLineWidth, dy: -indicatorLineWidth).offsetBy(dx: abs(mappedRightCenter.x - indicatorCenter.x), dy: 0.0))
            }
            self.avatarShapeLayer.path = avatarPath
            
            self.indicatorShapeLayer.path = calculateMergingCircleShape(center: indicatorCenter, leftCenter: mappedLeftCenter, rightCenter: mappedRightCenter, radius: indicatorFrame.width * 0.5 - indicatorLineWidth * 0.5)
            
            //TODO:localize
            let titleString: String
            if component.peer.id == component.context.account.peerId {
                if let _ = component.progress {
                    titleString = "Uploading..."
                } else {
                    titleString = "My story"
                }
            } else {
                titleString = component.peer.compactDisplayTitle
            }
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(Text(text: titleString, font: Font.regular(11.0), color: component.theme.list.itemPrimaryTextColor)),
                environment: {},
                containerSize: CGSize(width: availableSize.width + 4.0, height: 100.0)
            )
            let titleFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - titleSize.width) * 0.5) + (effectiveWidth - availableSize.width) * 0.25, y: indicatorFrame.midY + (indicatorFrame.height * 0.5 + 3.0) * effectiveScale), size: titleSize)
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    titleView.layer.anchorPoint = CGPoint()
                    titleView.isUserInteractionEnabled = false
                    self.addSubview(titleView)
                }
                transition.setPosition(view: titleView, position: titleFrame.origin)
                titleView.bounds = CGRect(origin: CGPoint(), size: titleFrame.size)
                transition.setScale(view: titleView, scale: effectiveScale)
                transition.setAlpha(view: titleView, alpha: 1.0 - component.collapseFraction)
            }
            
            if component.progress != nil {
                var progressTransition = transition
                let progressLayer: StoryProgressLayer
                if let current = self.progressLayer {
                    progressLayer = current
                } else {
                    progressTransition = .immediate
                    progressLayer = StoryProgressLayer()
                    self.progressLayer = progressLayer
                    self.indicatorMaskLayer.addSublayer(progressLayer)
                }
                let progressFrame = CGRect(origin: CGPoint(), size: indicatorFrame.size)
                progressTransition.setFrame(layer: progressLayer, frame: progressFrame)
                progressLayer.update(size: progressFrame.size, lineWidth: 4.0)
                
                self.indicatorShapeLayer.opacity = 0.0
            } else {
                self.indicatorShapeLayer.opacity = 1.0
                
                if let progressLayer = self.progressLayer {
                    self.progressLayer = nil
                    if transition.animation.isImmediate {
                        progressLayer.removeFromSuperlayer()
                    } else {
                        progressLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: { [weak progressLayer] _ in
                            progressLayer?.removeFromSuperlayer()
                        })
                    }
                }
            }
            
            return availableSize
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: Transition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
