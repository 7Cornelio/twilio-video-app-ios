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

import Foundation

enum MainParticipantStoreChange {
    case didUpdateMainParticipant
}

class MainParticipantStore {
    private(set) var mainParticipant: Participant
    private let room: Room
    private let participantsStore: ParticipantsStore
    private let notificationCenter: NotificationCenter
    
    init(room: Room, participantsStore: ParticipantsStore, notificationCenter: NotificationCenter) {
        self.room = room
        self.participantsStore = participantsStore
        self.notificationCenter = notificationCenter
        self.mainParticipant = room.localParticipant
        update()
        notificationCenter.addObserver(self, selector: #selector(roomDidChange(_:)), name: .roomDidChange, object: room)
        notificationCenter.addObserver(self, selector: #selector(participantDidChange(_:)), name: .participantDidChange, object: nil)
        notificationCenter.addObserver(self, selector: #selector(participanListDidChange(_:)), name: .participantListChange, object: participantsStore)
    }

    @objc private func roomDidChange(_ notification: Notification) {
        guard let payload = notification.payload as? RoomChange else { return }
        
        switch payload {
        case .didStartConnecting, .didConnect, .didFailToConnect, .didDisconnect: break
        case .didAddRemoteParticipants, .didRemoveRemoteParticipants: update()
        }
    }
    
    @objc private func participantDidChange(_ notification: Notification) {
        guard let payload = notification.payload as? ParticipantUpdate else { return }
        
        switch payload {
        case let .didUpdate(participant):
            if participant === mainParticipant {
                post(.didUpdateMainParticipant)
            }
            
            update()
        }
    }

    @objc private func participanListDidChange(_ notification: Notification) {
        update()
    }
    
    private func update() {
        let pinnedParticipant = participantsStore.participants.first(where: { $0.isPinned })
        let screenParticipant = room.remoteParticipants.first(where: { $0.screenTrack != nil })
        let dominantSpeaker = room.remoteParticipants.first(where: { $0.isDominantSpeaker })
        let firstRemoteParticipant = participantsStore.participants.first(where: { $0.isRemote })
        
        let new =
            pinnedParticipant ??
            screenParticipant ??
            dominantSpeaker ??
            firstRemoteParticipant ??
            room.localParticipant

        if new.identity != mainParticipant.identity {
            mainParticipant = new
            post(.didUpdateMainParticipant)
        }
    }
    
    private func post(_ payload: MainParticipantStoreChange) {
        notificationCenter.post(name: .mainParticipantStoreChange, object: self, payload: payload)
    }
}