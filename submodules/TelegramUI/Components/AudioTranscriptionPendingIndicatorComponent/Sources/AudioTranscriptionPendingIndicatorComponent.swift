import Foundation
import UIKit
import ComponentFlow
import AppBundle
import Display

public final class AudioTranscriptionPendingIndicatorComponent: Component {
    public let color: UIColor
    public let font: UIFont
    
    public init(color: UIColor, font: UIFont) {
        self.color = color
        self.font = font
    }
    
    public static func ==(lhs: AudioTranscriptionPendingIndicatorComponent, rhs: AudioTranscriptionPendingIndicatorComponent) -> Bool {
        if lhs.color != rhs.color {
            return false
        }
        if lhs.font != rhs.font {
            return false
        }
        return true
    }
    
    public final class View: UIView {
        private var component: AudioTranscriptionPendingIndicatorComponent?
        
        private var dotLayers: [SimpleLayer] = []
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            for _ in 0 ..< 3 {
                let dotLayer = SimpleLayer()
                self.dotLayers.append(dotLayer)
                self.layer.addSublayer(dotLayer)
            }
            
            self.dotLayers[0].didEnterHierarchy = { [weak self] in
                self?.restartAnimations()
            }
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func restartAnimations() {
            let beginTime = self.layer.convertTime(CACurrentMediaTime(), from: nil)
            for i in 0 ..< self.dotLayers.count {
                let delay = Double(i) * 0.07
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
                animation.beginTime = beginTime + delay
                animation.fromValue = 0.0 as NSNumber
                animation.toValue = 1.0 as NSNumber
                animation.repeatCount = Float.infinity
                animation.autoreverses = true
                animation.fillMode = .both
                self.dotLayers[i].add(animation, forKey: "idle")
            }
        }
        
        func update(component: AudioTranscriptionPendingIndicatorComponent, availableSize: CGSize, transition: Transition) -> CGSize {
            let dotSize: CGFloat = 2.0
            let spacing: CGFloat = 3.0
            
            var stringSize = NSAttributedString(string: "...", font: component.font, textColor: .black).boundingRect(with: CGSize(width: 100.0, height: 100.0), options: .usesLineFragmentOrigin, context: nil).size
            stringSize.width = ceil(stringSize.width)
            stringSize.height = ceil(stringSize.height)
            
            if self.component?.color != component.color {
                if let dotImage = generateFilledCircleImage(diameter: dotSize, color: component.color) {
                    for dotLayer in self.dotLayers {
                        dotLayer.contents = dotImage.cgImage
                    }
                }
            }
            
            self.component = component

            let size = CGSize(width: dotSize * CGFloat(self.dotLayers.count) + spacing * CGFloat(self.dotLayers.count - 1), height: dotSize)
            
            for i in 0 ..< self.dotLayers.count {
                self.dotLayers[i].frame = CGRect(origin: CGPoint(x: CGFloat(i) * (dotSize + spacing), y: 0.0), size: CGSize(width: dotSize, height: dotSize))
            }
            
            return CGSize(width: min(availableSize.width, stringSize.width), height: min(availableSize.height, size.height))
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: Transition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, transition: transition)
    }
}
