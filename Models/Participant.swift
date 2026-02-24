//
//  Participant.swift
//  EventSnap
//
//  参加者データモデル
//

import Foundation

struct Participant: Identifiable, Codable {
    let id: String // デバイスID
    var deviceName: String
    let joinedAt: Date
    var isActive: Bool

    init(
        id: String,
        deviceName: String = "Unknown Device",
        joinedAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.deviceName = deviceName
        self.joinedAt = joinedAt
        self.isActive = isActive
    }
}
