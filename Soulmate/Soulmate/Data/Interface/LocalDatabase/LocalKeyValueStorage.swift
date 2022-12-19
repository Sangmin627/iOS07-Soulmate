//
//  LocalKeyValueStorage.swift
//  Soulmate
//
//  Created by Sangmin Lee on 2022/11/23.
//

import Foundation
import Combine

protocol LocalKeyValueStorage {
    func set(key: String, value: Any?)
    func get<T>(key: String) -> T?
    func remove(key: String)
    func valuePublisher<Value>(path: KeyPath<UserDefaults, Value>) -> AnyPublisher<Value, Never>
}
