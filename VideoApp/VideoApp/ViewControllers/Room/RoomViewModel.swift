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

struct RoomViewModelData {
    struct Participant {
        let identity: String
        let networkQualityLevel: String // TODO: Enum
        let isAudioMuted: Bool
        let shouldMirrorVideo: Bool
        let cameraVideoTrack: VideoTrack?
    }
    
    let roomName: String
    let participants: [Participant]
}

protocol RoomViewModelDelegate: AnyObject {
    func didUpdateData() // TODO: Change to connection changes
    func didAddParticipants(at indexes: [Int])
    func didRemoveParticipant(at index: Int)
    func didUpdateParticipantAttributes(at index: Int)
    func didUpdateParticipantVideoConfig(at index: Int)
}

class RoomViewModel {
    weak var delegate: RoomViewModelDelegate?
    var data: RoomViewModelData {
        let participants: [Participant] = [room.localParticipant] + room.remoteParticipants
        let newParticipants = participants.map {
            RoomViewModelData.Participant(
                identity: $0.identity,
                networkQualityLevel: "",
                isAudioMuted: false,
                shouldMirrorVideo: false,
                cameraVideoTrack: $0.cameraVideoTrack
            )
        }
        
        return RoomViewModelData(
            roomName: roomName,
            participants: newParticipants
        )
    }
    var isMicOn: Bool {
        get { room.localParticipant.isMicOn
        }
        set {
            // TODO: Make sure the only gets called on a real change
            room.localParticipant.isMicOn = newValue
        }
    }
    private let roomName: String
    private let room: Room

    init(roomName: String, room: Room) {
        self.roomName = roomName
        self.room = room
        room.delegate = self
    }
    
    func connect() {
        room.connect(roomName: roomName)
    }
}

extension RoomViewModel: RoomDelegate {
    func didConnect() {
        delegate?.didUpdateData()
    }
    
    func didFailToConnect(error: Error) {
        
    }
    
    func didDisconnect(error: Error?) {
        delegate?.didUpdateData()
    }

    func didUpdate() {
        delegate?.didUpdateData()
    }

    func didAddRemoteParticipants(at indexes: [Int]) {
        room.remoteParticipants.forEach { $0.delegate = self }
        delegate?.didAddParticipants(at: indexes.map { $0 + 1 })
    }
    
    func didRemoveRemoteParticipant(at index: Int) {
        delegate?.didRemoveParticipant(at: index + 1)
    }
}

extension RoomViewModel: ParticipantDelegate {
    func didUpdateAttributes(participant: Participant) {
        guard let index = room.remoteParticipants.firstIndex(where: { $0.identity == participant.identity }) else { return }
        
        delegate?.didUpdateParticipantAttributes(at: index + 1)
    }
    
    func didUpdateVideoConfig(participant: Participant) {
        // TODO: Make more DRY
        guard let index = room.remoteParticipants.firstIndex(where: { $0.identity == participant.identity }) else { return }

        delegate?.didUpdateParticipantVideoConfig(at: index + 1)
    }
}