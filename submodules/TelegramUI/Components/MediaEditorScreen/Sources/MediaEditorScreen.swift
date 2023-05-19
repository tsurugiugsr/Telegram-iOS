import Foundation
import UIKit
import Display
import AsyncDisplayKit
import ComponentFlow
import SwiftSignalKit
import ViewControllerComponent
import ComponentDisplayAdapters
import TelegramPresentationData
import AccountContext
import TelegramCore
import MultilineTextComponent
import DrawingUI
import MediaEditor
import Photos
import LottieAnimationComponent
import MessageInputPanelComponent
import EntityKeyboard
import TooltipUI
import BlurredBackgroundComponent
import AvatarNode
import ShareWithPeersScreen
import PresentationDataUtils

enum DrawingScreenType {
    case drawing
    case text
    case sticker
}

private let privacyButtonTag = GenericComponentViewTag()
private let muteButtonTag = GenericComponentViewTag()
private let saveButtonTag = GenericComponentViewTag()

final class MediaEditorScreenComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment
    
    let context: AccountContext
    let mediaEditor: MediaEditor?
    let privacy: EngineStoryPrivacy
    let timeout: Bool
    let openDrawing: (DrawingScreenType) -> Void
    let openTools: () -> Void
    
    init(
        context: AccountContext,
        mediaEditor: MediaEditor?,
        privacy: EngineStoryPrivacy,
        timeout: Bool,
        openDrawing: @escaping (DrawingScreenType) -> Void,
        openTools: @escaping () -> Void
    ) {
        self.context = context
        self.mediaEditor = mediaEditor
        self.privacy = privacy
        self.timeout = timeout
        self.openDrawing = openDrawing
        self.openTools = openTools
    }
    
    static func ==(lhs: MediaEditorScreenComponent, rhs: MediaEditorScreenComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.privacy != rhs.privacy {
            return false
        }
        if lhs.timeout != rhs.timeout {
            return false
        }
        return true
    }

    final class State: ComponentState {
        enum ImageKey: Hashable {
            case draw
            case text
            case sticker
            case tools
            case done
        }
        private var cachedImages: [ImageKey: UIImage] = [:]
        func image(_ key: ImageKey) -> UIImage {
            if let image = self.cachedImages[key] {
                return image
            } else {
                var image: UIImage
                switch key {
                case .draw:
                    image = generateTintedImage(image: UIImage(bundleImageName: "Media Editor/Pencil"), color: .white)!
                case .text:
                    image = generateTintedImage(image: UIImage(bundleImageName: "Media Editor/AddText"), color: .white)!
                case .sticker:
                    image = generateTintedImage(image: UIImage(bundleImageName: "Media Editor/AddSticker"), color: .white)!
                case .tools:
                    image = generateTintedImage(image: UIImage(bundleImageName: "Media Editor/Tools"), color: .white)!
                case .done:
                    let accentColor = self.context.sharedContext.currentPresentationData.with { $0 }.theme.chat.inputPanel.panelControlAccentColor
                    image = generateImage(CGSize(width: 33.0, height: 33.0), rotatedContext: { size, context in
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(accentColor.cgColor)
                        context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
                        context.setBlendMode(.copy)
                        context.setStrokeColor(UIColor.white.cgColor)
                        context.setLineWidth(2.0)
                        context.setLineCap(.round)
                        context.setLineJoin(.round)
                        
                        context.translateBy(x: 5.45, y: 4.0)
                        
                        context.saveGState()
                        context.translateBy(x: 4.0, y: 4.0)
                        let _ = try? drawSvgPath(context, path: "M1,7 L7,1 L13,7 S ")
                        context.restoreGState()
                        
                        context.saveGState()
                        context.translateBy(x: 10.0, y: 4.0)
                        let _ = try? drawSvgPath(context, path: "M1,16 V1 S ")
                        context.restoreGState()
                    })!
                }
                cachedImages[key] = image
                return image
            }
        }
        
        let context: AccountContext
        var playerStateDisposable: Disposable?
        var playerState: MediaEditorPlayerState?
        
        init(context: AccountContext, mediaEditor: MediaEditor?) {
            self.context = context
            
            super.init()
            
            if let mediaEditor {
                self.playerStateDisposable = (mediaEditor.playerState(framesCount: 16)
                |> deliverOnMainQueue).start(next: { [weak self] playerState in
                    if let self {
                        self.playerState = playerState
                        self.updated()
                    }
                })
            }
        }
        
        deinit {
            self.playerStateDisposable?.dispose()
        }
    }
    
    func makeState() -> State {
        return State(
            context: self.context,
            mediaEditor: self.mediaEditor
        )
    }
    
    public final class View: UIView {
        private let cancelButton = ComponentView<Empty>()
        private let drawButton = ComponentView<Empty>()
        private let textButton = ComponentView<Empty>()
        private let stickerButton = ComponentView<Empty>()
        private let toolsButton = ComponentView<Empty>()
        private let doneButton = ComponentView<Empty>()
        
        private let inputPanel = ComponentView<Empty>()
        private let inputPanelExternalState = MessageInputPanelComponent.ExternalState()
        
        private let scrubber = ComponentView<Empty>()
        
        private let privacyButton = ComponentView<Empty>()
        private let muteButton = ComponentView<Empty>()
        private let saveButton = ComponentView<Empty>()
        
        private var component: MediaEditorScreenComponent?
        private weak var state: State?
        private var environment: ViewControllerComponentContainer.Environment?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            self.backgroundColor = .clear
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func animateInFromCamera() {
            if let view = self.cancelButton.view {
                view.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                view.layer.animateScale(from: 0.1, to: 1.0, duration: 0.2)
            }
            
            let buttons = [
                self.drawButton,
                self.textButton,
                self.stickerButton,
                self.toolsButton
            ]
            
            var delay: Double = 0.0
            for button in buttons {
                if let view = button.view {
                    view.layer.animatePosition(from: CGPoint(x: 0.0, y: 64.0), to: .zero, duration: 0.3, delay: delay, timingFunction: kCAMediaTimingFunctionSpring, additive: true)
                    view.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2, delay: delay)
                    view.layer.animateScale(from: 0.1, to: 1.0, duration: 0.2, delay: delay)
                    delay += 0.05
                }
            }
            
            if let view = self.doneButton.view {
                view.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                view.layer.animateScale(from: 0.1, to: 1.0, duration: 0.2)
            }
            
            if let view = self.inputPanel.view {
                view.layer.animatePosition(from: CGPoint(x: 0.0, y: 44.0), to: .zero, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, additive: true)
                view.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                view.layer.animateScale(from: 0.1, to: 1.0, duration: 0.2)
            }
            
            if let view = self.saveButton.view {
                view.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                view.layer.animateScale(from: 0.1, to: 1.0, duration: 0.2)
            }
            
            if let view = self.muteButton.view {
                view.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                view.layer.animateScale(from: 0.1, to: 1.0, duration: 0.2)
            }
            
            if let view = self.privacyButton.view {
                view.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                view.layer.animateScale(from: 0.1, to: 1.0, duration: 0.2)
            }
        }
        
        func animateOutToCamera() {
            let transition = Transition(animation: .curve(duration: 0.2, curve: .easeInOut))
            if let view = self.cancelButton.view {
                transition.setAlpha(view: view, alpha: 0.0)
                transition.setScale(view: view, scale: 0.1)
            }
            
            let buttons = [
                self.drawButton,
                self.textButton,
                self.stickerButton,
                self.toolsButton
            ]
            
            for button in buttons {
                if let view = button.view {
                    view.layer.animatePosition(from: .zero, to: CGPoint(x: 0.0, y: 64.0), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, additive: true)
                    view.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
                    view.layer.animateScale(from: 1.0, to: 0.1, duration: 0.2)
                }
            }
            
            if let view = self.doneButton.view {
                transition.setAlpha(view: view, alpha: 0.0)
                transition.setScale(view: view, scale: 0.1)
            }
            
            if let view = self.inputPanel.view {
                view.layer.animatePosition(from: .zero, to: CGPoint(x: 0.0, y: 44.0), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, additive: true)
                view.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
                view.layer.animateScale(from: 1.0, to: 0.1, duration: 0.2)
            }
            
            if let view = self.saveButton.view {
                transition.setAlpha(view: view, alpha: 0.0)
                transition.setScale(view: view, scale: 0.1)
            }
            
            if let view = self.muteButton.view {
                transition.setAlpha(view: view, alpha: 0.0)
                transition.setScale(view: view, scale: 0.1)
            }
            
            if let view = self.privacyButton.view {
                transition.setAlpha(view: view, alpha: 0.0)
                transition.setScale(view: view, scale: 0.1)
            }
            
            if let view = self.scrubber.view {
                view.layer.animatePosition(from: .zero, to: CGPoint(x: 0.0, y: 44.0), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, additive: true)
                view.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
                view.layer.animateScale(from: 1.0, to: 0.1, duration: 0.2)
            }
        }
        
        func animateOutToTool() {
            let transition = Transition(animation: .curve(duration: 0.2, curve: .easeInOut))
            if let view = self.cancelButton.view {
                view.alpha = 0.0
            }
            
            let buttons = [
                self.drawButton,
                self.textButton,
                self.stickerButton,
                self.toolsButton
            ]
            
            for button in buttons {
                if let view = button.view {
                    view.layer.animatePosition(from: .zero, to: CGPoint(x: 0.0, y: -44.0), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, additive: true)
                    transition.setAlpha(view: view, alpha: 0.0)
                    view.layer.animateScale(from: 1.0, to: 0.1, duration: 0.2)
                }
            }
            
            if let view = self.doneButton.view {
                transition.setAlpha(view: view, alpha: 0.0)
                transition.setScale(view: view, scale: 0.1)
            }
            
            if let view = self.inputPanel.view {
                transition.setAlpha(view: view, alpha: 0.0)
                view.layer.animateScale(from: 1.0, to: 0.1, duration: 0.2)
            }
            
            if let view = self.saveButton.view {
                transition.setAlpha(view: view, alpha: 0.0)
                transition.setScale(view: view, scale: 0.1)
            }
            
            if let view = self.muteButton.view {
                transition.setAlpha(view: view, alpha: 0.0)
                transition.setScale(view: view, scale: 0.1)
            }
            
            if let view = self.privacyButton.view {
                transition.setAlpha(view: view, alpha: 0.0)
                transition.setScale(view: view, scale: 0.1)
            }
            
            if let view = self.scrubber.view {
                transition.setAlpha(view: view, alpha: 0.0)
                view.layer.animateScale(from: 1.0, to: 0.1, duration: 0.2)
            }
        }
        
        func animateInFromTool() {
            let transition = Transition(animation: .curve(duration: 0.2, curve: .easeInOut))
            if let view = self.cancelButton.view {
                view.alpha = 1.0
            }
            
            let buttons = [
                self.drawButton,
                self.textButton,
                self.stickerButton,
                self.toolsButton
            ]
            
            for button in buttons {
                if let view = button.view {
                    view.layer.animatePosition(from: CGPoint(x: 0.0, y: -44.0), to: .zero, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, additive: true)
                    transition.setAlpha(view: view, alpha: 1.0)
                    view.layer.animateScale(from: 0.1, to: 1.0, duration: 0.2)
                }
            }
            
            if let view = self.doneButton.view {
                transition.setAlpha(view: view, alpha: 1.0)
                transition.setScale(view: view, scale: 1.0)
            }
            
            if let view = self.inputPanel.view {
                transition.setAlpha(view: view, alpha: 1.0)
                view.layer.animateScale(from: 0.0, to: 1.0, duration: 0.2)
            }
            
            if let view = self.saveButton.view {
                transition.setAlpha(view: view, alpha: 1.0)
                transition.setScale(view: view, scale: 1.0)
            }
            
            if let view = self.muteButton.view {
                transition.setAlpha(view: view, alpha: 1.0)
                transition.setScale(view: view, scale: 1.0)
            }
            
            if let view = self.privacyButton.view {
                transition.setAlpha(view: view, alpha: 1.0)
                transition.setScale(view: view, scale: 1.0)
            }
            
            if let view = self.scrubber.view {
                transition.setAlpha(view: view, alpha: 1.0)
                view.layer.animateScale(from: 0.0, to: 1.0, duration: 0.2)
            }
        }
        
        func update(component: MediaEditorScreenComponent, availableSize: CGSize, state: State, environment: Environment<ViewControllerComponentContainer.Environment>, transition: Transition) -> CGSize {
            let environment = environment[ViewControllerComponentContainer.Environment.self].value
            self.environment = environment
            
            self.component = component
            self.state = state
            
            let openDrawing = component.openDrawing
            let openTools = component.openTools
            
            let buttonSideInset: CGFloat = 10.0
            let buttonBottomInset: CGFloat = 8.0
            
            let cancelButtonSize = self.cancelButton.update(
                transition: transition,
                component: AnyComponent(Button(
                    content: AnyComponent(
                        LottieAnimationComponent(
                            animation: LottieAnimationComponent.AnimationItem(
                                name: "media_backToCancel",
                                mode: .still(position: .begin),
                                range: nil
                            ),
                            colors: ["__allcolors__": .white],
                            size: CGSize(width: 33.0, height: 33.0)
                        )
                    ),
                    action: {
                        guard let controller = environment.controller() as? MediaEditorScreen else {
                            return
                        }
                        controller.maybePresentDiscardAlert()
                    }
                )),
                environment: {},
                containerSize: CGSize(width: 44.0, height: 44.0)
            )
            let cancelButtonFrame = CGRect(
                origin: CGPoint(x: buttonSideInset, y: availableSize.height - environment.safeInsets.bottom + buttonBottomInset),
                size: cancelButtonSize
            )
            if let cancelButtonView = self.cancelButton.view {
                if cancelButtonView.superview == nil {
                    self.addSubview(cancelButtonView)
                }
                transition.setPosition(view: cancelButtonView, position: cancelButtonFrame.center)
                transition.setBounds(view: cancelButtonView, bounds: CGRect(origin: .zero, size: cancelButtonFrame.size))
            }
            
            let doneButtonSize = self.doneButton.update(
                transition: transition,
                component: AnyComponent(Button(
                    content: AnyComponent(Image(
                        image: state.image(.done),
                        size: CGSize(width: 33.0, height: 33.0)
                    )),
                    action: { [weak self] in
                        guard let self, let controller = environment.controller() as? MediaEditorScreen else {
                            return
                        }
                        guard let inputPanelView = self.inputPanel.view as? MessageInputPanelComponent.View else {
                            return
                        }
                        var inputText = NSAttributedString(string: "")
                        switch inputPanelView.getSendMessageInput() {
                        case let .text(text):
                            inputText = NSAttributedString(string: text)
                        }
                        
                        controller.requestCompletion(caption: inputText, animated: true)
                    }
                )),
                environment: {},
                containerSize: CGSize(width: 44.0, height: 44.0)
            )
            let doneButtonFrame = CGRect(
                origin: CGPoint(x: availableSize.width - buttonSideInset - doneButtonSize.width, y: availableSize.height - environment.safeInsets.bottom + buttonBottomInset),
                size: doneButtonSize
            )
            if let doneButtonView = self.doneButton.view {
                if doneButtonView.superview == nil {
                    self.addSubview(doneButtonView)
                }
                transition.setPosition(view: doneButtonView, position: doneButtonFrame.center)
                transition.setBounds(view: doneButtonView, bounds: CGRect(origin: .zero, size: doneButtonFrame.size))
            }
            
            let drawButtonSize = self.drawButton.update(
                transition: transition,
                component: AnyComponent(Button(
                    content: AnyComponent(Image(
                        image: state.image(.draw),
                        size: CGSize(width: 30.0, height: 30.0)
                    )),
                    action: {
                        openDrawing(.drawing)
                    }
                )),
                environment: {},
                containerSize: CGSize(width: 40.0, height: 40.0)
            )
            let drawButtonFrame = CGRect(
                origin: CGPoint(x: floorToScreenPixels(availableSize.width / 4.0 - 3.0 - drawButtonSize.width / 2.0), y: availableSize.height - environment.safeInsets.bottom + buttonBottomInset),
                size: drawButtonSize
            )
            if let drawButtonView = self.drawButton.view {
                if drawButtonView.superview == nil {
                    self.addSubview(drawButtonView)
                }
                transition.setFrame(view: drawButtonView, frame: drawButtonFrame)
            }
            
            let textButtonSize = self.textButton.update(
                transition: transition,
                component: AnyComponent(Button(
                    content: AnyComponent(Image(
                        image: state.image(.text),
                        size: CGSize(width: 30.0, height: 30.0)
                    )),
                    action: {
                        openDrawing(.text)
                    }
                )),
                environment: {},
                containerSize: CGSize(width: 40.0, height: 40.0)
            )
            let textButtonFrame = CGRect(
                origin: CGPoint(x: floorToScreenPixels(availableSize.width / 2.5 + 5.0 - textButtonSize.width / 2.0), y: availableSize.height - environment.safeInsets.bottom + buttonBottomInset),
                size: textButtonSize
            )
            if let textButtonView = self.textButton.view {
                if textButtonView.superview == nil {
                    self.addSubview(textButtonView)
                }
                transition.setFrame(view: textButtonView, frame: textButtonFrame)
            }
            
            let stickerButtonSize = self.stickerButton.update(
                transition: transition,
                component: AnyComponent(Button(
                    content: AnyComponent(Image(
                        image: state.image(.sticker),
                        size: CGSize(width: 30.0, height: 30.0)
                    )),
                    action: {
                        openDrawing(.sticker)
                    }
                )),
                environment: {},
                containerSize: CGSize(width: 40.0, height: 40.0)
            )
            let stickerButtonFrame = CGRect(
                origin: CGPoint(x: floorToScreenPixels(availableSize.width - availableSize.width / 2.5 - 5.0 - stickerButtonSize.width / 2.0), y: availableSize.height - environment.safeInsets.bottom + buttonBottomInset),
                size: stickerButtonSize
            )
            if let stickerButtonView = self.stickerButton.view {
                if stickerButtonView.superview == nil {
                    self.addSubview(stickerButtonView)
                }
                transition.setFrame(view: stickerButtonView, frame: stickerButtonFrame)
            }
            
            let toolsButtonSize = self.toolsButton.update(
                transition: transition,
                component: AnyComponent(Button(
                    content: AnyComponent(Image(
                        image: state.image(.tools),
                        size: CGSize(width: 30.0, height: 30.0)
                    )),
                    action: {
                        openTools()
                    }
                )),
                environment: {},
                containerSize: CGSize(width: 40.0, height: 40.0)
            )
            let toolsButtonFrame = CGRect(
                origin: CGPoint(x: floorToScreenPixels(availableSize.width / 4.0 * 3.0 + 3.0 - toolsButtonSize.width / 2.0), y: availableSize.height - environment.safeInsets.bottom + buttonBottomInset),
                size: toolsButtonSize
            )
            if let toolsButtonView = self.toolsButton.view {
                if toolsButtonView.superview == nil {
                    self.addSubview(toolsButtonView)
                }
                transition.setFrame(view: toolsButtonView, frame: toolsButtonFrame)
            }
            
            let mediaEditor = component.mediaEditor
            
            var scrubberBottomInset: CGFloat = 0.0
            if let playerState = state.playerState {
                let scrubberInset: CGFloat = 9.0
                let scrubberSize = self.scrubber.update(
                    transition: transition,
                    component: AnyComponent(VideoScrubberComponent(
                        context: component.context,
                        duration: playerState.duration,
                        startPosition: playerState.timeRange?.lowerBound ?? 0.0,
                        endPosition: playerState.timeRange?.upperBound ?? playerState.duration,
                        position: playerState.position,
                        frames: playerState.frames,
                        framesUpdateTimestamp: playerState.framesUpdateTimestamp,
                        startPositionUpdated: { [weak mediaEditor] position, done in
                            if let mediaEditor {
                                mediaEditor.setVideoTrimStart(position)
                                mediaEditor.seek(position, andPlay: done)
                            }
                        },
                        endPositionUpdated: { [weak mediaEditor] position, done in
                            if let mediaEditor {
                                mediaEditor.setVideoTrimEnd(position)
                                if done {
                                    let start = mediaEditor.values.videoTrimRange?.lowerBound ?? 0.0
                                    mediaEditor.seek(start, andPlay: true)
                                } else {
                                    mediaEditor.seek(position, andPlay: false)
                                }
                            }
                        },
                        positionUpdated: { position, done in
                            if let mediaEditor {
                                mediaEditor.seek(position, andPlay: done)
                            }
                        }
                    )),
                    environment: {},
                    containerSize: CGSize(width: availableSize.width - scrubberInset * 2.0, height: availableSize.height)
                )
                
                let scrubberFrame = CGRect(origin: CGPoint(x: scrubberInset, y: availableSize.height - environment.safeInsets.bottom - scrubberSize.height - 8.0), size: scrubberSize)
                if let scrubberView = self.scrubber.view {
                    if scrubberView.superview == nil {
                        self.addSubview(scrubberView)
                    }
                    transition.setFrame(view: scrubberView, frame: scrubberFrame)
                }
                
                scrubberBottomInset = scrubberSize.height + 10.0
            } else {
                
            }
            
            self.inputPanel.parentState = state
            let inputPanelSize = self.inputPanel.update(
                transition: transition,
                component: AnyComponent(MessageInputPanelComponent(
                    externalState: self.inputPanelExternalState,
                    context: component.context,
                    theme: environment.theme,
                    strings: environment.strings,
                    style: .editor,
                    placeholder: "Add a caption...",
                    presentController: { [weak self] c in
                        guard let self, let _ = self.component else {
                            return
                        }
                        //component.presentController(c)
                    },
                    sendMessageAction: { [weak self] in
                        guard let self else {
                            return
                        }
                        self.endEditing(true)
                    },
                    setMediaRecordingActive: nil,
                    attachmentAction: nil,
                    reactionAction: nil,
                    timeoutAction: { view in
                        
                    },
                    audioRecorder: nil,
                    videoRecordingStatus: nil,
                    timeoutValue: 24,
                    timeoutSelected: component.timeout,
                    displayGradient: false,//component.inputHeight != 0.0,
                    bottomInset: 0.0 //component.inputHeight != 0.0 ? 0.0 : bottomContentInset
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: 200.0)
            )
            
            var inputPanelOffset: CGFloat = 0.0
            var inputPanelBottomInset: CGFloat = scrubberBottomInset
            if environment.inputHeight > 0.0 {
                inputPanelBottomInset = environment.inputHeight - environment.safeInsets.bottom
                inputPanelOffset = inputPanelBottomInset
            }
            let inputPanelFrame = CGRect(origin: CGPoint(x: 0.0, y: availableSize.height - environment.safeInsets.bottom - inputPanelBottomInset - inputPanelSize.height - 3.0), size: inputPanelSize)
            if let inputPanelView = self.inputPanel.view {
                if inputPanelView.superview == nil {
                    self.addSubview(inputPanelView)
                }
                transition.setFrame(view: inputPanelView, frame: inputPanelFrame)
            }
            
            let privacyText: String
            switch component.privacy.base {
            case .everyone:
                privacyText = "Everyone"
            case .closeFriends:
                privacyText = "Close Friends"
            case .contacts:
                privacyText = "Contacts"
            case .nobody:
                privacyText = "Selected Contacts"
            }
            
            
            let privacyButtonSize = self.privacyButton.update(
                transition: transition,
                component: AnyComponent(Button(
                    content: AnyComponent(
                        PrivacyButtonComponent(
                            icon: UIImage(bundleImageName: "Media Editor/Recipient")!,
                            text: privacyText
                        )
                    ),
                    action: {
                        if let controller = environment.controller() as? MediaEditorScreen {
                            controller.presentPrivacySettings()
                        }
                    }
                ).tagged(privacyButtonTag)),
                environment: {},
                containerSize: CGSize(width: 44.0, height: 44.0)
            )
            let privacyButtonFrame = CGRect(
                origin: CGPoint(x: 16.0, y: environment.safeInsets.top + 20.0 - inputPanelOffset),
                size: privacyButtonSize
            )
            if let privacyButtonView = self.privacyButton.view {
                if privacyButtonView.superview == nil {
                    self.addSubview(privacyButtonView)
                }
                transition.setPosition(view: privacyButtonView, position: privacyButtonFrame.center)
                transition.setBounds(view: privacyButtonView, bounds: CGRect(origin: .zero, size: privacyButtonFrame.size))
                transition.setScale(view: privacyButtonView, scale: self.inputPanelExternalState.isEditing ? 0.01 : 1.0)
                transition.setAlpha(view: privacyButtonView, alpha: self.inputPanelExternalState.isEditing ? 0.0 : 1.0)
            }
            
            let saveButtonSize = self.saveButton.update(
                transition: transition,
                component: AnyComponent(Button(
                    content: AnyComponent(
                        LottieAnimationComponent(
                            animation: LottieAnimationComponent.AnimationItem(
                                name: "anim_storysave",
                                mode: .still(position: .begin),
                                range: nil
                            ),
                            colors: ["__allcolors__": .white],
                            size: CGSize(width: 33.0, height: 33.0)
                        ).tagged(saveButtonTag)
                    ),
                    action: { [weak self] in
                        if let view = self?.saveButton.findTaggedView(tag: saveButtonTag) as? LottieAnimationComponent.View {
                            view.playOnce()
                        }
                        if let controller = environment.controller() as? MediaEditorScreen {
                            controller.requestSave()
                        }
                    }
                )),
                environment: {},
                containerSize: CGSize(width: 44.0, height: 44.0)
            )
            let saveButtonFrame = CGRect(
                origin: CGPoint(x: availableSize.width - 20.0 - saveButtonSize.width, y: environment.safeInsets.top + 20.0 - inputPanelOffset),
                size: saveButtonSize
            )
            if let saveButtonView = self.saveButton.view {
                if saveButtonView.superview == nil {
                    saveButtonView.layer.shadowOffset = CGSize(width: 0.0, height: 0.0)
                    saveButtonView.layer.shadowRadius = 4.0
                    saveButtonView.layer.shadowColor = UIColor.black.cgColor
                    saveButtonView.layer.shadowOpacity = 0.2
                    self.addSubview(saveButtonView)
                }
                transition.setPosition(view: saveButtonView, position: saveButtonFrame.center)
                transition.setBounds(view: saveButtonView, bounds: CGRect(origin: .zero, size: saveButtonFrame.size))
                transition.setScale(view: saveButtonView, scale: self.inputPanelExternalState.isEditing ? 0.01 : 1.0)
                transition.setAlpha(view: saveButtonView, alpha: self.inputPanelExternalState.isEditing ? 0.0 : 1.0)
            }
             
            if let _ = state.playerState {
                let isVideoMuted = component.mediaEditor?.values.videoIsMuted ?? false
                let muteButtonSize = self.muteButton.update(
                    transition: transition,
                    component: AnyComponent(Button(
                        content: AnyComponent(
                            LottieAnimationComponent(
                                animation: LottieAnimationComponent.AnimationItem(
                                    name: "anim_storymute",
                                    mode: .animating(loop: false),
                                    range: isVideoMuted ? (0.0, 0.5) : (0.5, 1.0)
                                ),
                                colors: ["__allcolors__": .white],
                                size: CGSize(width: 33.0, height: 33.0)
                            ).tagged(muteButtonTag)
                        ),
                        action: { [weak self, weak state] in
                            if let self, let mediaEditor = self.component?.mediaEditor {
                                mediaEditor.setVideoIsMuted(!mediaEditor.values.videoIsMuted)
                                state?.updated()
                            }
                        }
                    )),
                    environment: {},
                    containerSize: CGSize(width: 44.0, height: 44.0)
                )
                let muteButtonFrame = CGRect(
                    origin: CGPoint(x: availableSize.width - 20.0 - muteButtonSize.width - 50.0, y: environment.safeInsets.top + 20.0 - inputPanelOffset),
                    size: muteButtonSize
                )
                if let muteButtonView = self.muteButton.view {
                    if muteButtonView.superview == nil {
                        muteButtonView.layer.shadowOffset = CGSize(width: 0.0, height: 0.0)
                        muteButtonView.layer.shadowRadius = 4.0
                        muteButtonView.layer.shadowColor = UIColor.black.cgColor
                        muteButtonView.layer.shadowOpacity = 0.2
                        self.addSubview(muteButtonView)
                    }
                    transition.setPosition(view: muteButtonView, position: muteButtonFrame.center)
                    transition.setBounds(view: muteButtonView, bounds: CGRect(origin: .zero, size: muteButtonFrame.size))
                    transition.setScale(view: muteButtonView, scale: self.inputPanelExternalState.isEditing ? 0.01 : 1.0)
                    transition.setAlpha(view: muteButtonView, alpha: self.inputPanelExternalState.isEditing ? 0.0 : 1.0)
                }
            }
            
            return availableSize
        }
    }
    
    func makeView() -> View {
        return View()
    }
    
    public func update(view: View, availableSize: CGSize, state: State, environment: Environment<ViewControllerComponentContainer.Environment>, transition: Transition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

private let storyDimensions = CGSize(width: 1080.0, height: 1920.0)

public final class MediaEditorScreen: ViewController {
    public final class TransitionIn {
        public weak var sourceView: UIView?
        public let sourceRect: CGRect
        public let sourceCornerRadius: CGFloat
        
        public init(
            sourceView: UIView,
            sourceRect: CGRect,
            sourceCornerRadius: CGFloat
        ) {
            self.sourceView = sourceView
            self.sourceRect = sourceRect
            self.sourceCornerRadius = sourceCornerRadius
        }
    }
    
    public final class TransitionOut {
        public weak var destinationView: UIView?
        public let destinationRect: CGRect
        public let destinationCornerRadius: CGFloat
        
        public init(
            destinationView: UIView,
            destinationRect: CGRect,
            destinationCornerRadius: CGFloat
        ) {
            self.destinationView = destinationView
            self.destinationRect = destinationRect
            self.destinationCornerRadius = destinationCornerRadius
        }
    }
    
    fileprivate final class Node: ViewControllerTracingNode, UIGestureRecognizerDelegate {
        private weak var controller: MediaEditorScreen?
        private let context: AccountContext
        private let initializationTimestamp = CACurrentMediaTime()
        
        fileprivate var subject: MediaEditorScreen.Subject?
        private var subjectDisposable: Disposable?
        fileprivate var storyPrivacy: EngineStoryPrivacy = EngineStoryPrivacy(base: .everyone, additionallyIncludePeers: [])
        fileprivate var timeout: Bool = true
        
        private let backgroundDimView: UIView
        fileprivate let componentHost: ComponentView<ViewControllerComponentContainer.Environment>
        
        private let previewContainerView: UIView
        
        private let gradientView: UIImageView
        private var gradientColorsDisposable: Disposable?
        
        fileprivate let entitiesContainerView: UIView
        fileprivate let entitiesView: DrawingEntitiesView
        fileprivate let drawingView: DrawingView
        fileprivate let previewView: MediaEditorPreviewView
        fileprivate var mediaEditor: MediaEditor?
        
        private let stickerPickerInputData = Promise<StickerPickerInputData>()
        
        private var presentationData: PresentationData
        private var validLayout: ContainerViewLayout?
        
        init(controller: MediaEditorScreen) {
            self.controller = controller
            self.context = controller.context

            self.presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
            
            self.backgroundDimView = UIView()
            self.backgroundDimView.alpha = 0.0
            self.backgroundDimView.backgroundColor = .black
            
            self.componentHost = ComponentView<ViewControllerComponentContainer.Environment>()
            
            self.previewContainerView = UIView()
            self.previewContainerView.alpha = 0.0
            self.previewContainerView.clipsToBounds = true
            self.previewContainerView.layer.cornerRadius = 12.0
            if #available(iOS 13.0, *) {
                self.previewContainerView.layer.cornerCurve = .continuous
            }
            
            self.gradientView = UIImageView()
            
            self.entitiesContainerView = UIView(frame: CGRect(origin: .zero, size: storyDimensions))
            self.entitiesView = DrawingEntitiesView(context: controller.context, size: storyDimensions)
            self.entitiesView.getEntityCenterPosition = {
                return CGPoint(x: storyDimensions.width / 2.0, y: storyDimensions.height / 2.0)
            }
            self.previewView = MediaEditorPreviewView(frame: .zero)
            self.drawingView = DrawingView(size: storyDimensions)
            self.drawingView.isUserInteractionEnabled = false
            
            super.init()
            
            self.backgroundColor = .clear
            
            //self.view.addSubview(self.backgroundDimView)
            self.view.addSubview(self.previewContainerView)
            self.previewContainerView.addSubview(self.gradientView)
            self.previewContainerView.addSubview(self.entitiesContainerView)
            self.entitiesContainerView.addSubview(self.entitiesView)
            self.previewContainerView.addSubview(self.drawingView)
            
            self.subjectDisposable = (
                controller.subject
                |> filter {
                    $0 != nil
                }
                |> take(1)
                |> deliverOnMainQueue
            ).start(next: { [weak self] subject in
                if let self, let subject {
                    self.setup(with: subject)
                }
            })
            
            let stickerPickerInputData = self.stickerPickerInputData
            Queue.concurrentDefaultQueue().after(0.5, {
                let emojiItems = EmojiPagerContentComponent.emojiInputData(
                    context: controller.context,
                    animationCache: controller.context.animationCache,
                    animationRenderer: controller.context.animationRenderer,
                    isStandalone: false,
                    isStatusSelection: false,
                    isReactionSelection: false,
                    isEmojiSelection: true,
                    hasTrending: false,
                    topReactionItems: [],
                    areUnicodeEmojiEnabled: true,
                    areCustomEmojiEnabled: true,
                    chatPeerId: controller.context.account.peerId,
                    hasSearch: false,
                    forceHasPremium: true
                )
                
                let stickerItems = EmojiPagerContentComponent.stickerInputData(
                    context: controller.context,
                    animationCache: controller.context.animationCache,
                    animationRenderer: controller.context.animationRenderer,
                    stickerNamespaces: [Namespaces.ItemCollection.CloudStickerPacks],
                    stickerOrderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudSavedStickers, Namespaces.OrderedItemList.CloudRecentStickers, Namespaces.OrderedItemList.CloudAllPremiumStickers],
                    chatPeerId: controller.context.account.peerId,
                    hasSearch: false,
                    hasTrending: true,
                    forceHasPremium: true
                )
                
                let maskItems = EmojiPagerContentComponent.stickerInputData(
                    context: controller.context,
                    animationCache: controller.context.animationCache,
                    animationRenderer: controller.context.animationRenderer,
                    stickerNamespaces: [Namespaces.ItemCollection.CloudMaskPacks],
                    stickerOrderedItemListCollectionIds: [],
                    chatPeerId: controller.context.account.peerId,
                    hasSearch: false,
                    hasTrending: false,
                    forceHasPremium: true
                )
                
                let signal = combineLatest(queue: .mainQueue(),
                                           emojiItems,
                                           stickerItems,
                                           maskItems
                ) |> map { emoji, stickers, masks -> StickerPickerInputData in
                    return StickerPickerInputData(emoji: emoji, stickers: stickers, masks: masks)
                }
                
                stickerPickerInputData.set(signal)
            })
        }
        
        deinit {
            self.subjectDisposable?.dispose()
            self.gradientColorsDisposable?.dispose()
        }
        
        private func setup(with subject: MediaEditorScreen.Subject) {
            self.subject = subject
            guard let _ = self.controller else {
                return
            }
            
            let mediaDimensions = subject.dimensions
            
            let maxSide: CGFloat = 1920.0 / UIScreen.main.scale
            let fittedSize = mediaDimensions.cgSize.fitted(CGSize(width: maxSide, height: maxSide))
            let mediaEntity = DrawingMediaEntity(content: subject.mediaContent, size: fittedSize)
            mediaEntity.position = CGPoint(x: storyDimensions.width / 2.0, y: storyDimensions.height / 2.0)
            if fittedSize.height > fittedSize.width {
                mediaEntity.scale = storyDimensions.height / fittedSize.height
            } else {
                mediaEntity.scale = storyDimensions.width / fittedSize.width
            }
            self.entitiesView.add(mediaEntity, announce: false)
            
            let initialPosition = mediaEntity.position
            let initialScale = mediaEntity.scale
            let initialRotation = mediaEntity.rotation
            
            if let entityView = self.entitiesView.getView(for: mediaEntity.uuid) as? DrawingMediaEntityView {
                entityView.previewView = self.previewView
                entityView.updated = { [weak self, weak mediaEntity] in
                    if let self, let mediaEntity {
                        let rotationDelta = mediaEntity.rotation - initialRotation
                        let positionDelta = CGPoint(x: mediaEntity.position.x - initialPosition.x, y: mediaEntity.position.y - initialPosition.y)
                        let scaleDelta = mediaEntity.scale / initialScale
                        self.mediaEditor?.setCrop(offset: positionDelta, scale: scaleDelta, rotation: rotationDelta, mirroring: false)
                    }
                }
            }
            
            let initialValues: MediaEditorValues?
            if case let .draft(draft) = subject {
                initialValues = draft.values
                
                for entity in draft.values.entities {
                    entitiesView.add(entity.entity, announce: false)
                }
            } else {
                initialValues = nil
            }
            let mediaEditor = MediaEditor(subject: subject.editorSubject, values: initialValues, hasHistogram: true)
            mediaEditor.attachPreviewView(self.previewView)
            
            self.gradientColorsDisposable = mediaEditor.gradientColors.start(next: { [weak self] colors in
                if let self, let colors {
                    let (topColor, bottomColor) = colors
                    let gradientImage = generateGradientImage(size: CGSize(width: 5.0, height: 640.0), colors: [topColor, bottomColor], locations: [0.0, 1.0])
                    Queue.mainQueue().async {
                        self.gradientView.image = gradientImage
                        
                        self.previewContainerView.alpha = 1.0
                        if CACurrentMediaTime() - self.initializationTimestamp > 0.2 {
                            self.previewContainerView.layer.allowsGroupOpacity = true
                            self.previewContainerView.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25, completion: { _ in
                                self.previewContainerView.layer.allowsGroupOpacity = false
                                self.controller?.onReady()
                            })
                        } else {
                            self.controller?.onReady()
                        }
                    }
                }
            })
            self.mediaEditor = mediaEditor
        }
        
        override func didLoad() {
            super.didLoad()
            
            self.view.disablesInteractiveModalDismiss = true
            self.view.disablesInteractiveKeyboardGestureRecognizer = true
            
            let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
            panGestureRecognizer.delegate = self
            panGestureRecognizer.minimumNumberOfTouches = 2
            panGestureRecognizer.maximumNumberOfTouches = 2
            self.previewContainerView.addGestureRecognizer(panGestureRecognizer)
            
            let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(self.handlePinch(_:)))
            pinchGestureRecognizer.delegate = self
            self.previewContainerView.addGestureRecognizer(pinchGestureRecognizer)
            
            let rotateGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(self.handleRotate(_:)))
            rotateGestureRecognizer.delegate = self
            self.previewContainerView.addGestureRecognizer(rotateGestureRecognizer)
        }
        
        @objc func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
        
        @objc func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
            self.entitiesView.handlePan(gestureRecognizer)
        }
        
        @objc func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
            self.entitiesView.handlePinch(gestureRecognizer)
        }
        
        @objc func handleRotate(_ gestureRecognizer: UIRotationGestureRecognizer) {
            self.entitiesView.handleRotate(gestureRecognizer)
        }
        
        func animateIn() {
            if let sourceHint = self.controller?.sourceHint {
                switch sourceHint {
                case .camera:
                    if let view = self.componentHost.view as? MediaEditorScreenComponent.View {
                        view.animateInFromCamera()
                    }
                }
            }
            
//            Queue.mainQueue().after(0.5) {
//                self.presentPrivacyTooltip()
//            }
        }
        
        func animateOut(finished: Bool, completion: @escaping () -> Void) {
            guard let controller = self.controller else {
                return
            }
            if let transitionOut = controller.transitionOut(finished), let destinationView = transitionOut.destinationView {
                let destinationLocalFrame = destinationView.convert(transitionOut.destinationRect, to: self.view)
                
                let targetScale = destinationLocalFrame.width / self.previewContainerView.frame.width
                self.previewContainerView.layer.animatePosition(from: self.previewContainerView.center, to: destinationLocalFrame.center, duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { _ in
                    completion()
                })
                self.previewContainerView.layer.animateScale(from: 1.0, to: targetScale, duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
                self.previewContainerView.layer.animateBounds(from: self.previewContainerView.bounds, to: CGRect(origin: CGPoint(x: 0.0, y: (self.previewContainerView.bounds.height - self.previewContainerView.bounds.width) / 2.0), size: CGSize(width: self.previewContainerView.bounds.width, height: self.previewContainerView.bounds.width)), duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
                self.previewContainerView.layer.animate(
                    from: self.previewContainerView.layer.cornerRadius as NSNumber,
                    to: self.previewContainerView.bounds.width / 2.0 as NSNumber,
                    keyPath: "cornerRadius",
                    timingFunction: kCAMediaTimingFunctionSpring,
                    duration: 0.4,
                    removeOnCompletion: false
                )
                
                if let componentView = self.componentHost.view {
                    componentView.clipsToBounds = true
                    componentView.layer.animatePosition(from: componentView.center, to: destinationLocalFrame.center, duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
                    componentView.layer.animateScale(from: 1.0, to: targetScale, duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
                    componentView.layer.animateBounds(from: componentView.bounds, to: CGRect(origin: CGPoint(x: 0.0, y: (componentView.bounds.height - componentView.bounds.width) / 2.0), size: CGSize(width: componentView.bounds.width, height: componentView.bounds.width)), duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
                    componentView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
                    componentView.layer.animate(
                        from: componentView.layer.cornerRadius as NSNumber,
                        to: componentView.bounds.width / 2.0 as NSNumber,
                        keyPath: "cornerRadius",
                        timingFunction: kCAMediaTimingFunctionSpring,
                        duration: 0.4,
                        removeOnCompletion: false
                    )
                }
            } else if let sourceHint = controller.sourceHint {
                switch sourceHint {
                case .camera:
                    if let view = self.componentHost.view as? MediaEditorScreenComponent.View {
                        view.animateOutToCamera()
                    }
                    let transition = Transition(animation: .curve(duration: 0.25, curve: .easeInOut))
                    transition.setAlpha(view: self.previewContainerView, alpha: 0.0, completion: { _ in
                        completion()
                    })
                }
            } else {
                completion()
            }
        }
        
        func animateOutToTool() {
            if let view = self.componentHost.view as? MediaEditorScreenComponent.View {
                view.animateOutToTool()
            }
        }
        
        func animateInFromTool() {
            if let view = self.componentHost.view as? MediaEditorScreenComponent.View {
                view.animateInFromTool()
            }
        }

        func presentPrivacyTooltip() {
            guard let sourceView = self.componentHost.findTaggedView(tag: privacyButtonTag) else {
                return
            }
            
            let parentFrame = self.view.convert(self.bounds, to: nil)
            let absoluteFrame = sourceView.convert(sourceView.bounds, to: nil).offsetBy(dx: -parentFrame.minX, dy: 0.0)
            let location = CGRect(origin: CGPoint(x: absoluteFrame.midX, y: absoluteFrame.maxY + 3.0), size: CGSize())
            
            let controller = TooltipScreen(account: self.context.account, sharedContext: self.context.sharedContext, text: "You can set who can view this story", location: .point(location, .top), displayDuration: .manual, inset: 16.0, shouldDismissOnTouch: { _ in
                return .ignore
            })
            self.controller?.present(controller, in: .current)
        }
        
        func presentSaveTooltip() {
            guard let sourceView = self.componentHost.findTaggedView(tag: saveButtonTag) else {
                return
            }
            
            let parentFrame = self.view.convert(self.bounds, to: nil)
            let absoluteFrame = sourceView.convert(sourceView.bounds, to: nil).offsetBy(dx: -parentFrame.minX, dy: 0.0)
            let location = CGRect(origin: CGPoint(x: absoluteFrame.midX, y: absoluteFrame.maxY + 3.0), size: CGSize())
            
            let text: String
            let isVideo = self.mediaEditor?.resultIsVideo ?? false
            if isVideo {
                text = "Video saved to Photos"
            } else {
                text = "Image saved to Photos"
            }
    
            let controller = TooltipScreen(account: self.context.account, sharedContext: self.context.sharedContext, text: text, location: .point(location, .top), displayDuration: .default, inset: 16.0, shouldDismissOnTouch: { _ in
                return .ignore
            })
            self.controller?.present(controller, in: .current)
        }
        
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let result = super.hitTest(point, with: event)
            if result == self.componentHost.view {
                self.controller?.view.endEditing(true)
                let point = self.view.convert(point, to: self.previewContainerView)
                return self.previewContainerView.hitTest(point, with: event)
            }
            return result
        }
        
        func requestUpdate() {
            if let layout = self.validLayout {
                self.containerLayoutUpdated(layout: layout, transition: .immediate)
            }
        }
        
        private var drawingScreen: DrawingScreen?
        func containerLayoutUpdated(layout: ContainerViewLayout, forceUpdate: Bool = false, animateOut: Bool = false, transition: Transition) {
            guard let _ = self.controller else {
                return
            }
            let isFirstTime = self.validLayout == nil
            self.validLayout = layout

            let previewSize = CGSize(width: layout.size.width, height: floorToScreenPixels(layout.size.width * 1.77778))
            let topInset: CGFloat = floor(layout.size.height - previewSize.height) / 2.0
            
            let environment = ViewControllerComponentContainer.Environment(
                statusBarHeight: layout.statusBarHeight ?? 0.0,
                navigationHeight: 0.0,
                safeInsets: UIEdgeInsets(
                    top: topInset,
                    left: layout.safeInsets.left,
                    bottom: topInset,
                    right: layout.safeInsets.right
                ),
                inputHeight: layout.inputHeight ?? 0.0,
                metrics: layout.metrics,
                deviceMetrics: layout.deviceMetrics,
                orientation: nil,
                isVisible: true,
                theme: self.presentationData.theme,
                strings: self.presentationData.strings,
                dateTimeFormat: self.presentationData.dateTimeFormat,
                controller: { [weak self] in
                    return self?.controller
                }
            )

            let componentSize = self.componentHost.update(
                transition: transition,
                component: AnyComponent(
                    MediaEditorScreenComponent(
                        context: self.context,
                        mediaEditor: self.mediaEditor,
                        privacy: self.storyPrivacy,
                        timeout: self.timeout,
                        openDrawing: { [weak self] mode in
                            if let self {
                                let controller = DrawingScreen(context: self.context, sourceHint: .storyEditor, size: self.previewContainerView.frame.size, originalSize: storyDimensions, isVideo: false, isAvatar: false, drawingView: self.drawingView, entitiesView: self.entitiesView, existingStickerPickerInputData: self.stickerPickerInputData)
                                self.drawingScreen = controller
                                self.drawingView.isUserInteractionEnabled = true
                                
                                let selectionContainerView = controller.selectionContainerView
                                selectionContainerView.frame = self.previewContainerView.bounds
                                self.previewContainerView.addSubview(selectionContainerView)
                                
                                controller.requestDismiss = { [weak controller, weak self, weak selectionContainerView] in
                                    self?.drawingScreen = nil
                                    controller?.animateOut({
                                        controller?.dismiss()
                                    })
                                    self?.drawingView.isUserInteractionEnabled = false
                                    self?.animateInFromTool()
                                    
                                    selectionContainerView?.removeFromSuperview()
                                }
                                controller.requestApply = { [weak controller, weak self, weak selectionContainerView] in
                                    self?.drawingScreen = nil
                                    controller?.animateOut({
                                        controller?.dismiss()
                                    })
                                    self?.drawingView.isUserInteractionEnabled = false
                                    self?.animateInFromTool()
                                    
                                    if let result = controller?.generateDrawingResultData() {
                                        self?.mediaEditor?.setDrawingAndEntities(data: result.data, image: result.drawingImage, entities: result.entities)
                                    } else {
                                        self?.mediaEditor?.setDrawingAndEntities(data: nil, image: nil, entities: [])
                                    }
                                    
                                    selectionContainerView?.removeFromSuperview()
                                }
                                self.controller?.present(controller, in: .current)
                                
                                switch mode {
                                case .sticker:
                                    controller.presentStickerSelection()
                                case .text:
                                    Queue.mainQueue().after(0.05, {
                                        controller.addTextEntity()
                                    })
                                default:
                                    break
                                }
                                
                                self.animateOutToTool()
                            }
                        },
                        openTools: { [weak self] in
                            if let self, let mediaEditor = self.mediaEditor {
                                let controller = MediaToolsScreen(context: self.context, mediaEditor: mediaEditor)
                                controller.dismissed = { [weak self] in
                                    if let self {
                                        self.animateInFromTool()
                                    }
                                }
                                self.controller?.present(controller, in: .current)
                                self.animateOutToTool()
                            }
                        }
                    )
                ),
                environment: {
                    environment
                },
                forceUpdate: forceUpdate || animateOut,
                containerSize: layout.size
            )
            if let componentView = self.componentHost.view {
                if componentView.superview == nil {
                    self.view.insertSubview(componentView, at: 3)
                    componentView.clipsToBounds = true
                }
                let componentFrame = CGRect(origin: .zero, size: componentSize)
                transition.setFrame(view: componentView, frame: CGRect(origin: componentFrame.origin, size: CGSize(width: componentFrame.width, height: componentFrame.height)))
            }
            
            var bottomInputOffset: CGFloat = 0.0
            if let inputHeight = layout.inputHeight, inputHeight > 0.0 {
                bottomInputOffset = inputHeight - topInset - 17.0
            }
                        
            transition.setFrame(view: self.backgroundDimView, frame: CGRect(origin: .zero, size: layout.size))
            
            var previewFrame = CGRect(origin: CGPoint(x: 0.0, y: topInset - bottomInputOffset), size: previewSize)
            if let inputHeight = layout.inputHeight, inputHeight > 0.0, self.drawingScreen != nil {
                previewFrame = previewFrame.offsetBy(dx: 0.0, dy: inputHeight / 2.0)
            }
            
            transition.setFrame(view: self.previewContainerView, frame: previewFrame)
            let entitiesViewScale = previewSize.width / storyDimensions.width
            self.entitiesContainerView.transform = CGAffineTransformMakeScale(entitiesViewScale, entitiesViewScale)
            transition.setFrame(view: self.entitiesContainerView, frame: CGRect(origin: .zero, size: previewFrame.size))
            transition.setFrame(view: self.gradientView, frame: CGRect(origin: .zero, size: previewFrame.size))
            transition.setFrame(view: self.drawingView, frame: CGRect(origin: .zero, size: previewFrame.size))
            
            if isFirstTime {
                self.animateIn()
            }
        }
    }
    
    fileprivate var node: Node {
        return self.displayNode as! Node
    }
    
    public enum Subject {
        case image(UIImage, PixelDimensions)
        case video(String, PixelDimensions)
        case asset(PHAsset)
        case draft(MediaEditorDraft)
        
        var dimensions: PixelDimensions {
            switch self {
            case let .image(_, dimensions), let .video(_, dimensions):
                return dimensions
            case let .asset(asset):
                return PixelDimensions(width: Int32(asset.pixelWidth), height: Int32(asset.pixelHeight))
            case let .draft(draft):
                return draft.dimensions
            }
        }
        
        var editorSubject: MediaEditor.Subject {
            switch self {
            case let .image(image, dimensions):
                return .image(image, dimensions)
            case let .video(videoPath, dimensions):
                return .video(videoPath, dimensions)
            case let .asset(asset):
                return .asset(asset)
            case let .draft(draft):
                return .draft(draft)
            }
        }
        
        var mediaContent: DrawingMediaEntity.Content {
            switch self {
            case let .image(image, dimensions):
                return .image(image, dimensions)
            case let .video(videoPath, dimensions):
                return .video(videoPath, dimensions)
            case let .asset(asset):
                return .asset(asset)
            case let .draft(draft):
                return .image(draft.thumbnail, draft.dimensions)
            }
        }
    }
    
    public enum Result {
        public enum VideoResult {
            case imageFile(path: String)
            case videoFile(path: String)
            case asset(localIdentifier: String)
        }
        case image(image: UIImage, dimensions: PixelDimensions, caption: NSAttributedString?)
        case video(video: VideoResult, coverImage: UIImage?, values: MediaEditorValues, duration: Double, dimensions: PixelDimensions, caption: NSAttributedString?)
    }
    
    fileprivate let context: AccountContext
    fileprivate let subject: Signal<Subject?, NoError>
    fileprivate let transitionIn: TransitionIn?
    fileprivate let transitionOut: (Bool) -> TransitionOut?
    
    public enum SourceHint {
        case camera
    }
    public var sourceHint: SourceHint?
    
    public var cancelled: (Bool) -> Void = { _ in }
    public var completion: (MediaEditorScreen.Result, @escaping () -> Void, EngineStoryPrivacy) -> Void = { _, _, _ in }
    public var onReady: () -> Void = {}
    
    public init(
        context: AccountContext,
        subject: Signal<Subject?, NoError>,
        transitionIn: TransitionIn?,
        transitionOut: @escaping (Bool) -> TransitionOut?,
        completion: @escaping (MediaEditorScreen.Result, @escaping () -> Void, EngineStoryPrivacy) -> Void
    ) {
        self.context = context
        self.subject = subject
        self.transitionIn = transitionIn
        self.transitionOut = transitionOut
        self.completion = completion
        
        super.init(navigationBarPresentationData: nil)
        
        self.navigationPresentation = .flatModal
                    
        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
        
        self.statusBar.statusBarStyle = .White
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func loadDisplayNode() {
        self.displayNode = Node(controller: self)

        super.displayNodeDidLoad()
    }
            
    func presentPrivacySettings() {
        let stateContext = ShareWithPeersScreen.StateContext(context: self.context)
        let _ = (stateContext.ready |> filter { $0 } |> take(1) |> deliverOnMainQueue).start(next: { [weak self] _ in
            guard let self else {
                return
            }
            
            self.push(ShareWithPeersScreen(context: self.context, initialPrivacy: self.node.storyPrivacy, stateContext: stateContext, completion: { [weak self] privacy in
                guard let self else {
                    return
                }
                self.node.storyPrivacy = privacy
                self.node.requestUpdate()
            }))
        })
    }
    
    func maybePresentDiscardAlert() {
        if let subject = self.node.subject, case .asset = subject {
            self.requestDismiss(saveDraft: false, animated: true)
            return
        }
        let title: String
        let save: String
        if case .draft = self.node.subject {
            title = "Discard Draft?"
            save = "Keep Draft"
        } else {
            title = "Discard Media?"
            save = "Save Draft"
        }
        let theme = defaultDarkPresentationTheme
        let controller = textAlertController(
            context: self.context,
            forceTheme: theme,
            title: title,
            text: "If you go back now, you will lose any changes that you've made.",
            actions: [
                TextAlertAction(type: .destructiveAction, title: "Discard", action: { [weak self] in
                    if let self {
                        self.requestDismiss(saveDraft: false, animated: true)
                    }
                }),
                TextAlertAction(type: .genericAction, title: save, action: { [weak self] in
                    if let self {
                        self.requestDismiss(saveDraft: true, animated: true)
                    }
                }),
                TextAlertAction(type: .genericAction, title: "Cancel", action: {
                    
                })
            ],
            actionLayout: .vertical
        )
        self.present(controller, in: .window(.root))
    }
    
    func requestDismiss(saveDraft: Bool, animated: Bool) {
        if saveDraft, let subject = self.node.subject, let values = self.node.mediaEditor?.values {
            if let resultImage = self.node.mediaEditor?.resultImage {
                let fittedSize = resultImage.size.aspectFitted(CGSize(width: 128.0, height: 128.0))
                if case let .image(image, dimensions) = subject {
                    if let thumbnailImage = generateScaledImage(image: resultImage, size: fittedSize) {
                        let path = NSTemporaryDirectory() + "\(Int64.random(in: .min ... .max)).jpg"
                        if let data = image.jpegData(compressionQuality: 0.87) {
                            try? data.write(to: URL(fileURLWithPath: path))
                            let draft = MediaEditorDraft(path: path, isVideo: false, thumbnail: thumbnailImage, dimensions: dimensions, values: values)
                            addStoryDraft(engine: self.context.engine, item: draft)
                        }
                    }
                } else if case let .draft(draft) = subject {
                    if let thumbnailImage = generateScaledImage(image: resultImage, size: fittedSize) {
                        removeStoryDraft(engine: self.context.engine, path: draft.path, delete: false)
                        let draft = MediaEditorDraft(path: draft.path, isVideo: draft.isVideo, thumbnail: thumbnailImage, dimensions: draft.dimensions, values: values)
                        addStoryDraft(engine: self.context.engine, item: draft)
                    }
                }
            }
        } else {
            if case let .draft(draft) = self.node.subject {
                removeStoryDraft(engine: self.context.engine, path: draft.path, delete: true)
            }
        }
        
        self.cancelled(saveDraft)
        
        self.node.animateOut(finished: false, completion: { [weak self] in
            self?.dismiss()
        })
    }
        
    func requestCompletion(caption: NSAttributedString,  animated: Bool) {
        guard let mediaEditor = self.node.mediaEditor, let subject = self.node.subject else {
            return
        }
                
        if mediaEditor.resultIsVideo {
            let videoResult: Result.VideoResult
            let duration: Double
            switch subject {
            case let .image(image, _):
                let tempImagePath = NSTemporaryDirectory() + "\(Int64.random(in: Int64.min ... Int64.max)).jpg"
                if let data = image.jpegData(compressionQuality: 0.85) {
                    try? data.write(to: URL(fileURLWithPath: tempImagePath))
                }
                videoResult = .imageFile(path: tempImagePath)
                duration = 5.0
            case let .video(path, _):
                videoResult = .videoFile(path: path)
                if let videoTrimRange = mediaEditor.values.videoTrimRange {
                    duration = videoTrimRange.upperBound - videoTrimRange.lowerBound
                } else {
                    duration = 5.0
                }
            case let .asset(asset):
                videoResult = .asset(localIdentifier: asset.localIdentifier)
                if asset.mediaType == .video {
                    if let videoTrimRange = mediaEditor.values.videoTrimRange {
                        duration = videoTrimRange.upperBound - videoTrimRange.lowerBound
                    } else {
                        duration = asset.duration
                    }
                } else {
                    duration = 5.0
                }
            case let .draft(draft):
                if draft.isVideo {
                    videoResult = .videoFile(path: draft.path)
                    if let videoTrimRange = mediaEditor.values.videoTrimRange {
                        duration = videoTrimRange.upperBound - videoTrimRange.lowerBound
                    } else {
                        duration = 5.0
                    }
                } else {
                    videoResult = .imageFile(path: draft.path)
                    duration = 5.0
                }
            }
            self.completion(.video(video: videoResult, coverImage: nil, values: mediaEditor.values, duration: duration, dimensions: PixelDimensions(width: 720, height: 1280), caption: caption), { [weak self] in
                self?.node.animateOut(finished: true, completion: { [weak self] in
                    self?.dismiss()
                })
            }, self.node.storyPrivacy)
            
            if case let .draft(draft) = subject {
                removeStoryDraft(engine: self.context.engine, path: draft.path, delete: true)
            }
        } else {
            if let image = mediaEditor.resultImage {
                makeEditorImageComposition(account: self.context.account, inputImage: image, dimensions: storyDimensions, values: mediaEditor.values, time: .zero, completion: { resultImage in
                    if let resultImage {
                        self.completion(.image(image: resultImage, dimensions: PixelDimensions(resultImage.size), caption: caption), { [weak self] in
                            self?.node.animateOut(finished: true, completion: { [weak self] in
                                self?.dismiss()
                            })
                        }, self.node.storyPrivacy)
                        if case let .draft(draft) = subject {
                            removeStoryDraft(engine: self.context.engine, path: draft.path, delete: true)
                        }
                    }
                })
            }
        }
    }
    
    private var videoExport: MediaEditorVideoExport?
    private var exportDisposable: Disposable?
    
    func requestSave() {
        guard let mediaEditor = self.node.mediaEditor, let subject = self.node.subject else {
            return
        }
        
        let tempVideoPath = NSTemporaryDirectory() + "\(Int64.random(in: Int64.min ... Int64.max)).mp4"
        let saveToPhotos: (String, Bool) -> Void = { path, isVideo in
            PHPhotoLibrary.shared().performChanges({
                if isVideo {
                    if let _ = try? FileManager.default.copyItem(atPath: path, toPath: tempVideoPath) {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: path))
                    }
                } else {
                    if let fileData = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                        PHAssetCreationRequest.forAsset().addResource(with: .photo, data: fileData, options: nil)
                    }
                }
            }, completionHandler: { _, error in
                if let error = error {
                    print("\(error)")
                }
                let _ = try? FileManager.default.removeItem(atPath: tempVideoPath)
            })
        }
        
        if mediaEditor.resultIsVideo {
            let exportSubject: Signal<MediaEditorVideoExport.Subject, NoError>
            switch subject {
            case let .video(path, _):
                let asset = AVURLAsset(url: NSURL(fileURLWithPath: path) as URL)
                exportSubject = .single(.video(asset))
            case let .image(image, _):
                exportSubject = .single(.image(image))
            case let .asset(asset):
                exportSubject = Signal { subscriber in
                    if asset.mediaType == .video {
                        PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { avAsset, _, _ in
                            if let avAsset {
                                subscriber.putNext(.video(avAsset))
                                subscriber.putCompletion()
                            }
                        }
                    } else {
                        let options = PHImageRequestOptions()
                        options.deliveryMode = .highQualityFormat
                        PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .default, options: options) { image, _ in
                            if let image {
                                subscriber.putNext(.image(image))
                                subscriber.putCompletion()
                            }
                        }
                    }
                    return EmptyDisposable
                }
            case let .draft(draft):
                if draft.isVideo {
                    let asset = AVURLAsset(url: NSURL(fileURLWithPath: draft.path) as URL)
                    exportSubject = .single(.video(asset))
                } else {
                    if let image = UIImage(contentsOfFile: draft.path) {
                        exportSubject = .single(.image(image))
                    } else {
                        fatalError()
                    }
                }
            }
            
            let _ = exportSubject.start(next: { [weak self] exportSubject in
                guard let self else {
                    return
                }
                let configuration = recommendedVideoExportConfiguration(values: mediaEditor.values)
                let outputPath = NSTemporaryDirectory() + "\(Int64.random(in: 0 ..< .max)).mp4"
                let videoExport = MediaEditorVideoExport(account: self.context.account, subject: exportSubject, configuration: configuration, outputPath: outputPath)
                self.videoExport = videoExport
                
                videoExport.startExport()
                
                self.exportDisposable = (videoExport.status
                |> deliverOnMainQueue).start(next: { [weak self] status in
                    if let self {
                        if case .completed = status {
                            self.videoExport = nil
                            saveToPhotos(outputPath, true)
                            self.node.presentSaveTooltip()
                        }
                    }
                })
            })
        } else {
            if let image = mediaEditor.resultImage {
                makeEditorImageComposition(account: self.context.account, inputImage: image, dimensions: storyDimensions, values: mediaEditor.values, time: .zero, completion: { resultImage in
                    if let data = resultImage?.jpegData(compressionQuality: 0.8) {
                        let outputPath = NSTemporaryDirectory() + "\(Int64.random(in: 0 ..< .max)).jpg"
                        try? data.write(to: URL(fileURLWithPath: outputPath))
                        saveToPhotos(outputPath, false)
                    }
                })
                self.node.presentSaveTooltip()
            }
        }
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        (self.displayNode as! Node).containerLayoutUpdated(layout: layout, transition: Transition(transition))
    }
}

final class PrivacyButtonComponent: CombinedComponent {
    let icon: UIImage
    let text: String

    init(
        icon: UIImage,
        text: String
    ) {
        self.icon = icon
        self.text = text
    }

    static func ==(lhs: PrivacyButtonComponent, rhs: PrivacyButtonComponent) -> Bool {
        if lhs.text != rhs.text {
            return false
        }
        return true
    }

    static var body: Body {
        let background = Child(BlurredBackgroundComponent.self)
        let icon = Child(Image.self)
        let text = Child(Text.self)

        return { context in
            let icon = icon.update(
                component: Image(image: context.component.icon, size: CGSize(width: 9.0, height: 11.0)),
                availableSize: CGSize(width: 180.0, height: 100.0),
                transition: .immediate
            )
            
            let text = text.update(
                component: Text(
                    text: "\(context.component.text)",
                    font: Font.medium(14.0),
                    color: .white
                ),
                availableSize: CGSize(width: 180.0, height: 100.0),
                transition: .immediate
            )

            let backgroundSize = CGSize(width: text.size.width + 38.0, height: 30.0)
            let background = background.update(
                component: BlurredBackgroundComponent(color: UIColor(white: 0.0, alpha: 0.5)),
                availableSize: backgroundSize,
                transition: .immediate
            )

            context.add(background
                .position(CGPoint(x: backgroundSize.width / 2.0, y: backgroundSize.height / 2.0))
                .cornerRadius(min(backgroundSize.width, backgroundSize.height) / 2.0)
                .clipsToBounds(true)
            )
            
            context.add(icon
                .position(CGPoint(x: 16.0, y: backgroundSize.height / 2.0))
            )

            context.add(text
                .position(CGPoint(x: backgroundSize.width / 2.0 + 7.0, y: backgroundSize.height / 2.0))
            )

            return backgroundSize
        }
    }
}
