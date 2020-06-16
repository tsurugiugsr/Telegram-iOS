#include "Manager.h"

#ifdef TGVOIP_NAMESPACE
namespace TGVOIP_NAMESPACE {
#endif

static rtc::Thread *makeNetworkThread() {
    static std::unique_ptr<rtc::Thread> value = rtc::Thread::CreateWithSocketServer();
    value->SetName("WebRTC-Network", nullptr);
    value->Start();
    return value.get();
}


static rtc::Thread *getNetworkThread() {
    static rtc::Thread *value = makeNetworkThread();
    return value;
}

static rtc::Thread *makeMediaThread() {
    static std::unique_ptr<rtc::Thread> value = rtc::Thread::Create();
    value->SetName("WebRTC-Media", nullptr);
    value->Start();
    return value.get();
}


static rtc::Thread *getMediaThread() {
    static rtc::Thread *value = makeMediaThread();
    return value;
}

Manager::Manager(
    rtc::Thread *thread,
    TgVoipEncryptionKey encryptionKey,
    bool enableP2P,
    std::function<void (const TgVoipState &)> stateUpdated,
    std::function<void (const std::vector<uint8_t> &)> signalingDataEmitted
) :
_thread(thread),
_encryptionKey(encryptionKey),
_enableP2P(enableP2P),
_stateUpdated(stateUpdated),
_signalingDataEmitted(signalingDataEmitted) {
    assert(_thread->IsCurrent());
}

Manager::~Manager() {
    assert(_thread->IsCurrent());
}

void Manager::start() {
    auto weakThis = std::weak_ptr<Manager>(shared_from_this());
    _networkManager.reset(new ThreadLocalObject<NetworkManager>(getNetworkThread(), [encryptionKey = _encryptionKey, enableP2P = _enableP2P, thread = _thread, weakThis]() {
        return new NetworkManager(
            getNetworkThread(),
            encryptionKey,
            enableP2P,
            [thread, weakThis](const NetworkManager::State &state) {
                thread->Invoke<void>(RTC_FROM_HERE, [weakThis, state]() {
                    auto strongThis = weakThis.lock();
                    if (strongThis == nullptr) {
                        return;
                    }
                    TgVoipState mappedState;
                    if (state.isReadyToSendData) {
                        mappedState = TgVoipState::Estabilished;
                    } else {
                        mappedState = TgVoipState::Reconnecting;
                    }
                    strongThis->_stateUpdated(mappedState);
                    
                    strongThis->_mediaManager->perform([state](MediaManager *mediaManager) {
                        mediaManager->setIsConnected(state.isReadyToSendData);
                    });
                });
            },
            [thread, weakThis](const rtc::CopyOnWriteBuffer &packet) {
                thread->PostTask(RTC_FROM_HERE, [weakThis, packet]() {
                    auto strongThis = weakThis.lock();
                    if (strongThis == nullptr) {
                        return;
                    }
                    strongThis->_mediaManager->perform([packet](MediaManager *mediaManager) {
                        mediaManager->receivePacket(packet);
                    });
                });
            },
            [thread, weakThis](const std::vector<uint8_t> &data) {
                thread->PostTask(RTC_FROM_HERE, [weakThis, data]() {
                    auto strongThis = weakThis.lock();
                    if (strongThis == nullptr) {
                        return;
                    }
                    strongThis->_signalingDataEmitted(data);
                });
            }
        );
    }));
    bool isOutgoing = _encryptionKey.isOutgoing;
    _mediaManager.reset(new ThreadLocalObject<MediaManager>(getMediaThread(), [isOutgoing, thread = _thread, weakThis]() {
        return new MediaManager(
            getMediaThread(),
            isOutgoing,
            [thread, weakThis](const rtc::CopyOnWriteBuffer &packet) {
                thread->PostTask(RTC_FROM_HERE, [weakThis, packet]() {
                    auto strongThis = weakThis.lock();
                    if (strongThis == nullptr) {
                        return;
                    }
                    strongThis->_networkManager->perform([packet](NetworkManager *networkManager) {
                        networkManager->sendPacket(packet);
                    });
                });
            }
        );
    }));
}

void Manager::receiveSignalingData(const std::vector<uint8_t> &data) {
    _networkManager->perform([data](NetworkManager *networkManager) {
        networkManager->receiveSignalingData(data);
    });
}

void Manager::setIncomingVideoOutput(std::shared_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>> sink) {
    _mediaManager->perform([sink](MediaManager *mediaManager) {
        mediaManager->setIncomingVideoOutput(sink);
    });
}

void Manager::setOutgoingVideoOutput(std::shared_ptr<rtc::VideoSinkInterface<webrtc::VideoFrame>> sink) {
    _mediaManager->perform([sink](MediaManager *mediaManager) {
        mediaManager->setOutgoingVideoOutput(sink);
    });
}

#ifdef TGVOIP_NAMESPACE
}
#endif
