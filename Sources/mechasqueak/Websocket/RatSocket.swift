/*
 Copyright 2020 The Fuel Rats Mischief

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
 products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation
import NIOHTTP1
import IRCKit
import NIO
import WebSocketKit

enum RatSocketEventType: String {
    case connection
    case rescueCreated = "fuelrats.rescuecreate"
    case rescueUpdated = "fuelrats.rescueupdate"
    case rescueDeleted = "fuelrats.rescuedelete"
    case userUpdated = "fuelrats.userupdate"
    case channelMessage = "mechasqueak.channelmessage"
}

struct WebSocket {}

class RatSocket {
    var connectedAndAuthenticated = false
    var socket: WebSocketKit.WebSocket?

    init () {
        self.connect()
    }
    
    func connect () {
        guard configuration.api.websocket != nil else {
            return
        }
        
        _ = WebSocketKit.WebSocket.connect(to: URL(string: "\(configuration.api.websocket!)")!, headers: HTTPHeaders([
            ("Sec-Websocket-Protocol", "FR-JSONAPI-WS"),
            ("x-bearer", configuration.api.token)
        ]), on: loop) { ws in
            self.socket = ws

            ws.onText(self.websocketDidReceiveMessage)
            ws.onClose.whenComplete { result in
                switch result {
                case .failure(let error):
                    self.websocketDidDisconnect(error: error)

                case .success(_):
                    self.websocketDidConnect()
                }
            }
        }
    }

    func broadcast<Payload: Encodable> (event: RatSocketEventType, payload: Payload) {
        let request = RatSocketRequest(
            endpoint: ["events", "broadcast"],
            query: BroadcastQuery(event: event.rawValue),
            body: payload
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(.iso8601Full)

        guard
            let requestData = try? encoder.encode(request),
            let requestJson = String(data: requestData, encoding: .utf8)
        else {
            return
        }

        socket?.send(requestJson)
    }

    func websocketDidConnect () {
        debug("Connected to Websocket connection")
    }

    func websocketDidDisconnect (error: Error?) {
        self.socket = nil
        debug("Disconnected from Websocket connection")
        connectedAndAuthenticated = false
        self.connect()
    }

    func websocketDidReceiveMessage (socket: WebSocketKit.WebSocket, text: String) {
        debug(text)
        guard let data = text.data(using: .utf8), let initialField = RatSocket.getInitialField(from: data) else {
            return
        }

        if let ratSocketEvent = RatSocketEventType(rawValue: initialField) {
            switch ratSocketEvent {
                case .connection:
                    connectedAndAuthenticated = true
                    debug("Received welcome from Websocket connection")

//                case .rescueCreated:
//                    RatSocket.getEventAndPost(notification: RatSocketRescueCreatedNotification.self, from: data)
//
//                case .rescueUpdated:
//                    RatSocket.getEventAndPost(notification: RatSocketRescueUpdatedNotification.self, from: data)
//
//                case .rescueDeleted:
//                    RatSocket.getEventAndPost(notification: RatSocketRescueDeletedNotification.self, from: data)
//
//                case .userUpdated:
//                    RatSocket.getEventAndPost(notification: RatSocketUserUpdatedNotification.self, from: data)

                default:
                    break
            }
        }
    }

    @discardableResult
    static func getEventAndPost<Notification: NotificationDescriptor, Event: Decodable>
    (notification: Notification.Type, from data: Data) -> RatSocketEvent<Event>?
    where Notification.Payload == RatSocketEvent<Event> {
        guard let event = try? RatSocketEvent<Event>.from(data) else {
            return nil
        }

        Notification().encode(payload: event).post()
        return event
    }

    static func getInitialField (from data: Data) -> String? {
        let decoder = JSONDecoder()
        guard let genericResponse = try? decoder.decode(GenericSocketData.self, from: data) else {
            return nil
        }
        return genericResponse.originField
    }
}

struct BroadcastQuery: Encodable {
    let event: String
}

struct GenericSocketData: Decodable {
    let originField: String

    init (from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        originField = try container.decode(String.self)
    }
}

struct RatSocketEvent<Body: Decodable>: Decodable {
    let event: String
    let sender: UUID
    let resourceIdentifier: String?
    let body: Body?

    init (from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        self.event = try container.decode(String.self)
        self.sender = try container.decode(UUID.self)
        if let resourceIdentifier = try? container.decode(String.self) {
            self.resourceIdentifier = resourceIdentifier
            self.body = try container.decode(Body.self)
        } else {
            self.resourceIdentifier = nil
            self.body = try container.decode(Body.self)
        }
    }

    static func from (_ data: Data) throws -> RatSocketEvent<Body> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(.iso8601Full)
        return try decoder.decode(RatSocketEvent<Body>.self, from: data)
    }
}

struct RatSocketRequest<Query: Encodable, Body: Encodable>: Encodable {
    let state: String
    let endpoint: [String]
    let query: Query
    let body: Body

    init (endpoint: [String], query: Query, body: Body) {
        self.state = UUID().uuidString
        self.endpoint = endpoint
        self.query = query
        self.body = body
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(state)
        try container.encode(endpoint)
        try container.encode(query)
        try container.encode(body)
    }

    struct EmptyQuery: Encodable {}

    struct EmptyBody: Encodable {}
}

struct RatSocketResponse<Body: Decodable>: Decodable {
    let state: String
    let status: HTTPResponseStatus
    let body: Body

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        self.state = try container.decode(String.self)
        let statusCode = try container.decode(Int.self)
        self.status = HTTPResponseStatus(statusCode: statusCode)
        self.body = try container.decode(Body.self)
    }
}

struct ChannelMessageEventPayload: Codable {
    var label: String
    var time: Date
    var sender: Sender
    var destination: String
    var contents: String

    init (channelMessage: IRCPrivateMessage) {
        label = channelMessage.raw.label
        time = channelMessage.raw.time
        sender = Sender(user: channelMessage.user)
        destination = channelMessage.destination.name
        contents = channelMessage.message
    }

    struct Sender: Codable {
        var nickname: String
        var username: String
        var hostmask: String
        var realName: String?
        var account: String?
        var isIRCOperator: Bool
        var securelyConnected: Bool
        var isAway: Bool
        var usermodes: [String] = []

        init (user: IRCUser) {
            self.nickname = user.nickname
            self.username = user.username
            self.hostmask = user.hostmask
            self.realName = user.realName
            self.account = user.account
            self.isIRCOperator = user.isIRCOperator
            self.securelyConnected = user.isSecure
            self.isAway = user.isAway
            self.usermodes = Array(user.channelUserModes.map({ "\($0)" }))
        }
    }
}

