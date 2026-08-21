public extension Api {
    enum GeoPoint: TypeConstructorDescription {
        public class Cons_geoPoint: TypeConstructorDescription {
            public var flags: Int32
            public var long: Double
            public var lat: Double
            public var accessHash: Int64
            public var accuracyRadius: Int32?
            public init(flags: Int32, long: Double, lat: Double, accessHash: Int64, accuracyRadius: Int32?) {
                self.flags = flags
                self.long = long
                self.lat = lat
                self.accessHash = accessHash
                self.accuracyRadius = accuracyRadius
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("geoPoint", [("flags", ConstructorParameterDescription(self.flags)), ("long", ConstructorParameterDescription(self.long)), ("lat", ConstructorParameterDescription(self.lat)), ("accessHash", ConstructorParameterDescription(self.accessHash)), ("accuracyRadius", ConstructorParameterDescription(self.accuracyRadius))])
            }
        }
        case geoPoint(Cons_geoPoint)
        case geoPointEmpty

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .geoPoint(let _data):
                if boxed {
                    buffer.appendInt32(-1297942941)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeDouble(_data.long, buffer: buffer, boxed: false)
                serializeDouble(_data.lat, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    serializeInt32(_data.accuracyRadius!, buffer: buffer, boxed: false)
                }
                break
            case .geoPointEmpty:
                if boxed {
                    buffer.appendInt32(286776671)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .geoPoint(let _data):
                return ("geoPoint", [("flags", ConstructorParameterDescription(_data.flags)), ("long", ConstructorParameterDescription(_data.long)), ("lat", ConstructorParameterDescription(_data.lat)), ("accessHash", ConstructorParameterDescription(_data.accessHash)), ("accuracyRadius", ConstructorParameterDescription(_data.accuracyRadius))])
            case .geoPointEmpty:
                return ("geoPointEmpty", [])
            }
        }

        public static func parse_geoPoint(_ reader: BufferReader) -> GeoPoint? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Double?
            _2 = reader.readDouble()
            var _3: Double?
            _3 = reader.readDouble()
            var _4: Int64?
            _4 = reader.readInt64()
            var _5: Int32?
            if Int(_1 ?? 0) & Int(1 << 0) != 0 {
                _5 = reader.readInt32()
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = (Int(_1 ?? 0) & Int(1 << 0) == 0) || _5 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 {
                return Api.GeoPoint.geoPoint(Cons_geoPoint(flags: _1!, long: _2!, lat: _3!, accessHash: _4!, accuracyRadius: _5))
            }
            else {
                return nil
            }
        }
        public static func parse_geoPointEmpty(_ reader: BufferReader) -> GeoPoint? {
            return Api.GeoPoint.geoPointEmpty
        }
    }
}
public extension Api {
    enum GeoPointAddress: TypeConstructorDescription {
        public class Cons_geoPointAddress: TypeConstructorDescription {
            public var flags: Int32
            public var countryIso2: String
            public var state: String?
            public var city: String?
            public var street: String?
            public init(flags: Int32, countryIso2: String, state: String?, city: String?, street: String?) {
                self.flags = flags
                self.countryIso2 = countryIso2
                self.state = state
                self.city = city
                self.street = street
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("geoPointAddress", [("flags", ConstructorParameterDescription(self.flags)), ("countryIso2", ConstructorParameterDescription(self.countryIso2)), ("state", ConstructorParameterDescription(self.state)), ("city", ConstructorParameterDescription(self.city)), ("street", ConstructorParameterDescription(self.street))])
            }
        }
        case geoPointAddress(Cons_geoPointAddress)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .geoPointAddress(let _data):
                if boxed {
                    buffer.appendInt32(-565420653)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeString(_data.countryIso2, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    serializeString(_data.state!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeString(_data.city!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    serializeString(_data.street!, buffer: buffer, boxed: false)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .geoPointAddress(let _data):
                return ("geoPointAddress", [("flags", ConstructorParameterDescription(_data.flags)), ("countryIso2", ConstructorParameterDescription(_data.countryIso2)), ("state", ConstructorParameterDescription(_data.state)), ("city", ConstructorParameterDescription(_data.city)), ("street", ConstructorParameterDescription(_data.street))])
            }
        }

        public static func parse_geoPointAddress(_ reader: BufferReader) -> GeoPointAddress? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            _2 = parseString(reader)
            var _3: String?
            if Int(_1 ?? 0) & Int(1 << 0) != 0 {
                _3 = parseString(reader)
            }
            var _4: String?
            if Int(_1 ?? 0) & Int(1 << 1) != 0 {
                _4 = parseString(reader)
            }
            var _5: String?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                _5 = parseString(reader)
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1 ?? 0) & Int(1 << 0) == 0) || _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 1) == 0) || _4 != nil
            let _c5 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _5 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 {
                return Api.GeoPointAddress.geoPointAddress(Cons_geoPointAddress(flags: _1!, countryIso2: _2!, state: _3, city: _4, street: _5))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum GlobalPrivacySettings: TypeConstructorDescription {
        public class Cons_globalPrivacySettings: TypeConstructorDescription {
            public var flags: Int32
            public var noncontactPeersPaidStars: Int64?
            public var disallowedGifts: Api.DisallowedGiftsSettings?
            public init(flags: Int32, noncontactPeersPaidStars: Int64?, disallowedGifts: Api.DisallowedGiftsSettings?) {
                self.flags = flags
                self.noncontactPeersPaidStars = noncontactPeersPaidStars
                self.disallowedGifts = disallowedGifts
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("globalPrivacySettings", [("flags", ConstructorParameterDescription(self.flags)), ("noncontactPeersPaidStars", ConstructorParameterDescription(self.noncontactPeersPaidStars)), ("disallowedGifts", ConstructorParameterDescription(self.disallowedGifts))])
            }
        }
        case globalPrivacySettings(Cons_globalPrivacySettings)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .globalPrivacySettings(let _data):
                if boxed {
                    buffer.appendInt32(-29248689)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 5) != 0 {
                    serializeInt64(_data.noncontactPeersPaidStars!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 6) != 0 {
                    _data.disallowedGifts!.serialize(buffer, true)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .globalPrivacySettings(let _data):
                return ("globalPrivacySettings", [("flags", ConstructorParameterDescription(_data.flags)), ("noncontactPeersPaidStars", ConstructorParameterDescription(_data.noncontactPeersPaidStars)), ("disallowedGifts", ConstructorParameterDescription(_data.disallowedGifts))])
            }
        }

        public static func parse_globalPrivacySettings(_ reader: BufferReader) -> GlobalPrivacySettings? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            if Int(_1 ?? 0) & Int(1 << 5) != 0 {
                _2 = reader.readInt64()
            }
            var _3: Api.DisallowedGiftsSettings?
            if Int(_1 ?? 0) & Int(1 << 6) != 0 {
                if let signature = reader.readInt32() {
                    _3 = Api.parse(reader, signature: signature) as? Api.DisallowedGiftsSettings
                }
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1 ?? 0) & Int(1 << 5) == 0) || _2 != nil
            let _c3 = (Int(_1 ?? 0) & Int(1 << 6) == 0) || _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.GlobalPrivacySettings.globalPrivacySettings(Cons_globalPrivacySettings(flags: _1!, noncontactPeersPaidStars: _2, disallowedGifts: _3))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum GroupCall: TypeConstructorDescription {
        public class Cons_groupCall: TypeConstructorDescription {
            public var flags: Int32
            public var id: Int64
            public var accessHash: Int64
            public var participantsCount: Int32
            public var title: String?
            public var streamDcId: Int32?
            public var recordStartDate: Int32?
            public var scheduleDate: Int32?
            public var unmutedVideoCount: Int32?
            public var unmutedVideoLimit: Int32
            public var version: Int32
            public var inviteLink: String?
            public var sendPaidMessagesStars: Int64?
            public var defaultSendAs: Api.Peer?
            public init(flags: Int32, id: Int64, accessHash: Int64, participantsCount: Int32, title: String?, streamDcId: Int32?, recordStartDate: Int32?, scheduleDate: Int32?, unmutedVideoCount: Int32?, unmutedVideoLimit: Int32, version: Int32, inviteLink: String?, sendPaidMessagesStars: Int64?, defaultSendAs: Api.Peer?) {
                self.flags = flags
                self.id = id
                self.accessHash = accessHash
                self.participantsCount = participantsCount
                self.title = title
                self.streamDcId = streamDcId
                self.recordStartDate = recordStartDate
                self.scheduleDate = scheduleDate
                self.unmutedVideoCount = unmutedVideoCount
                self.unmutedVideoLimit = unmutedVideoLimit
                self.version = version
                self.inviteLink = inviteLink
                self.sendPaidMessagesStars = sendPaidMessagesStars
                self.defaultSendAs = defaultSendAs
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("groupCall", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash)), ("participantsCount", ConstructorParameterDescription(self.participantsCount)), ("title", ConstructorParameterDescription(self.title)), ("streamDcId", ConstructorParameterDescription(self.streamDcId)), ("recordStartDate", ConstructorParameterDescription(self.recordStartDate)), ("scheduleDate", ConstructorParameterDescription(self.scheduleDate)), ("unmutedVideoCount", ConstructorParameterDescription(self.unmutedVideoCount)), ("unmutedVideoLimit", ConstructorParameterDescription(self.unmutedVideoLimit)), ("version", ConstructorParameterDescription(self.version)), ("inviteLink", ConstructorParameterDescription(self.inviteLink)), ("sendPaidMessagesStars", ConstructorParameterDescription(self.sendPaidMessagesStars)), ("defaultSendAs", ConstructorParameterDescription(self.defaultSendAs))])
            }
        }
        public class Cons_groupCallDiscarded: TypeConstructorDescription {
            public var id: Int64
            public var accessHash: Int64
            public var duration: Int32
            public init(id: Int64, accessHash: Int64, duration: Int32) {
                self.id = id
                self.accessHash = accessHash
                self.duration = duration
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("groupCallDiscarded", [("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash)), ("duration", ConstructorParameterDescription(self.duration))])
            }
        }
        case groupCall(Cons_groupCall)
        case groupCallDiscarded(Cons_groupCallDiscarded)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .groupCall(let _data):
                if boxed {
                    buffer.appendInt32(-273500649)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                serializeInt32(_data.participantsCount, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 3) != 0 {
                    serializeString(_data.title!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 4) != 0 {
                    serializeInt32(_data.streamDcId!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 5) != 0 {
                    serializeInt32(_data.recordStartDate!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 7) != 0 {
                    serializeInt32(_data.scheduleDate!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 10) != 0 {
                    serializeInt32(_data.unmutedVideoCount!, buffer: buffer, boxed: false)
                }
                serializeInt32(_data.unmutedVideoLimit, buffer: buffer, boxed: false)
                serializeInt32(_data.version, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 16) != 0 {
                    serializeString(_data.inviteLink!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 20) != 0 {
                    serializeInt64(_data.sendPaidMessagesStars!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 21) != 0 {
                    _data.defaultSendAs!.serialize(buffer, true)
                }
                break
            case .groupCallDiscarded(let _data):
                if boxed {
                    buffer.appendInt32(2004925620)
                }
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                serializeInt32(_data.duration, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .groupCall(let _data):
                return ("groupCall", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash)), ("participantsCount", ConstructorParameterDescription(_data.participantsCount)), ("title", ConstructorParameterDescription(_data.title)), ("streamDcId", ConstructorParameterDescription(_data.streamDcId)), ("recordStartDate", ConstructorParameterDescription(_data.recordStartDate)), ("scheduleDate", ConstructorParameterDescription(_data.scheduleDate)), ("unmutedVideoCount", ConstructorParameterDescription(_data.unmutedVideoCount)), ("unmutedVideoLimit", ConstructorParameterDescription(_data.unmutedVideoLimit)), ("version", ConstructorParameterDescription(_data.version)), ("inviteLink", ConstructorParameterDescription(_data.inviteLink)), ("sendPaidMessagesStars", ConstructorParameterDescription(_data.sendPaidMessagesStars)), ("defaultSendAs", ConstructorParameterDescription(_data.defaultSendAs))])
            case .groupCallDiscarded(let _data):
                return ("groupCallDiscarded", [("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash)), ("duration", ConstructorParameterDescription(_data.duration))])
            }
        }

        public static func parse_groupCall(_ reader: BufferReader) -> GroupCall? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Int64?
            _3 = reader.readInt64()
            var _4: Int32?
            _4 = reader.readInt32()
            var _5: String?
            if Int(_1 ?? 0) & Int(1 << 3) != 0 {
                _5 = parseString(reader)
            }
            var _6: Int32?
            if Int(_1 ?? 0) & Int(1 << 4) != 0 {
                _6 = reader.readInt32()
            }
            var _7: Int32?
            if Int(_1 ?? 0) & Int(1 << 5) != 0 {
                _7 = reader.readInt32()
            }
            var _8: Int32?
            if Int(_1 ?? 0) & Int(1 << 7) != 0 {
                _8 = reader.readInt32()
            }
            var _9: Int32?
            if Int(_1 ?? 0) & Int(1 << 10) != 0 {
                _9 = reader.readInt32()
            }
            var _10: Int32?
            _10 = reader.readInt32()
            var _11: Int32?
            _11 = reader.readInt32()
            var _12: String?
            if Int(_1 ?? 0) & Int(1 << 16) != 0 {
                _12 = parseString(reader)
            }
            var _13: Int64?
            if Int(_1 ?? 0) & Int(1 << 20) != 0 {
                _13 = reader.readInt64()
            }
            var _14: Api.Peer?
            if Int(_1 ?? 0) & Int(1 << 21) != 0 {
                if let signature = reader.readInt32() {
                    _14 = Api.parse(reader, signature: signature) as? Api.Peer
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = (Int(_1 ?? 0) & Int(1 << 3) == 0) || _5 != nil
            let _c6 = (Int(_1 ?? 0) & Int(1 << 4) == 0) || _6 != nil
            let _c7 = (Int(_1 ?? 0) & Int(1 << 5) == 0) || _7 != nil
            let _c8 = (Int(_1 ?? 0) & Int(1 << 7) == 0) || _8 != nil
            let _c9 = (Int(_1 ?? 0) & Int(1 << 10) == 0) || _9 != nil
            let _c10 = _10 != nil
            let _c11 = _11 != nil
            let _c12 = (Int(_1 ?? 0) & Int(1 << 16) == 0) || _12 != nil
            let _c13 = (Int(_1 ?? 0) & Int(1 << 20) == 0) || _13 != nil
            let _c14 = (Int(_1 ?? 0) & Int(1 << 21) == 0) || _14 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 && _c9 && _c10 && _c11 && _c12 && _c13 && _c14 {
                return Api.GroupCall.groupCall(Cons_groupCall(flags: _1!, id: _2!, accessHash: _3!, participantsCount: _4!, title: _5, streamDcId: _6, recordStartDate: _7, scheduleDate: _8, unmutedVideoCount: _9, unmutedVideoLimit: _10!, version: _11!, inviteLink: _12, sendPaidMessagesStars: _13, defaultSendAs: _14))
            }
            else {
                return nil
            }
        }
        public static func parse_groupCallDiscarded(_ reader: BufferReader) -> GroupCall? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Int32?
            _3 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.GroupCall.groupCallDiscarded(Cons_groupCallDiscarded(id: _1!, accessHash: _2!, duration: _3!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum GroupCallDonor: TypeConstructorDescription {
        public class Cons_groupCallDonor: TypeConstructorDescription {
            public var flags: Int32
            public var peerId: Api.Peer?
            public var stars: Int64
            public init(flags: Int32, peerId: Api.Peer?, stars: Int64) {
                self.flags = flags
                self.peerId = peerId
                self.stars = stars
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("groupCallDonor", [("flags", ConstructorParameterDescription(self.flags)), ("peerId", ConstructorParameterDescription(self.peerId)), ("stars", ConstructorParameterDescription(self.stars))])
            }
        }
        case groupCallDonor(Cons_groupCallDonor)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .groupCallDonor(let _data):
                if boxed {
                    buffer.appendInt32(-297595771)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 3) != 0 {
                    _data.peerId!.serialize(buffer, true)
                }
                serializeInt64(_data.stars, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .groupCallDonor(let _data):
                return ("groupCallDonor", [("flags", ConstructorParameterDescription(_data.flags)), ("peerId", ConstructorParameterDescription(_data.peerId)), ("stars", ConstructorParameterDescription(_data.stars))])
            }
        }

        public static func parse_groupCallDonor(_ reader: BufferReader) -> GroupCallDonor? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.Peer?
            if Int(_1 ?? 0) & Int(1 << 3) != 0 {
                if let signature = reader.readInt32() {
                    _2 = Api.parse(reader, signature: signature) as? Api.Peer
                }
            }
            var _3: Int64?
            _3 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = (Int(_1 ?? 0) & Int(1 << 3) == 0) || _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.GroupCallDonor.groupCallDonor(Cons_groupCallDonor(flags: _1!, peerId: _2, stars: _3!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum GroupCallMessage: TypeConstructorDescription {
        public class Cons_groupCallMessage: TypeConstructorDescription {
            public var flags: Int32
            public var id: Int32
            public var fromId: Api.Peer
            public var date: Int32
            public var message: Api.TextWithEntities
            public var paidMessageStars: Int64?
            public init(flags: Int32, id: Int32, fromId: Api.Peer, date: Int32, message: Api.TextWithEntities, paidMessageStars: Int64?) {
                self.flags = flags
                self.id = id
                self.fromId = fromId
                self.date = date
                self.message = message
                self.paidMessageStars = paidMessageStars
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("groupCallMessage", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("fromId", ConstructorParameterDescription(self.fromId)), ("date", ConstructorParameterDescription(self.date)), ("message", ConstructorParameterDescription(self.message)), ("paidMessageStars", ConstructorParameterDescription(self.paidMessageStars))])
            }
        }
        case groupCallMessage(Cons_groupCallMessage)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .groupCallMessage(let _data):
                if boxed {
                    buffer.appendInt32(445316222)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt32(_data.id, buffer: buffer, boxed: false)
                _data.fromId.serialize(buffer, true)
                serializeInt32(_data.date, buffer: buffer, boxed: false)
                _data.message.serialize(buffer, true)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    serializeInt64(_data.paidMessageStars!, buffer: buffer, boxed: false)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .groupCallMessage(let _data):
                return ("groupCallMessage", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("fromId", ConstructorParameterDescription(_data.fromId)), ("date", ConstructorParameterDescription(_data.date)), ("message", ConstructorParameterDescription(_data.message)), ("paidMessageStars", ConstructorParameterDescription(_data.paidMessageStars))])
            }
        }

        public static func parse_groupCallMessage(_ reader: BufferReader) -> GroupCallMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Api.Peer?
            if let signature = reader.readInt32() {
                _3 = Api.parse(reader, signature: signature) as? Api.Peer
            }
            var _4: Int32?
            _4 = reader.readInt32()
            var _5: Api.TextWithEntities?
            if let signature = reader.readInt32() {
                _5 = Api.parse(reader, signature: signature) as? Api.TextWithEntities
            }
            var _6: Int64?
            if Int(_1 ?? 0) & Int(1 << 0) != 0 {
                _6 = reader.readInt64()
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = (Int(_1 ?? 0) & Int(1 << 0) == 0) || _6 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 {
                return Api.GroupCallMessage.groupCallMessage(Cons_groupCallMessage(flags: _1!, id: _2!, fromId: _3!, date: _4!, message: _5!, paidMessageStars: _6))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum GroupCallParticipant: TypeConstructorDescription {
        public class Cons_groupCallParticipant: TypeConstructorDescription {
            public var flags: Int32
            public var peer: Api.Peer
            public var date: Int32
            public var activeDate: Int32?
            public var source: Int32
            public var volume: Int32?
            public var about: String?
            public var raiseHandRating: Int64?
            public var video: Api.GroupCallParticipantVideo?
            public var presentation: Api.GroupCallParticipantVideo?
            public var paidStarsTotal: Int64?
            public init(flags: Int32, peer: Api.Peer, date: Int32, activeDate: Int32?, source: Int32, volume: Int32?, about: String?, raiseHandRating: Int64?, video: Api.GroupCallParticipantVideo?, presentation: Api.GroupCallParticipantVideo?, paidStarsTotal: Int64?) {
                self.flags = flags
                self.peer = peer
                self.date = date
                self.activeDate = activeDate
                self.source = source
                self.volume = volume
                self.about = about
                self.raiseHandRating = raiseHandRating
                self.video = video
                self.presentation = presentation
                self.paidStarsTotal = paidStarsTotal
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("groupCallParticipant", [("flags", ConstructorParameterDescription(self.flags)), ("peer", ConstructorParameterDescription(self.peer)), ("date", ConstructorParameterDescription(self.date)), ("activeDate", ConstructorParameterDescription(self.activeDate)), ("source", ConstructorParameterDescription(self.source)), ("volume", ConstructorParameterDescription(self.volume)), ("about", ConstructorParameterDescription(self.about)), ("raiseHandRating", ConstructorParameterDescription(self.raiseHandRating)), ("video", ConstructorParameterDescription(self.video)), ("presentation", ConstructorParameterDescription(self.presentation)), ("paidStarsTotal", ConstructorParameterDescription(self.paidStarsTotal))])
            }
        }
        case groupCallParticipant(Cons_groupCallParticipant)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .groupCallParticipant(let _data):
                if boxed {
                    buffer.appendInt32(708691884)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                _data.peer.serialize(buffer, true)
                serializeInt32(_data.date, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 3) != 0 {
                    serializeInt32(_data.activeDate!, buffer: buffer, boxed: false)
                }
                serializeInt32(_data.source, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 7) != 0 {
                    serializeInt32(_data.volume!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 11) != 0 {
                    serializeString(_data.about!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 13) != 0 {
                    serializeInt64(_data.raiseHandRating!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 6) != 0 {
                    _data.video!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 14) != 0 {
                    _data.presentation!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 16) != 0 {
                    serializeInt64(_data.paidStarsTotal!, buffer: buffer, boxed: false)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .groupCallParticipant(let _data):
                return ("groupCallParticipant", [("flags", ConstructorParameterDescription(_data.flags)), ("peer", ConstructorParameterDescription(_data.peer)), ("date", ConstructorParameterDescription(_data.date)), ("activeDate", ConstructorParameterDescription(_data.activeDate)), ("source", ConstructorParameterDescription(_data.source)), ("volume", ConstructorParameterDescription(_data.volume)), ("about", ConstructorParameterDescription(_data.about)), ("raiseHandRating", ConstructorParameterDescription(_data.raiseHandRating)), ("video", ConstructorParameterDescription(_data.video)), ("presentation", ConstructorParameterDescription(_data.presentation)), ("paidStarsTotal", ConstructorParameterDescription(_data.paidStarsTotal))])
            }
        }

        public static func parse_groupCallParticipant(_ reader: BufferReader) -> GroupCallParticipant? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.Peer?
            if let signature = reader.readInt32() {
                _2 = Api.parse(reader, signature: signature) as? Api.Peer
            }
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: Int32?
            if Int(_1 ?? 0) & Int(1 << 3) != 0 {
                _4 = reader.readInt32()
            }
            var _5: Int32?
            _5 = reader.readInt32()
            var _6: Int32?
            if Int(_1 ?? 0) & Int(1 << 7) != 0 {
                _6 = reader.readInt32()
            }
            var _7: String?
            if Int(_1 ?? 0) & Int(1 << 11) != 0 {
                _7 = parseString(reader)
            }
            var _8: Int64?
            if Int(_1 ?? 0) & Int(1 << 13) != 0 {
                _8 = reader.readInt64()
            }
            var _9: Api.GroupCallParticipantVideo?
            if Int(_1 ?? 0) & Int(1 << 6) != 0 {
                if let signature = reader.readInt32() {
                    _9 = Api.parse(reader, signature: signature) as? Api.GroupCallParticipantVideo
                }
            }
            var _10: Api.GroupCallParticipantVideo?
            if Int(_1 ?? 0) & Int(1 << 14) != 0 {
                if let signature = reader.readInt32() {
                    _10 = Api.parse(reader, signature: signature) as? Api.GroupCallParticipantVideo
                }
            }
            var _11: Int64?
            if Int(_1 ?? 0) & Int(1 << 16) != 0 {
                _11 = reader.readInt64()
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 3) == 0) || _4 != nil
            let _c5 = _5 != nil
            let _c6 = (Int(_1 ?? 0) & Int(1 << 7) == 0) || _6 != nil
            let _c7 = (Int(_1 ?? 0) & Int(1 << 11) == 0) || _7 != nil
            let _c8 = (Int(_1 ?? 0) & Int(1 << 13) == 0) || _8 != nil
            let _c9 = (Int(_1 ?? 0) & Int(1 << 6) == 0) || _9 != nil
            let _c10 = (Int(_1 ?? 0) & Int(1 << 14) == 0) || _10 != nil
            let _c11 = (Int(_1 ?? 0) & Int(1 << 16) == 0) || _11 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 && _c9 && _c10 && _c11 {
                return Api.GroupCallParticipant.groupCallParticipant(Cons_groupCallParticipant(flags: _1!, peer: _2!, date: _3!, activeDate: _4, source: _5!, volume: _6, about: _7, raiseHandRating: _8, video: _9, presentation: _10, paidStarsTotal: _11))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum GroupCallParticipantVideo: TypeConstructorDescription {
        public class Cons_groupCallParticipantVideo: TypeConstructorDescription {
            public var flags: Int32
            public var endpoint: String
            public var sourceGroups: [Api.GroupCallParticipantVideoSourceGroup]
            public var audioSource: Int32?
            public init(flags: Int32, endpoint: String, sourceGroups: [Api.GroupCallParticipantVideoSourceGroup], audioSource: Int32?) {
                self.flags = flags
                self.endpoint = endpoint
                self.sourceGroups = sourceGroups
                self.audioSource = audioSource
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("groupCallParticipantVideo", [("flags", ConstructorParameterDescription(self.flags)), ("endpoint", ConstructorParameterDescription(self.endpoint)), ("sourceGroups", ConstructorParameterDescription(self.sourceGroups)), ("audioSource", ConstructorParameterDescription(self.audioSource))])
            }
        }
        case groupCallParticipantVideo(Cons_groupCallParticipantVideo)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .groupCallParticipantVideo(let _data):
                if boxed {
                    buffer.appendInt32(1735736008)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeString(_data.endpoint, buffer: buffer, boxed: false)
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.sourceGroups.count))
                for item in _data.sourceGroups {
                    item.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeInt32(_data.audioSource!, buffer: buffer, boxed: false)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .groupCallParticipantVideo(let _data):
                return ("groupCallParticipantVideo", [("flags", ConstructorParameterDescription(_data.flags)), ("endpoint", ConstructorParameterDescription(_data.endpoint)), ("sourceGroups", ConstructorParameterDescription(_data.sourceGroups)), ("audioSource", ConstructorParameterDescription(_data.audioSource))])
            }
        }

        public static func parse_groupCallParticipantVideo(_ reader: BufferReader) -> GroupCallParticipantVideo? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            _2 = parseString(reader)
            var _3: [Api.GroupCallParticipantVideoSourceGroup]?
            if let _ = reader.readInt32() {
                _3 = Api.parseVector(reader, elementSignature: 0, elementType: Api.GroupCallParticipantVideoSourceGroup.self)
            }
            var _4: Int32?
            if Int(_1 ?? 0) & Int(1 << 1) != 0 {
                _4 = reader.readInt32()
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 1) == 0) || _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.GroupCallParticipantVideo.groupCallParticipantVideo(Cons_groupCallParticipantVideo(flags: _1!, endpoint: _2!, sourceGroups: _3!, audioSource: _4))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum GroupCallParticipantVideoSourceGroup: TypeConstructorDescription {
        public class Cons_groupCallParticipantVideoSourceGroup: TypeConstructorDescription {
            public var semantics: String
            public var sources: [Int32]
            public init(semantics: String, sources: [Int32]) {
                self.semantics = semantics
                self.sources = sources
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("groupCallParticipantVideoSourceGroup", [("semantics", ConstructorParameterDescription(self.semantics)), ("sources", ConstructorParameterDescription(self.sources))])
            }
        }
        case groupCallParticipantVideoSourceGroup(Cons_groupCallParticipantVideoSourceGroup)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .groupCallParticipantVideoSourceGroup(let _data):
                if boxed {
                    buffer.appendInt32(-592373577)
                }
                serializeString(_data.semantics, buffer: buffer, boxed: false)
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.sources.count))
                for item in _data.sources {
                    serializeInt32(item, buffer: buffer, boxed: false)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .groupCallParticipantVideoSourceGroup(let _data):
                return ("groupCallParticipantVideoSourceGroup", [("semantics", ConstructorParameterDescription(_data.semantics)), ("sources", ConstructorParameterDescription(_data.sources))])
            }
        }

        public static func parse_groupCallParticipantVideoSourceGroup(_ reader: BufferReader) -> GroupCallParticipantVideoSourceGroup? {
            var _1: String?
            _1 = parseString(reader)
            var _2: [Int32]?
            if let _ = reader.readInt32() {
                _2 = Api.parseVector(reader, elementSignature: -1471112230, elementType: Int32.self)
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.GroupCallParticipantVideoSourceGroup.groupCallParticipantVideoSourceGroup(Cons_groupCallParticipantVideoSourceGroup(semantics: _1!, sources: _2!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum GroupCallStreamChannel: TypeConstructorDescription {
        public class Cons_groupCallStreamChannel: TypeConstructorDescription {
            public var channel: Int32
            public var scale: Int32
            public var lastTimestampMs: Int64
            public init(channel: Int32, scale: Int32, lastTimestampMs: Int64) {
                self.channel = channel
                self.scale = scale
                self.lastTimestampMs = lastTimestampMs
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("groupCallStreamChannel", [("channel", ConstructorParameterDescription(self.channel)), ("scale", ConstructorParameterDescription(self.scale)), ("lastTimestampMs", ConstructorParameterDescription(self.lastTimestampMs))])
            }
        }
        case groupCallStreamChannel(Cons_groupCallStreamChannel)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .groupCallStreamChannel(let _data):
                if boxed {
                    buffer.appendInt32(-2132064081)
                }
                serializeInt32(_data.channel, buffer: buffer, boxed: false)
                serializeInt32(_data.scale, buffer: buffer, boxed: false)
                serializeInt64(_data.lastTimestampMs, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .groupCallStreamChannel(let _data):
                return ("groupCallStreamChannel", [("channel", ConstructorParameterDescription(_data.channel)), ("scale", ConstructorParameterDescription(_data.scale)), ("lastTimestampMs", ConstructorParameterDescription(_data.lastTimestampMs))])
            }
        }

        public static func parse_groupCallStreamChannel(_ reader: BufferReader) -> GroupCallStreamChannel? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Int64?
            _3 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.GroupCallStreamChannel.groupCallStreamChannel(Cons_groupCallStreamChannel(channel: _1!, scale: _2!, lastTimestampMs: _3!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum HighScore: TypeConstructorDescription {
        public class Cons_highScore: TypeConstructorDescription {
            public var pos: Int32
            public var userId: Int64
            public var score: Int32
            public init(pos: Int32, userId: Int64, score: Int32) {
                self.pos = pos
                self.userId = userId
                self.score = score
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("highScore", [("pos", ConstructorParameterDescription(self.pos)), ("userId", ConstructorParameterDescription(self.userId)), ("score", ConstructorParameterDescription(self.score))])
            }
        }
        case highScore(Cons_highScore)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .highScore(let _data):
                if boxed {
                    buffer.appendInt32(1940093419)
                }
                serializeInt32(_data.pos, buffer: buffer, boxed: false)
                serializeInt64(_data.userId, buffer: buffer, boxed: false)
                serializeInt32(_data.score, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .highScore(let _data):
                return ("highScore", [("pos", ConstructorParameterDescription(_data.pos)), ("userId", ConstructorParameterDescription(_data.userId)), ("score", ConstructorParameterDescription(_data.score))])
            }
        }

        public static func parse_highScore(_ reader: BufferReader) -> HighScore? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Int32?
            _3 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.HighScore.highScore(Cons_highScore(pos: _1!, userId: _2!, score: _3!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum ImportedContact: TypeConstructorDescription {
        public class Cons_importedContact: TypeConstructorDescription {
            public var userId: Int64
            public var clientId: Int64
            public init(userId: Int64, clientId: Int64) {
                self.userId = userId
                self.clientId = clientId
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("importedContact", [("userId", ConstructorParameterDescription(self.userId)), ("clientId", ConstructorParameterDescription(self.clientId))])
            }
        }
        case importedContact(Cons_importedContact)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .importedContact(let _data):
                if boxed {
                    buffer.appendInt32(-1052885936)
                }
                serializeInt64(_data.userId, buffer: buffer, boxed: false)
                serializeInt64(_data.clientId, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .importedContact(let _data):
                return ("importedContact", [("userId", ConstructorParameterDescription(_data.userId)), ("clientId", ConstructorParameterDescription(_data.clientId))])
            }
        }

        public static func parse_importedContact(_ reader: BufferReader) -> ImportedContact? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Int64?
            _2 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.ImportedContact.importedContact(Cons_importedContact(userId: _1!, clientId: _2!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InlineBotSwitchPM: TypeConstructorDescription {
        public class Cons_inlineBotSwitchPM: TypeConstructorDescription {
            public var text: String
            public var startParam: String
            public init(text: String, startParam: String) {
                self.text = text
                self.startParam = startParam
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inlineBotSwitchPM", [("text", ConstructorParameterDescription(self.text)), ("startParam", ConstructorParameterDescription(self.startParam))])
            }
        }
        case inlineBotSwitchPM(Cons_inlineBotSwitchPM)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inlineBotSwitchPM(let _data):
                if boxed {
                    buffer.appendInt32(1008755359)
                }
                serializeString(_data.text, buffer: buffer, boxed: false)
                serializeString(_data.startParam, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inlineBotSwitchPM(let _data):
                return ("inlineBotSwitchPM", [("text", ConstructorParameterDescription(_data.text)), ("startParam", ConstructorParameterDescription(_data.startParam))])
            }
        }

        public static func parse_inlineBotSwitchPM(_ reader: BufferReader) -> InlineBotSwitchPM? {
            var _1: String?
            _1 = parseString(reader)
            var _2: String?
            _2 = parseString(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.InlineBotSwitchPM.inlineBotSwitchPM(Cons_inlineBotSwitchPM(text: _1!, startParam: _2!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InlineBotWebView: TypeConstructorDescription {
        public class Cons_inlineBotWebView: TypeConstructorDescription {
            public var text: String
            public var url: String
            public init(text: String, url: String) {
                self.text = text
                self.url = url
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inlineBotWebView", [("text", ConstructorParameterDescription(self.text)), ("url", ConstructorParameterDescription(self.url))])
            }
        }
        case inlineBotWebView(Cons_inlineBotWebView)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inlineBotWebView(let _data):
                if boxed {
                    buffer.appendInt32(-1250781739)
                }
                serializeString(_data.text, buffer: buffer, boxed: false)
                serializeString(_data.url, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inlineBotWebView(let _data):
                return ("inlineBotWebView", [("text", ConstructorParameterDescription(_data.text)), ("url", ConstructorParameterDescription(_data.url))])
            }
        }

        public static func parse_inlineBotWebView(_ reader: BufferReader) -> InlineBotWebView? {
            var _1: String?
            _1 = parseString(reader)
            var _2: String?
            _2 = parseString(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.InlineBotWebView.inlineBotWebView(Cons_inlineBotWebView(text: _1!, url: _2!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InlineQueryPeerType: TypeConstructorDescription {
        case inlineQueryPeerTypeBotPM
        case inlineQueryPeerTypeBroadcast
        case inlineQueryPeerTypeChat
        case inlineQueryPeerTypeMegagroup
        case inlineQueryPeerTypePM
        case inlineQueryPeerTypeSameBotPM

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inlineQueryPeerTypeBotPM:
                if boxed {
                    buffer.appendInt32(238759180)
                }
                break
            case .inlineQueryPeerTypeBroadcast:
                if boxed {
                    buffer.appendInt32(1664413338)
                }
                break
            case .inlineQueryPeerTypeChat:
                if boxed {
                    buffer.appendInt32(-681130742)
                }
                break
            case .inlineQueryPeerTypeMegagroup:
                if boxed {
                    buffer.appendInt32(1589952067)
                }
                break
            case .inlineQueryPeerTypePM:
                if boxed {
                    buffer.appendInt32(-2093215828)
                }
                break
            case .inlineQueryPeerTypeSameBotPM:
                if boxed {
                    buffer.appendInt32(813821341)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inlineQueryPeerTypeBotPM:
                return ("inlineQueryPeerTypeBotPM", [])
            case .inlineQueryPeerTypeBroadcast:
                return ("inlineQueryPeerTypeBroadcast", [])
            case .inlineQueryPeerTypeChat:
                return ("inlineQueryPeerTypeChat", [])
            case .inlineQueryPeerTypeMegagroup:
                return ("inlineQueryPeerTypeMegagroup", [])
            case .inlineQueryPeerTypePM:
                return ("inlineQueryPeerTypePM", [])
            case .inlineQueryPeerTypeSameBotPM:
                return ("inlineQueryPeerTypeSameBotPM", [])
            }
        }

        public static func parse_inlineQueryPeerTypeBotPM(_ reader: BufferReader) -> InlineQueryPeerType? {
            return Api.InlineQueryPeerType.inlineQueryPeerTypeBotPM
        }
        public static func parse_inlineQueryPeerTypeBroadcast(_ reader: BufferReader) -> InlineQueryPeerType? {
            return Api.InlineQueryPeerType.inlineQueryPeerTypeBroadcast
        }
        public static func parse_inlineQueryPeerTypeChat(_ reader: BufferReader) -> InlineQueryPeerType? {
            return Api.InlineQueryPeerType.inlineQueryPeerTypeChat
        }
        public static func parse_inlineQueryPeerTypeMegagroup(_ reader: BufferReader) -> InlineQueryPeerType? {
            return Api.InlineQueryPeerType.inlineQueryPeerTypeMegagroup
        }
        public static func parse_inlineQueryPeerTypePM(_ reader: BufferReader) -> InlineQueryPeerType? {
            return Api.InlineQueryPeerType.inlineQueryPeerTypePM
        }
        public static func parse_inlineQueryPeerTypeSameBotPM(_ reader: BufferReader) -> InlineQueryPeerType? {
            return Api.InlineQueryPeerType.inlineQueryPeerTypeSameBotPM
        }
    }
}
public extension Api {
    enum InputAiComposeTone: TypeConstructorDescription {
        public class Cons_inputAiComposeToneDefault: TypeConstructorDescription {
            public var tone: String
            public init(tone: String) {
                self.tone = tone
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputAiComposeToneDefault", [("tone", ConstructorParameterDescription(self.tone))])
            }
        }
        public class Cons_inputAiComposeToneID: TypeConstructorDescription {
            public var id: Int64
            public var accessHash: Int64
            public init(id: Int64, accessHash: Int64) {
                self.id = id
                self.accessHash = accessHash
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputAiComposeToneID", [("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash))])
            }
        }
        public class Cons_inputAiComposeToneSingleUse: TypeConstructorDescription {
            public var customPrompt: String
            public init(customPrompt: String) {
                self.customPrompt = customPrompt
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputAiComposeToneSingleUse", [("customPrompt", ConstructorParameterDescription(self.customPrompt))])
            }
        }
        public class Cons_inputAiComposeToneSlug: TypeConstructorDescription {
            public var slug: String
            public init(slug: String) {
                self.slug = slug
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputAiComposeToneSlug", [("slug", ConstructorParameterDescription(self.slug))])
            }
        }
        case inputAiComposeToneDefault(Cons_inputAiComposeToneDefault)
        case inputAiComposeToneID(Cons_inputAiComposeToneID)
        case inputAiComposeToneSingleUse(Cons_inputAiComposeToneSingleUse)
        case inputAiComposeToneSlug(Cons_inputAiComposeToneSlug)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputAiComposeToneDefault(let _data):
                if boxed {
                    buffer.appendInt32(535407039)
                }
                serializeString(_data.tone, buffer: buffer, boxed: false)
                break
            case .inputAiComposeToneID(let _data):
                if boxed {
                    buffer.appendInt32(125026432)
                }
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                break
            case .inputAiComposeToneSingleUse(let _data):
                if boxed {
                    buffer.appendInt32(235681199)
                }
                serializeString(_data.customPrompt, buffer: buffer, boxed: false)
                break
            case .inputAiComposeToneSlug(let _data):
                if boxed {
                    buffer.appendInt32(530584407)
                }
                serializeString(_data.slug, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputAiComposeToneDefault(let _data):
                return ("inputAiComposeToneDefault", [("tone", ConstructorParameterDescription(_data.tone))])
            case .inputAiComposeToneID(let _data):
                return ("inputAiComposeToneID", [("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash))])
            case .inputAiComposeToneSingleUse(let _data):
                return ("inputAiComposeToneSingleUse", [("customPrompt", ConstructorParameterDescription(_data.customPrompt))])
            case .inputAiComposeToneSlug(let _data):
                return ("inputAiComposeToneSlug", [("slug", ConstructorParameterDescription(_data.slug))])
            }
        }

        public static func parse_inputAiComposeToneDefault(_ reader: BufferReader) -> InputAiComposeTone? {
            var _1: String?
            _1 = parseString(reader)
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputAiComposeTone.inputAiComposeToneDefault(Cons_inputAiComposeToneDefault(tone: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputAiComposeToneID(_ reader: BufferReader) -> InputAiComposeTone? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Int64?
            _2 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.InputAiComposeTone.inputAiComposeToneID(Cons_inputAiComposeToneID(id: _1!, accessHash: _2!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputAiComposeToneSingleUse(_ reader: BufferReader) -> InputAiComposeTone? {
            var _1: String?
            _1 = parseString(reader)
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputAiComposeTone.inputAiComposeToneSingleUse(Cons_inputAiComposeToneSingleUse(customPrompt: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputAiComposeToneSlug(_ reader: BufferReader) -> InputAiComposeTone? {
            var _1: String?
            _1 = parseString(reader)
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputAiComposeTone.inputAiComposeToneSlug(Cons_inputAiComposeToneSlug(slug: _1!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputAppEvent: TypeConstructorDescription {
        public class Cons_inputAppEvent: TypeConstructorDescription {
            public var time: Double
            public var type: String
            public var peer: Int64
            public var data: Api.JSONValue
            public init(time: Double, type: String, peer: Int64, data: Api.JSONValue) {
                self.time = time
                self.type = type
                self.peer = peer
                self.data = data
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputAppEvent", [("time", ConstructorParameterDescription(self.time)), ("type", ConstructorParameterDescription(self.type)), ("peer", ConstructorParameterDescription(self.peer)), ("data", ConstructorParameterDescription(self.data))])
            }
        }
        case inputAppEvent(Cons_inputAppEvent)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputAppEvent(let _data):
                if boxed {
                    buffer.appendInt32(488313413)
                }
                serializeDouble(_data.time, buffer: buffer, boxed: false)
                serializeString(_data.type, buffer: buffer, boxed: false)
                serializeInt64(_data.peer, buffer: buffer, boxed: false)
                _data.data.serialize(buffer, true)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputAppEvent(let _data):
                return ("inputAppEvent", [("time", ConstructorParameterDescription(_data.time)), ("type", ConstructorParameterDescription(_data.type)), ("peer", ConstructorParameterDescription(_data.peer)), ("data", ConstructorParameterDescription(_data.data))])
            }
        }

        public static func parse_inputAppEvent(_ reader: BufferReader) -> InputAppEvent? {
            var _1: Double?
            _1 = reader.readDouble()
            var _2: String?
            _2 = parseString(reader)
            var _3: Int64?
            _3 = reader.readInt64()
            var _4: Api.JSONValue?
            if let signature = reader.readInt32() {
                _4 = Api.parse(reader, signature: signature) as? Api.JSONValue
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.InputAppEvent.inputAppEvent(Cons_inputAppEvent(time: _1!, type: _2!, peer: _3!, data: _4!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    indirect enum InputBotApp: TypeConstructorDescription {
        public class Cons_inputBotAppID: TypeConstructorDescription {
            public var id: Int64
            public var accessHash: Int64
            public init(id: Int64, accessHash: Int64) {
                self.id = id
                self.accessHash = accessHash
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotAppID", [("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash))])
            }
        }
        public class Cons_inputBotAppShortName: TypeConstructorDescription {
            public var botId: Api.InputUser
            public var shortName: String
            public init(botId: Api.InputUser, shortName: String) {
                self.botId = botId
                self.shortName = shortName
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotAppShortName", [("botId", ConstructorParameterDescription(self.botId)), ("shortName", ConstructorParameterDescription(self.shortName))])
            }
        }
        case inputBotAppID(Cons_inputBotAppID)
        case inputBotAppShortName(Cons_inputBotAppShortName)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputBotAppID(let _data):
                if boxed {
                    buffer.appendInt32(-1457472134)
                }
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                break
            case .inputBotAppShortName(let _data):
                if boxed {
                    buffer.appendInt32(-1869872121)
                }
                _data.botId.serialize(buffer, true)
                serializeString(_data.shortName, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputBotAppID(let _data):
                return ("inputBotAppID", [("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash))])
            case .inputBotAppShortName(let _data):
                return ("inputBotAppShortName", [("botId", ConstructorParameterDescription(_data.botId)), ("shortName", ConstructorParameterDescription(_data.shortName))])
            }
        }

        public static func parse_inputBotAppID(_ reader: BufferReader) -> InputBotApp? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Int64?
            _2 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.InputBotApp.inputBotAppID(Cons_inputBotAppID(id: _1!, accessHash: _2!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotAppShortName(_ reader: BufferReader) -> InputBotApp? {
            var _1: Api.InputUser?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.InputUser
            }
            var _2: String?
            _2 = parseString(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.InputBotApp.inputBotAppShortName(Cons_inputBotAppShortName(botId: _1!, shortName: _2!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputBotInlineMessage: TypeConstructorDescription {
        public class Cons_inputBotInlineMessageGame: TypeConstructorDescription {
            public var flags: Int32
            public var replyMarkup: Api.ReplyMarkup?
            public init(flags: Int32, replyMarkup: Api.ReplyMarkup?) {
                self.flags = flags
                self.replyMarkup = replyMarkup
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineMessageGame", [("flags", ConstructorParameterDescription(self.flags)), ("replyMarkup", ConstructorParameterDescription(self.replyMarkup))])
            }
        }
        public class Cons_inputBotInlineMessageMediaAuto: TypeConstructorDescription {
            public var flags: Int32
            public var message: String
            public var entities: [Api.MessageEntity]?
            public var replyMarkup: Api.ReplyMarkup?
            public init(flags: Int32, message: String, entities: [Api.MessageEntity]?, replyMarkup: Api.ReplyMarkup?) {
                self.flags = flags
                self.message = message
                self.entities = entities
                self.replyMarkup = replyMarkup
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineMessageMediaAuto", [("flags", ConstructorParameterDescription(self.flags)), ("message", ConstructorParameterDescription(self.message)), ("entities", ConstructorParameterDescription(self.entities)), ("replyMarkup", ConstructorParameterDescription(self.replyMarkup))])
            }
        }
        public class Cons_inputBotInlineMessageMediaContact: TypeConstructorDescription {
            public var flags: Int32
            public var phoneNumber: String
            public var firstName: String
            public var lastName: String
            public var vcard: String
            public var replyMarkup: Api.ReplyMarkup?
            public init(flags: Int32, phoneNumber: String, firstName: String, lastName: String, vcard: String, replyMarkup: Api.ReplyMarkup?) {
                self.flags = flags
                self.phoneNumber = phoneNumber
                self.firstName = firstName
                self.lastName = lastName
                self.vcard = vcard
                self.replyMarkup = replyMarkup
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineMessageMediaContact", [("flags", ConstructorParameterDescription(self.flags)), ("phoneNumber", ConstructorParameterDescription(self.phoneNumber)), ("firstName", ConstructorParameterDescription(self.firstName)), ("lastName", ConstructorParameterDescription(self.lastName)), ("vcard", ConstructorParameterDescription(self.vcard)), ("replyMarkup", ConstructorParameterDescription(self.replyMarkup))])
            }
        }
        public class Cons_inputBotInlineMessageMediaGeo: TypeConstructorDescription {
            public var flags: Int32
            public var geoPoint: Api.InputGeoPoint
            public var heading: Int32?
            public var period: Int32?
            public var proximityNotificationRadius: Int32?
            public var replyMarkup: Api.ReplyMarkup?
            public init(flags: Int32, geoPoint: Api.InputGeoPoint, heading: Int32?, period: Int32?, proximityNotificationRadius: Int32?, replyMarkup: Api.ReplyMarkup?) {
                self.flags = flags
                self.geoPoint = geoPoint
                self.heading = heading
                self.period = period
                self.proximityNotificationRadius = proximityNotificationRadius
                self.replyMarkup = replyMarkup
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineMessageMediaGeo", [("flags", ConstructorParameterDescription(self.flags)), ("geoPoint", ConstructorParameterDescription(self.geoPoint)), ("heading", ConstructorParameterDescription(self.heading)), ("period", ConstructorParameterDescription(self.period)), ("proximityNotificationRadius", ConstructorParameterDescription(self.proximityNotificationRadius)), ("replyMarkup", ConstructorParameterDescription(self.replyMarkup))])
            }
        }
        public class Cons_inputBotInlineMessageMediaInvoice: TypeConstructorDescription {
            public var flags: Int32
            public var title: String
            public var description: String
            public var photo: Api.InputWebDocument?
            public var invoice: Api.Invoice
            public var payload: Buffer
            public var provider: String
            public var providerData: Api.DataJSON
            public var replyMarkup: Api.ReplyMarkup?
            public init(flags: Int32, title: String, description: String, photo: Api.InputWebDocument?, invoice: Api.Invoice, payload: Buffer, provider: String, providerData: Api.DataJSON, replyMarkup: Api.ReplyMarkup?) {
                self.flags = flags
                self.title = title
                self.description = description
                self.photo = photo
                self.invoice = invoice
                self.payload = payload
                self.provider = provider
                self.providerData = providerData
                self.replyMarkup = replyMarkup
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineMessageMediaInvoice", [("flags", ConstructorParameterDescription(self.flags)), ("title", ConstructorParameterDescription(self.title)), ("description", ConstructorParameterDescription(self.description)), ("photo", ConstructorParameterDescription(self.photo)), ("invoice", ConstructorParameterDescription(self.invoice)), ("payload", ConstructorParameterDescription(self.payload)), ("provider", ConstructorParameterDescription(self.provider)), ("providerData", ConstructorParameterDescription(self.providerData)), ("replyMarkup", ConstructorParameterDescription(self.replyMarkup))])
            }
        }
        public class Cons_inputBotInlineMessageMediaVenue: TypeConstructorDescription {
            public var flags: Int32
            public var geoPoint: Api.InputGeoPoint
            public var title: String
            public var address: String
            public var provider: String
            public var venueId: String
            public var venueType: String
            public var replyMarkup: Api.ReplyMarkup?
            public init(flags: Int32, geoPoint: Api.InputGeoPoint, title: String, address: String, provider: String, venueId: String, venueType: String, replyMarkup: Api.ReplyMarkup?) {
                self.flags = flags
                self.geoPoint = geoPoint
                self.title = title
                self.address = address
                self.provider = provider
                self.venueId = venueId
                self.venueType = venueType
                self.replyMarkup = replyMarkup
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineMessageMediaVenue", [("flags", ConstructorParameterDescription(self.flags)), ("geoPoint", ConstructorParameterDescription(self.geoPoint)), ("title", ConstructorParameterDescription(self.title)), ("address", ConstructorParameterDescription(self.address)), ("provider", ConstructorParameterDescription(self.provider)), ("venueId", ConstructorParameterDescription(self.venueId)), ("venueType", ConstructorParameterDescription(self.venueType)), ("replyMarkup", ConstructorParameterDescription(self.replyMarkup))])
            }
        }
        public class Cons_inputBotInlineMessageMediaWebPage: TypeConstructorDescription {
            public var flags: Int32
            public var message: String
            public var entities: [Api.MessageEntity]?
            public var url: String
            public var replyMarkup: Api.ReplyMarkup?
            public init(flags: Int32, message: String, entities: [Api.MessageEntity]?, url: String, replyMarkup: Api.ReplyMarkup?) {
                self.flags = flags
                self.message = message
                self.entities = entities
                self.url = url
                self.replyMarkup = replyMarkup
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineMessageMediaWebPage", [("flags", ConstructorParameterDescription(self.flags)), ("message", ConstructorParameterDescription(self.message)), ("entities", ConstructorParameterDescription(self.entities)), ("url", ConstructorParameterDescription(self.url)), ("replyMarkup", ConstructorParameterDescription(self.replyMarkup))])
            }
        }
        public class Cons_inputBotInlineMessageRichMessage: TypeConstructorDescription {
            public var flags: Int32
            public var replyMarkup: Api.ReplyMarkup?
            public var richMessage: Api.InputRichMessage
            public init(flags: Int32, replyMarkup: Api.ReplyMarkup?, richMessage: Api.InputRichMessage) {
                self.flags = flags
                self.replyMarkup = replyMarkup
                self.richMessage = richMessage
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineMessageRichMessage", [("flags", ConstructorParameterDescription(self.flags)), ("replyMarkup", ConstructorParameterDescription(self.replyMarkup)), ("richMessage", ConstructorParameterDescription(self.richMessage))])
            }
        }
        public class Cons_inputBotInlineMessageText: TypeConstructorDescription {
            public var flags: Int32
            public var message: String
            public var entities: [Api.MessageEntity]?
            public var replyMarkup: Api.ReplyMarkup?
            public init(flags: Int32, message: String, entities: [Api.MessageEntity]?, replyMarkup: Api.ReplyMarkup?) {
                self.flags = flags
                self.message = message
                self.entities = entities
                self.replyMarkup = replyMarkup
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineMessageText", [("flags", ConstructorParameterDescription(self.flags)), ("message", ConstructorParameterDescription(self.message)), ("entities", ConstructorParameterDescription(self.entities)), ("replyMarkup", ConstructorParameterDescription(self.replyMarkup))])
            }
        }
        case inputBotInlineMessageGame(Cons_inputBotInlineMessageGame)
        case inputBotInlineMessageMediaAuto(Cons_inputBotInlineMessageMediaAuto)
        case inputBotInlineMessageMediaContact(Cons_inputBotInlineMessageMediaContact)
        case inputBotInlineMessageMediaGeo(Cons_inputBotInlineMessageMediaGeo)
        case inputBotInlineMessageMediaInvoice(Cons_inputBotInlineMessageMediaInvoice)
        case inputBotInlineMessageMediaVenue(Cons_inputBotInlineMessageMediaVenue)
        case inputBotInlineMessageMediaWebPage(Cons_inputBotInlineMessageMediaWebPage)
        case inputBotInlineMessageRichMessage(Cons_inputBotInlineMessageRichMessage)
        case inputBotInlineMessageText(Cons_inputBotInlineMessageText)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputBotInlineMessageGame(let _data):
                if boxed {
                    buffer.appendInt32(1262639204)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.replyMarkup!.serialize(buffer, true)
                }
                break
            case .inputBotInlineMessageMediaAuto(let _data):
                if boxed {
                    buffer.appendInt32(864077702)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeString(_data.message, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.entities!.count))
                    for item in _data.entities! {
                        item.serialize(buffer, true)
                    }
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.replyMarkup!.serialize(buffer, true)
                }
                break
            case .inputBotInlineMessageMediaContact(let _data):
                if boxed {
                    buffer.appendInt32(-1494368259)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeString(_data.phoneNumber, buffer: buffer, boxed: false)
                serializeString(_data.firstName, buffer: buffer, boxed: false)
                serializeString(_data.lastName, buffer: buffer, boxed: false)
                serializeString(_data.vcard, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.replyMarkup!.serialize(buffer, true)
                }
                break
            case .inputBotInlineMessageMediaGeo(let _data):
                if boxed {
                    buffer.appendInt32(-1768777083)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                _data.geoPoint.serialize(buffer, true)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    serializeInt32(_data.heading!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeInt32(_data.period!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 3) != 0 {
                    serializeInt32(_data.proximityNotificationRadius!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.replyMarkup!.serialize(buffer, true)
                }
                break
            case .inputBotInlineMessageMediaInvoice(let _data):
                if boxed {
                    buffer.appendInt32(-672693723)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeString(_data.title, buffer: buffer, boxed: false)
                serializeString(_data.description, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    _data.photo!.serialize(buffer, true)
                }
                _data.invoice.serialize(buffer, true)
                serializeBytes(_data.payload, buffer: buffer, boxed: false)
                serializeString(_data.provider, buffer: buffer, boxed: false)
                _data.providerData.serialize(buffer, true)
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.replyMarkup!.serialize(buffer, true)
                }
                break
            case .inputBotInlineMessageMediaVenue(let _data):
                if boxed {
                    buffer.appendInt32(1098628881)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                _data.geoPoint.serialize(buffer, true)
                serializeString(_data.title, buffer: buffer, boxed: false)
                serializeString(_data.address, buffer: buffer, boxed: false)
                serializeString(_data.provider, buffer: buffer, boxed: false)
                serializeString(_data.venueId, buffer: buffer, boxed: false)
                serializeString(_data.venueType, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.replyMarkup!.serialize(buffer, true)
                }
                break
            case .inputBotInlineMessageMediaWebPage(let _data):
                if boxed {
                    buffer.appendInt32(-1109605104)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeString(_data.message, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.entities!.count))
                    for item in _data.entities! {
                        item.serialize(buffer, true)
                    }
                }
                serializeString(_data.url, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.replyMarkup!.serialize(buffer, true)
                }
                break
            case .inputBotInlineMessageRichMessage(let _data):
                if boxed {
                    buffer.appendInt32(-1271007892)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.replyMarkup!.serialize(buffer, true)
                }
                _data.richMessage.serialize(buffer, true)
                break
            case .inputBotInlineMessageText(let _data):
                if boxed {
                    buffer.appendInt32(1036876423)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeString(_data.message, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.entities!.count))
                    for item in _data.entities! {
                        item.serialize(buffer, true)
                    }
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    _data.replyMarkup!.serialize(buffer, true)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputBotInlineMessageGame(let _data):
                return ("inputBotInlineMessageGame", [("flags", ConstructorParameterDescription(_data.flags)), ("replyMarkup", ConstructorParameterDescription(_data.replyMarkup))])
            case .inputBotInlineMessageMediaAuto(let _data):
                return ("inputBotInlineMessageMediaAuto", [("flags", ConstructorParameterDescription(_data.flags)), ("message", ConstructorParameterDescription(_data.message)), ("entities", ConstructorParameterDescription(_data.entities)), ("replyMarkup", ConstructorParameterDescription(_data.replyMarkup))])
            case .inputBotInlineMessageMediaContact(let _data):
                return ("inputBotInlineMessageMediaContact", [("flags", ConstructorParameterDescription(_data.flags)), ("phoneNumber", ConstructorParameterDescription(_data.phoneNumber)), ("firstName", ConstructorParameterDescription(_data.firstName)), ("lastName", ConstructorParameterDescription(_data.lastName)), ("vcard", ConstructorParameterDescription(_data.vcard)), ("replyMarkup", ConstructorParameterDescription(_data.replyMarkup))])
            case .inputBotInlineMessageMediaGeo(let _data):
                return ("inputBotInlineMessageMediaGeo", [("flags", ConstructorParameterDescription(_data.flags)), ("geoPoint", ConstructorParameterDescription(_data.geoPoint)), ("heading", ConstructorParameterDescription(_data.heading)), ("period", ConstructorParameterDescription(_data.period)), ("proximityNotificationRadius", ConstructorParameterDescription(_data.proximityNotificationRadius)), ("replyMarkup", ConstructorParameterDescription(_data.replyMarkup))])
            case .inputBotInlineMessageMediaInvoice(let _data):
                return ("inputBotInlineMessageMediaInvoice", [("flags", ConstructorParameterDescription(_data.flags)), ("title", ConstructorParameterDescription(_data.title)), ("description", ConstructorParameterDescription(_data.description)), ("photo", ConstructorParameterDescription(_data.photo)), ("invoice", ConstructorParameterDescription(_data.invoice)), ("payload", ConstructorParameterDescription(_data.payload)), ("provider", ConstructorParameterDescription(_data.provider)), ("providerData", ConstructorParameterDescription(_data.providerData)), ("replyMarkup", ConstructorParameterDescription(_data.replyMarkup))])
            case .inputBotInlineMessageMediaVenue(let _data):
                return ("inputBotInlineMessageMediaVenue", [("flags", ConstructorParameterDescription(_data.flags)), ("geoPoint", ConstructorParameterDescription(_data.geoPoint)), ("title", ConstructorParameterDescription(_data.title)), ("address", ConstructorParameterDescription(_data.address)), ("provider", ConstructorParameterDescription(_data.provider)), ("venueId", ConstructorParameterDescription(_data.venueId)), ("venueType", ConstructorParameterDescription(_data.venueType)), ("replyMarkup", ConstructorParameterDescription(_data.replyMarkup))])
            case .inputBotInlineMessageMediaWebPage(let _data):
                return ("inputBotInlineMessageMediaWebPage", [("flags", ConstructorParameterDescription(_data.flags)), ("message", ConstructorParameterDescription(_data.message)), ("entities", ConstructorParameterDescription(_data.entities)), ("url", ConstructorParameterDescription(_data.url)), ("replyMarkup", ConstructorParameterDescription(_data.replyMarkup))])
            case .inputBotInlineMessageRichMessage(let _data):
                return ("inputBotInlineMessageRichMessage", [("flags", ConstructorParameterDescription(_data.flags)), ("replyMarkup", ConstructorParameterDescription(_data.replyMarkup)), ("richMessage", ConstructorParameterDescription(_data.richMessage))])
            case .inputBotInlineMessageText(let _data):
                return ("inputBotInlineMessageText", [("flags", ConstructorParameterDescription(_data.flags)), ("message", ConstructorParameterDescription(_data.message)), ("entities", ConstructorParameterDescription(_data.entities)), ("replyMarkup", ConstructorParameterDescription(_data.replyMarkup))])
            }
        }

        public static func parse_inputBotInlineMessageGame(_ reader: BufferReader) -> InputBotInlineMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.ReplyMarkup?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _2 = Api.parse(reader, signature: signature) as? Api.ReplyMarkup
                }
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _2 != nil
            if _c1 && _c2 {
                return Api.InputBotInlineMessage.inputBotInlineMessageGame(Cons_inputBotInlineMessageGame(flags: _1!, replyMarkup: _2))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineMessageMediaAuto(_ reader: BufferReader) -> InputBotInlineMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            _2 = parseString(reader)
            var _3: [Api.MessageEntity]?
            if Int(_1 ?? 0) & Int(1 << 1) != 0 {
                if let _ = reader.readInt32() {
                    _3 = Api.parseVector(reader, elementSignature: 0, elementType: Api.MessageEntity.self)
                }
            }
            var _4: Api.ReplyMarkup?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _4 = Api.parse(reader, signature: signature) as? Api.ReplyMarkup
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1 ?? 0) & Int(1 << 1) == 0) || _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.InputBotInlineMessage.inputBotInlineMessageMediaAuto(Cons_inputBotInlineMessageMediaAuto(flags: _1!, message: _2!, entities: _3, replyMarkup: _4))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineMessageMediaContact(_ reader: BufferReader) -> InputBotInlineMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            _2 = parseString(reader)
            var _3: String?
            _3 = parseString(reader)
            var _4: String?
            _4 = parseString(reader)
            var _5: String?
            _5 = parseString(reader)
            var _6: Api.ReplyMarkup?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _6 = Api.parse(reader, signature: signature) as? Api.ReplyMarkup
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _6 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 {
                return Api.InputBotInlineMessage.inputBotInlineMessageMediaContact(Cons_inputBotInlineMessageMediaContact(flags: _1!, phoneNumber: _2!, firstName: _3!, lastName: _4!, vcard: _5!, replyMarkup: _6))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineMessageMediaGeo(_ reader: BufferReader) -> InputBotInlineMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.InputGeoPoint?
            if let signature = reader.readInt32() {
                _2 = Api.parse(reader, signature: signature) as? Api.InputGeoPoint
            }
            var _3: Int32?
            if Int(_1 ?? 0) & Int(1 << 0) != 0 {
                _3 = reader.readInt32()
            }
            var _4: Int32?
            if Int(_1 ?? 0) & Int(1 << 1) != 0 {
                _4 = reader.readInt32()
            }
            var _5: Int32?
            if Int(_1 ?? 0) & Int(1 << 3) != 0 {
                _5 = reader.readInt32()
            }
            var _6: Api.ReplyMarkup?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _6 = Api.parse(reader, signature: signature) as? Api.ReplyMarkup
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1 ?? 0) & Int(1 << 0) == 0) || _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 1) == 0) || _4 != nil
            let _c5 = (Int(_1 ?? 0) & Int(1 << 3) == 0) || _5 != nil
            let _c6 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _6 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 {
                return Api.InputBotInlineMessage.inputBotInlineMessageMediaGeo(Cons_inputBotInlineMessageMediaGeo(flags: _1!, geoPoint: _2!, heading: _3, period: _4, proximityNotificationRadius: _5, replyMarkup: _6))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineMessageMediaInvoice(_ reader: BufferReader) -> InputBotInlineMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            _2 = parseString(reader)
            var _3: String?
            _3 = parseString(reader)
            var _4: Api.InputWebDocument?
            if Int(_1 ?? 0) & Int(1 << 0) != 0 {
                if let signature = reader.readInt32() {
                    _4 = Api.parse(reader, signature: signature) as? Api.InputWebDocument
                }
            }
            var _5: Api.Invoice?
            if let signature = reader.readInt32() {
                _5 = Api.parse(reader, signature: signature) as? Api.Invoice
            }
            var _6: Buffer?
            _6 = parseBytes(reader)
            var _7: String?
            _7 = parseString(reader)
            var _8: Api.DataJSON?
            if let signature = reader.readInt32() {
                _8 = Api.parse(reader, signature: signature) as? Api.DataJSON
            }
            var _9: Api.ReplyMarkup?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _9 = Api.parse(reader, signature: signature) as? Api.ReplyMarkup
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 0) == 0) || _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            let _c7 = _7 != nil
            let _c8 = _8 != nil
            let _c9 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _9 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 && _c9 {
                return Api.InputBotInlineMessage.inputBotInlineMessageMediaInvoice(Cons_inputBotInlineMessageMediaInvoice(flags: _1!, title: _2!, description: _3!, photo: _4, invoice: _5!, payload: _6!, provider: _7!, providerData: _8!, replyMarkup: _9))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineMessageMediaVenue(_ reader: BufferReader) -> InputBotInlineMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.InputGeoPoint?
            if let signature = reader.readInt32() {
                _2 = Api.parse(reader, signature: signature) as? Api.InputGeoPoint
            }
            var _3: String?
            _3 = parseString(reader)
            var _4: String?
            _4 = parseString(reader)
            var _5: String?
            _5 = parseString(reader)
            var _6: String?
            _6 = parseString(reader)
            var _7: String?
            _7 = parseString(reader)
            var _8: Api.ReplyMarkup?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _8 = Api.parse(reader, signature: signature) as? Api.ReplyMarkup
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            let _c7 = _7 != nil
            let _c8 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _8 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 {
                return Api.InputBotInlineMessage.inputBotInlineMessageMediaVenue(Cons_inputBotInlineMessageMediaVenue(flags: _1!, geoPoint: _2!, title: _3!, address: _4!, provider: _5!, venueId: _6!, venueType: _7!, replyMarkup: _8))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineMessageMediaWebPage(_ reader: BufferReader) -> InputBotInlineMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            _2 = parseString(reader)
            var _3: [Api.MessageEntity]?
            if Int(_1 ?? 0) & Int(1 << 1) != 0 {
                if let _ = reader.readInt32() {
                    _3 = Api.parseVector(reader, elementSignature: 0, elementType: Api.MessageEntity.self)
                }
            }
            var _4: String?
            _4 = parseString(reader)
            var _5: Api.ReplyMarkup?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _5 = Api.parse(reader, signature: signature) as? Api.ReplyMarkup
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1 ?? 0) & Int(1 << 1) == 0) || _3 != nil
            let _c4 = _4 != nil
            let _c5 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _5 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 {
                return Api.InputBotInlineMessage.inputBotInlineMessageMediaWebPage(Cons_inputBotInlineMessageMediaWebPage(flags: _1!, message: _2!, entities: _3, url: _4!, replyMarkup: _5))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineMessageRichMessage(_ reader: BufferReader) -> InputBotInlineMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.ReplyMarkup?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _2 = Api.parse(reader, signature: signature) as? Api.ReplyMarkup
                }
            }
            var _3: Api.InputRichMessage?
            if let signature = reader.readInt32() {
                _3 = Api.parse(reader, signature: signature) as? Api.InputRichMessage
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.InputBotInlineMessage.inputBotInlineMessageRichMessage(Cons_inputBotInlineMessageRichMessage(flags: _1!, replyMarkup: _2, richMessage: _3!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineMessageText(_ reader: BufferReader) -> InputBotInlineMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            _2 = parseString(reader)
            var _3: [Api.MessageEntity]?
            if Int(_1 ?? 0) & Int(1 << 1) != 0 {
                if let _ = reader.readInt32() {
                    _3 = Api.parseVector(reader, elementSignature: 0, elementType: Api.MessageEntity.self)
                }
            }
            var _4: Api.ReplyMarkup?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                if let signature = reader.readInt32() {
                    _4 = Api.parse(reader, signature: signature) as? Api.ReplyMarkup
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1 ?? 0) & Int(1 << 1) == 0) || _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.InputBotInlineMessage.inputBotInlineMessageText(Cons_inputBotInlineMessageText(flags: _1!, message: _2!, entities: _3, replyMarkup: _4))
            }
            else {
                return nil
            }
        }
    }
}
