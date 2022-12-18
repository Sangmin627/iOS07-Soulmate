//
//  DefaultUserPreviewRepository.swift
//  Soulmate
//
//  Created by Sangmin Lee on 2022/11/24.
//

import Foundation

final class DefaultUserPreviewRepository: UserPreviewRepository {
    
    let networkDatabaseApi: NetworkDatabaseApi
    let collectionTitle = "UserPreview"
    
    init(networkDatabaseApi: NetworkDatabaseApi) {
        self.networkDatabaseApi = networkDatabaseApi
    }
    
    func fetchDistanceFilteredRecommendedPreviewList(
        userUid: String,
        userGender: GenderType,
        userLocation: Location,
        distance: Double
    ) async throws -> [UserPreview] {
        
        let fromPoint = Location(latitude: userLocation.latitude, longitude: userLocation.longitude)

        return try await networkDatabaseApi.read(
            table: collectionTitle,
            constraints: [QueryEntity(field: "gender", value: userGender.rawValue, comparator: .isNotEqualTo)],
            type: UserPreviewDTO.self
        )
        .filter { dto in
            guard let documentID = dto.uid,
                  documentID != userUid,
                  let location = dto.location else { return false }
            
            let toPoint = Location(latitude: location.latitude, longitude: location.longitude)
            return Location.distance(from: fromPoint, to: toPoint) <= distance
        }
        .map {
            $0.toDomain()
        }
        
    }
    
    func fetchRecommendedPreviewList(
        userUid: String,
        userGender: GenderType
    ) async throws -> [UserPreview] {
        return try await networkDatabaseApi.read(
            table: collectionTitle,
            constraints: [QueryEntity(field: "gender", value: userGender.rawValue, comparator: .isNotEqualTo)],
            type: UserPreviewDTO.self
        )
        .filter { dto in
            guard let documentID = dto.uid,
                  documentID != userUid else { return false }
            return true
        }
        .map {
            $0.toDomain()
        }
    }
    
    func registerPreview(userUid: String, userPreview: UserPreview) async throws {
        try await networkDatabaseApi.create(
            table: collectionTitle,
            documentID: userUid,
            data: userPreview.toDTO()
        )
    }
    
    func updatePreview(userUid: String, userPreview: UserPreview) async throws {
        let dto = userPreview.toDTO()
        networkDatabaseApi.update(path: collectionTitle,
                                  documentId: userUid,
                                  with: [
                                    "gender": dto.gender,
                                    "name": dto.name,
                                    "birth": dto.birth,
                                    "imageKey": dto.imageKey,
                                    "chatImageKey": dto.chatImageKey
                                  ]
        )
    }
    
    func updateLocation(userUid: String, location: Location) async throws {
        try await networkDatabaseApi.update(
            table: collectionTitle,
            documentID: userUid,
            with: [
                "location": location.toGeoPoint()
            ]
        )
    }
    
    func downloadPreview(userUid: String) async throws -> UserPreview {
        return try await networkDatabaseApi.read(
            table: collectionTitle,
            documentID: userUid,
            type: UserPreviewDTO.self
        )
        .toDomain()
    }

}
