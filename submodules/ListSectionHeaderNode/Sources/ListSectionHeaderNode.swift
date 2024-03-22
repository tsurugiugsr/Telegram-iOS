import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData

private let titleFont = Font.regular(13.0)
private let actionFont = Font.regular(13.0)

public enum ListSectionHeaderActionType {
    case generic
    case destructive
}

public final class ListSectionHeaderNode: ASDisplayNode {
    private let backgroundLayer: SimpleLayer
    private let label: ImmediateTextNode
    private var actionButtonLabel: ImmediateTextNode?
    private var actionButton: HighlightableButtonNode?
    private var theme: PresentationTheme
    
    private var validLayout: (size: CGSize, leftInset: CGFloat, rightInset: CGFloat)?
    
    public var title: String? {
        didSet {
            self.label.attributedText = NSAttributedString(string: self.title ?? "", font: titleFont, textColor: self.theme.chatList.sectionHeaderTextColor)
            self.label.accessibilityLabel = self.title
            
            if let (size, leftInset, rightInset) = self.validLayout {
                self.updateLayout(size: size, leftInset: leftInset, rightInset: rightInset)
            }
        }
    }
    
    public var actionType: ListSectionHeaderActionType = .generic {
        didSet {
            self.updateAction()
        }
    }
    
    public var action: String? {
        didSet {
            self.updateAction()
        }
    }
    
    private func updateAction() {
        if (self.action != nil) != (self.actionButton != nil) {
            if let _ = self.action {
                let actionButtonLabel = ImmediateTextNode()
                actionButtonLabel.displaysAsynchronously = false
                self.addSubnode(actionButtonLabel)
                self.actionButtonLabel = actionButtonLabel
                let actionButton = HighlightableButtonNode()
                self.addSubnode(actionButton)
                self.actionButton = actionButton
                actionButton.addTarget(self, action: #selector(self.actionButtonPressed), forControlEvents: .touchUpInside)
            } else {
                if let actionButtonLabel = self.actionButtonLabel {
                    self.actionButtonLabel = nil
                    actionButtonLabel.removeFromSupernode()
                }
                if let actionButton = self.actionButton {
                    self.actionButton = nil
                    actionButton.removeFromSupernode()
                }
            }
        }
        if let action = self.action {
            let actionColor: UIColor
            switch self.actionType {
                case .generic:
                    actionColor = self.theme.chatList.sectionHeaderTextColor
                case .destructive:
                    actionColor = self.theme.list.itemDestructiveColor
            }
            self.actionButtonLabel?.attributedText = NSAttributedString(string: action, font: actionFont, textColor: actionColor)
            self.actionButton?.accessibilityLabel = action
            self.actionButton?.accessibilityTraits = [.button]
        }
        
        if let (size, leftInset, rightInset) = self.validLayout {
            self.updateLayout(size: size, leftInset: leftInset, rightInset: rightInset)
        }
    }
    
    public var activateAction: (() -> Void)?
    
    public init(theme: PresentationTheme) {
        self.theme = theme
        
        self.backgroundLayer = SimpleLayer()
        
        self.label = ImmediateTextNode()
        self.label.isUserInteractionEnabled = false
        self.label.isAccessibilityElement = true
        self.label.displaysAsynchronously = false
        
        super.init()
        
        self.layer.addSublayer(self.backgroundLayer)
        
        self.addSubnode(self.label)
        
        self.backgroundLayer.backgroundColor = theme.chatList.sectionHeaderFillColor.cgColor
    }
    
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let actionButton = self.actionButton {
            if actionButton.frame.contains(point) {
                return actionButton.view
            }
        }
        
        return super.hitTest(point, with: event)
    }
    
    public func updateTheme(theme: PresentationTheme) {
        if self.theme !== theme {
            self.theme = theme
            
            self.label.attributedText = NSAttributedString(string: self.title ?? "", font: titleFont, textColor: self.theme.chatList.sectionHeaderTextColor)
            
            self.backgroundLayer.backgroundColor = theme.chatList.sectionHeaderFillColor.cgColor
            if let action = self.action {
                self.actionButtonLabel?.attributedText = NSAttributedString(string: action, font: actionFont, textColor: self.theme.chatList.sectionHeaderTextColor)
            }
            
            if let (size, leftInset, rightInset) = self.validLayout {
                self.updateLayout(size: size, leftInset: leftInset, rightInset: rightInset)
            }
        }
    }
    
    public func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat) {
        self.validLayout = (size, leftInset, rightInset)
        let labelSize = self.label.updateLayout(CGSize(width: max(0.0, size.width - leftInset - rightInset - 18.0), height: size.height))
        self.label.frame = CGRect(origin: CGPoint(x: leftInset + 16.0, y: 6.0 + UIScreenPixel), size: CGSize(width: labelSize.width, height: size.height))
        
        if let actionButton = self.actionButton, let actionButtonLabel = self.actionButtonLabel {
            let buttonSize = actionButtonLabel.updateLayout(CGSize(width: size.width, height: size.height))
            actionButtonLabel.frame = CGRect(origin: CGPoint(x: size.width - rightInset - 16.0 - buttonSize.width, y: 6.0 + UIScreenPixel), size: buttonSize)
            actionButton.frame = CGRect(origin: CGPoint(x: size.width - rightInset - 16.0 - buttonSize.width, y: 6.0 + UIScreenPixel), size: buttonSize)
        }
        
        self.backgroundLayer.frame = CGRect(origin: CGPoint(x: 0.0, y: -UIScreenPixel), size: CGSize(width: size.width, height: size.height + UIScreenPixel))
    }
    
    @objc private func actionButtonPressed() {
        self.activateAction?()
    }
}
