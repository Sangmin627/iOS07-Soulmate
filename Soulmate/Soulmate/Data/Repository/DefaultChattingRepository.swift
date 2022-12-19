//
//  DefaultChattingRepository.swift
//  Soulmate
//
//  Created by Hoen on 2022/12/06.
//

import Combine
import FirebaseFirestore

final class DefaultChattingRepository: ChattingRepository {
    
    private let authRepository: AuthRepository
    private let networkDatabaseApi: NetworkDatabaseApi
    
    var startDocument: QueryDocumentSnapshot?
    var lastDocument: QueryDocumentSnapshot?
    var othersMessages = PassthroughSubject<[Chat], Never>()
    
    private var chattinListenerRegistration: ListenerRegistration?    
    
    init(authRepository: AuthRepository, networkDatabaseApi: NetworkDatabaseApi) {
        self.authRepository = authRepository
        self.networkDatabaseApi = networkDatabaseApi
    }
    
    func removeChattingListen() {
        chattinListenerRegistration?.remove()
        chattinListenerRegistration = nil
    }
    
    func setStartDocument(_ doc: QueryDocumentSnapshot?) {
        self.startDocument = doc
    }
    
    func setLastDocument(_ doc: QueryDocumentSnapshot?) {        
        self.lastDocument = doc
    }
    
    func loadReadChattings(from chatRoomId: String) async -> [MessageInfoDTO] {
        guard let uid = try? authRepository.currentUid() else { return [] }
        let path = "ChatRooms/\(chatRoomId)/Messages"
        let constraints = [
            QueryEntity(field: "readUsers", value: uid, comparator: .arrayContains),
            QueryEntity(field: "date", value: "", comparator: .order),            
            QueryEntity(field: "", value: 100, comparator: .limitToLast)
        ]
        
        guard let result = try? await networkDatabaseApi.read(
            path: path,
            constraints: constraints,
            type: MessageInfoDTO.self
        ) else { return [] }
        
        let dtos = result.data
        let snapshot = result.snapshot
        
        startDocument = snapshot.documents.first
        lastDocument = snapshot.documents.last
        
        return dtos
    }
    
    func loadUnReadChattings(from chatRoomId: String) async -> [MessageInfoDTO] {
        
        let path = "ChatRooms/\(chatRoomId)/Messages"
        var constraints = [
            QueryEntity(field: "date", value: "", comparator: .order)
        ]
        
        if let lastDocument {
            constraints.append(QueryEntity(field: "", value: lastDocument, comparator: .startAfterDocument))
        }
        
        guard let result = try? await networkDatabaseApi.read(
            path: path,
            constraints: constraints,
            type: MessageInfoDTO.self
        ) else { return [] }
        
        let dtos = result.data
        let snapshot = result.snapshot
        
        if let newLastDocument = snapshot.documents.last {
            lastDocument = newLastDocument
        }
        
        addMeToReadUsers(of: snapshot)
        
        return dtos
    }
    
    func loadPrevChattings(from chatRoomId: String) async -> [MessageInfoDTO] {

        guard startDocument != nil else {
            return []
        }
        
        let path = "ChatRooms/\(chatRoomId)/Messages"
        var constraints = [
            QueryEntity(field: "date", value: "", comparator: .orderDescending),
            QueryEntity(field: "", value: 30, comparator: .limit),
            QueryEntity(field: "", value: startDocument, comparator: .startAfterDocument)
        ]
        
        if let startDocument {
            constraints.append(QueryEntity(field: "", value: startDocument, comparator: .startAfterDocument))
        }
        
        guard let result = try? await networkDatabaseApi.read(
            path: path,
            constraints: constraints,
            type: MessageInfoDTO.self
        ) else { return [] }
                
        let dtos = result.data
        let snapshot = result.snapshot
        
        startDocument = snapshot.documents.last
        
        return dtos
    }
    
    func addMeToReadUsers(of snapshot: QuerySnapshot) {
        guard let uid = try? authRepository.currentUid() else { return }
        
        snapshot.documents.forEach { doc in
            let docRef = doc.reference
            var readUsers = Set(doc.data()["readUsers"] as? [String] ?? [])
            readUsers.insert(uid)
            var arrReadUsers = readUsers.map { $0 }
            
            docRef.updateData(["readUsers": arrReadUsers])        
        }            
    }
    
    func updateUnreadCountToZero(of chatRoomId: String, othersId: String) {
        guard let uid = try? authRepository.currentUid() else { return }
        let path = "ChatRooms"
        
        networkDatabaseApi.update(
            path: path,
            documentId: chatRoomId,
            with: ["unreadCount": [uid: 0.0, othersId: 0.0 ]]
        )
    }
    
    func increaseUnreadCount(of id: String, in chatRoomId: String) async {
        
        let path = "ChatRooms/\(chatRoomId)"

        let doc = try? await networkDatabaseApi.read(
            table: "ChatRooms",
            documentID: chatRoomId,
            type: ChatRoomInfoDTO.self)
        
        guard var unreadCount = doc?.unreadCount else { return }
        unreadCount[id]! += 1
        
        try? await networkDatabaseApi.update(
            table: "ChatRooms",
            documentID: chatRoomId,
            with: ["unreadCount": unreadCount]
        )
    }
    
    func addMessage(_ message: MessageToSendDTO, to chatRoomId: String) async -> Bool {
        let path = "ChatRooms/\(chatRoomId)/Messages"

        if let _ = try? await networkDatabaseApi.create(path: path, data: message.toDict()) {
            
            if let _ = try? await self.networkDatabaseApi.update(
                table: "ChatRooms",
                documentID: chatRoomId,
                with: [
                    "lastMessage": message.text,
                    "lastDate": message.date
                ]
            ) {
                return true
            }
        }
        
        return false
    }
    
    func listenOthersChattings(from chatRoomId: String, uid: String) {
        
        let path = "ChatRooms/\(chatRoomId)/Messages"
        var constraints = [
            QueryEntity(field: "date", value: "", comparator: .order)
        ]
        
        if let lastDocument {
            constraints.append(QueryEntity(field: "", value: lastDocument, comparator: .startAfterDocument))
        }
        
        let query = networkDatabaseApi.query(path: path, constraints: constraints)
        
        chattinListenerRegistration = query
            .addSnapshotListener { [weak self] snapshot, err in
                guard let snapshot, err == nil, !snapshot.documentChanges.isEmpty else {
                    return
                }
                
                let addChange = snapshot.documentChanges.filter { change in
                    change.type == .added
                }
                
                let addedDocs = addChange.map { $0.document }
                
                guard !addedDocs.isEmpty else {
                    return
                }
                
                let dtos = addedDocs.compactMap { try? $0.data(as: MessageInfoDTO.self) }
                let infos = dtos.map { $0.toModel() }.reversed()
                let others = infos.filter { $0.userId != uid }
                let chats = others.map { info in
                    let date = info.date
                    let isMe = info.userId == uid
                    let text = info.text
                    
                    var readUsers = Set(info.readUsers)
                    readUsers.insert(uid)
                    let arrReadUsers = readUsers.map { $0 }
                    
                    return Chat(isMe: isMe, userId: info.userId, readUsers: arrReadUsers, text: text, date: date, state: .validated)
                }
                
                guard !chats.isEmpty else { return }
                
                self?.addMeToReadUsers(of: snapshot)
                self?.othersMessages.send(chats)
                self?.setLastDocument(snapshot.documents.last)
                self?.removeChattingListen()
                self?.listenOthersChattings(from: chatRoomId, uid: uid)
            }
    }
}
