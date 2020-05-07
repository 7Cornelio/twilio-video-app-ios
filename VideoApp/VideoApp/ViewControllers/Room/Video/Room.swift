//
//  Copyright (C) 2020 Twilio, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import TwilioVideo

enum RoomChange {
    case didStartConnecting
    case didConnect
    case didFailToConnect(error: Error)
    case didDisconnect(error:Error?)
    case didAddRemoteParticipants(participants: [Participant])
    case didRemoveRemoteParticipants(participants: [Participant])
}

enum RoomState {
    case disconnected
    case connecting // Includes fetching access token
    case connected
}

@objc class Room: NSObject {
    let localParticipant: LocalParticipant
    private(set) var remoteParticipants: [RemoteParticipant] = []
    private(set) var state: RoomState = .disconnected
    @objc private(set) var room: TwilioVideo.Room? // Only exposed for stats and should not be used for anything else
    private let accessTokenStore: TwilioAccessTokenStoreReading
    private let connectOptionsFactory: ConnectOptionsFactory
    private let notificationCenter = NotificationCenter.default
    
    init(
        localParticipant: LocalParticipant,
        accessTokenStore: TwilioAccessTokenStoreReading,
        connectOptionsFactory: ConnectOptionsFactory
    ) {
        self.localParticipant = localParticipant
        self.accessTokenStore = accessTokenStore
        self.connectOptionsFactory = connectOptionsFactory
    }

    func connect(roomName: String) {
        guard state == .disconnected else { fatalError("Connection already in progress.") }

        state = .connecting
        sendRoomUpdate(change: .didStartConnecting) // TODO: Make more dry

        accessTokenStore.fetchTwilioAccessToken(roomName: roomName) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case let .success(accessToken):
                let options = self.connectOptionsFactory.makeConnectOptions(
                    accessToken: accessToken,
                    roomName: roomName,
                    audioTracks: [self.localParticipant.micAudioTrack].compactMap { $0 },
                    videoTracks: [self.localParticipant.localCameraVideoTrack].compactMap { $0 }
                )
                // TODO: Inject
                self.room = TwilioVideoSDK.connect(options: options, delegate: self)
            case let .failure(error):
                self.state = .disconnected
                self.sendRoomUpdate(change: .didFailToConnect(error: error))
            }
        }
    }

    func disconnect() {
        room?.disconnect()
        state = .disconnected
        sendRoomUpdate(change: .didDisconnect(error: nil))
    }
    
    private func updateRemoteParticipants() {
        guard let room = room else { remoteParticipants = []; return }
        
        remoteParticipants = room.remoteParticipants.map { RemoteParticipant(participant: $0) }
    }
    
    private func sendRoomUpdate(change: RoomChange) {
        self.notificationCenter.post(name: .roomDidChange, object: self, userInfo: ["key": change])
    }
}

extension Room: TwilioVideo.RoomDelegate {
    func roomDidConnect(room: TwilioVideo.Room) {
        state = .connected
        localParticipant.participant = room.localParticipant
        updateRemoteParticipants()
        sendRoomUpdate(change: .didConnect)
        
        if !remoteParticipants.isEmpty {
            sendRoomUpdate(change: .didAddRemoteParticipants(participants: remoteParticipants))
        }
    }
    
    func roomDidFailToConnect(room: TwilioVideo.Room, error: Error) {
        state = .disconnected
        self.room = nil
        sendRoomUpdate(change: .didFailToConnect(error: error))
    }
    
    func roomDidDisconnect(room: TwilioVideo.Room, error: Error?) {
        state = .disconnected
        self.room = nil
        localParticipant.participant = nil
        let participants = remoteParticipants
        updateRemoteParticipants()
        sendRoomUpdate(change: .didDisconnect(error: error))
        
        if !participants.isEmpty {
            sendRoomUpdate(change: .didRemoveRemoteParticipants(participants: participants))
        }
    }
    
    func participantDidConnect(room: TwilioVideo.Room, participant: TwilioVideo.RemoteParticipant) {
        updateRemoteParticipants()
    
        sendRoomUpdate(change: .didAddRemoteParticipants(participants: [remoteParticipants[remoteParticipants.count - 1]]))
    }
    
    func participantDidDisconnect(room: TwilioVideo.Room, participant: TwilioVideo.RemoteParticipant) {
        guard let participant = remoteParticipants.first(where: { $0.identity == participant.identity }) else { return }
        
        updateRemoteParticipants()
        sendRoomUpdate(change: .didRemoveRemoteParticipants(participants: [participant]))
    }
    
    func dominantSpeakerDidChange(room: TwilioVideo.Room, participant: TwilioVideo.RemoteParticipant?) {
        guard let participant = remoteParticipants.first(where: { $0.identity == participant?.identity }) else { return }

        if let old = remoteParticipants.first(where: { $0.isDominantSpeaker }) {
            old.isDominantSpeaker = false
        }

        participant.isDominantSpeaker = true
    }
}
