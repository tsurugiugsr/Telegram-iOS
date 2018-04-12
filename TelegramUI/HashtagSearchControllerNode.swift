import Display
import AsyncDisplayKit
import UIKit
import Postbox
import TelegramCore

final class HashtagSearchControllerNode: ASDisplayNode {
    private let toolbarBackgroundNode: ASDisplayNode
    private let toolbarSeparatorNode: ASDisplayNode
    private let segmentedControl: UISegmentedControl
    let listNode: ListView
    
    private var chatController: ChatController?
    
    private let account: Account
    private let query: String
    
    private var containerLayout: (ContainerViewLayout, CGFloat)?
    private var enqueuedTransitions: [(ChatListSearchContainerTransition, Bool)] = []
    private var hasValidLayout = false
    
    var navigationBar: NavigationBar?
    
    init(account: Account, peer: Peer?, query: String, theme: PresentationTheme, strings: PresentationStrings) {
        self.account = account
        self.query = query
        self.listNode = ListView()
        
        self.toolbarBackgroundNode = ASDisplayNode()
        self.toolbarBackgroundNode.backgroundColor = theme.rootController.navigationBar.backgroundColor
        
        self.toolbarSeparatorNode = ASDisplayNode()
        self.toolbarSeparatorNode.backgroundColor = theme.rootController.navigationBar.separatorColor
        
        self.segmentedControl = UISegmentedControl(items: [peer?.displayTitle ?? "", strings.HashtagSearch_AllChats])
        self.segmentedControl.tintColor = theme.rootController.navigationBar.accentTextColor
        self.segmentedControl.selectedSegmentIndex = 1
        
        if let peer = peer {
            self.chatController = ChatController(account: account, chatLocation: .peer(peer.id), messageId: nil, botStart: nil, mode: .inline)
        } else {
            self.chatController = nil
        }
        
        super.init()
        
        self.setViewBlock({
            return UITracingLayerView()
        })
        
        self.backgroundColor = theme.chatList.backgroundColor
        
        self.listNode.isHidden = true
        self.addSubnode(self.listNode)
        
        self.segmentedControl.addTarget(self, action: #selector(self.indexChanged), for: .valueChanged)
    }
    
    func enqueueTransition(_ transition: ChatListSearchContainerTransition, firstTime: Bool) {
        enqueuedTransitions.append((transition, firstTime))
        
        if self.hasValidLayout {
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }
    
    private func dequeueTransition() {
        if let (transition, _) = self.enqueuedTransitions.first {
            self.enqueuedTransitions.remove(at: 0)
            
            let options = ListViewDeleteAndInsertOptions()
            
            let displayingResults = transition.displayingResults
            self.listNode.transaction(deleteIndices: transition.deletions, insertIndicesAndItems: transition.insertions, updateIndicesAndItems: transition.updates, options: options, updateSizeAndInsets: nil, updateOpaqueState: nil, completion: { [weak self] _ in
                if let strongSelf = self {
                    if displayingResults != !strongSelf.listNode.isHidden {
                        if strongSelf.listNode.isHidden {
                            strongSelf.listNode.isHidden = false
                            strongSelf.listNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                        }
                    }
                }
            })
        }
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.containerLayout = (layout, navigationBarHeight)
        
        if self.chatController != nil && self.toolbarBackgroundNode.supernode == nil {
            self.addSubnode(self.toolbarBackgroundNode)
            self.addSubnode(self.toolbarSeparatorNode)
            
            self.view.addSubview(self.segmentedControl)
        }
        
        var insets = layout.insets(options: [.input])
        insets.top += navigationBarHeight
        
        let toolbarHeight: CGFloat = 40.0
        let panelY: CGFloat = insets.top - UIScreenPixel - 4.0
        
        transition.updateFrame(node: self.toolbarBackgroundNode, frame: CGRect(origin: CGPoint(x: 0.0, y: panelY), size: CGSize(width: layout.size.width, height: toolbarHeight)))
        transition.updateFrame(node: self.toolbarSeparatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: panelY + toolbarHeight), size: CGSize(width: layout.size.width, height: UIScreenPixel)))
        
        var controlSize = self.segmentedControl.sizeThatFits(layout.size)
        controlSize.width = layout.size.width - 14.0 * 2.0
        
        transition.updateFrame(view: self.segmentedControl, frame: CGRect(origin: CGPoint(x: floor((layout.size.width - controlSize.width) / 2.0), y: panelY + floor((toolbarHeight - controlSize.height) / 2.0)), size: controlSize))
        
        if let chatController = self.chatController {
            insets.top += toolbarHeight - 4.0
            let chatSize = CGSize(width: layout.size.width, height: layout.size.height)
            transition.updateFrame(node: chatController.displayNode, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: chatSize))
            chatController.containerLayoutUpdated(ContainerViewLayout(size: chatSize, metrics: layout.metrics, intrinsicInsets: UIEdgeInsets(top: insets.top, left: 0.0, bottom: layout.intrinsicInsets.bottom, right: 0.0), safeInsets: layout.safeInsets, statusBarHeight: nil, inputHeight: nil, standardInputHeight: 216.0, inputHeightIsInteractivellyChanging: false), transition: .immediate)
            
            if chatController.displayNode.supernode == nil {
                chatController.viewWillAppear(false)
                self.insertSubnode(chatController.displayNode, at: 0)
                chatController.viewDidAppear(false)
                chatController.displayNode.isHidden = true
                
                chatController.beginMessageSearch(self.query)
            }
        }
        
        self.listNode.bounds = CGRect(x: 0.0, y: 0.0, width: layout.size.width, height: layout.size.height)
        self.listNode.position = CGPoint(x: layout.size.width / 2.0, y: layout.size.height / 2.0)
        
        var duration: Double = 0.0
        var curve: UInt = 0
        switch transition {
            case .immediate:
                break
            case let .animated(animationDuration, animationCurve):
                duration = animationDuration
                switch animationCurve {
                case .easeInOut:
                    break
                case .spring:
                    curve = 7
                }
        }
        
        let listViewCurve: ListViewAnimationCurve
        if curve == 7 {
            listViewCurve = .Spring(duration: duration)
        } else {
            listViewCurve = .Default
        }
        
        let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: layout.size, insets: insets, duration: duration, curve: listViewCurve)
        
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        if !hasValidLayout {
            hasValidLayout = true
            while !self.enqueuedTransitions.isEmpty {
                self.dequeueTransition()
            }
        }
    }
    
    @objc private func indexChanged() {
        if self.segmentedControl.selectedSegmentIndex == 0 {
            self.chatController?.displayNode.isHidden = false
            self.listNode.isHidden = true
        } else {
            self.chatController?.displayNode.isHidden = true
            self.listNode.isHidden = false
        }
    }
}
