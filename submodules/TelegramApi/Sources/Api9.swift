public extension Api {
    enum InputBotInlineMessageID: TypeConstructorDescription {
        public class Cons_inputBotInlineMessageID: TypeConstructorDescription {
            public var dcId: Int32
            public var id: Int64
            public var accessHash: Int64
            public init(dcId: Int32, id: Int64, accessHash: Int64) {
                self.dcId = dcId
                self.id = id
                self.accessHash = accessHash
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineMessageID", [("dcId", ConstructorParameterDescription(self.dcId)), ("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash))])
            }
        }
        public class Cons_inputBotInlineMessageID64: TypeConstructorDescription {
            public var dcId: Int32
            public var ownerId: Int64
            public var id: Int32
            public var accessHash: Int64
            public init(dcId: Int32, ownerId: Int64, id: Int32, accessHash: Int64) {
                self.dcId = dcId
                self.ownerId = ownerId
                self.id = id
                self.accessHash = accessHash
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineMessageID64", [("dcId", ConstructorParameterDescription(self.dcId)), ("ownerId", ConstructorParameterDescription(self.ownerId)), ("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash))])
            }
        }
        case inputBotInlineMessageID(Cons_inputBotInlineMessageID)
        case inputBotInlineMessageID64(Cons_inputBotInlineMessageID64)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputBotInlineMessageID(let _data):
                if boxed {
                    buffer.appendInt32(-1995686519)
                }
                serializeInt32(_data.dcId, buffer: buffer, boxed: false)
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                break
            case .inputBotInlineMessageID64(let _data):
                if boxed {
                    buffer.appendInt32(-1227287081)
                }
                serializeInt32(_data.dcId, buffer: buffer, boxed: false)
                serializeInt64(_data.ownerId, buffer: buffer, boxed: false)
                serializeInt32(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputBotInlineMessageID(let _data):
                return ("inputBotInlineMessageID", [("dcId", ConstructorParameterDescription(_data.dcId)), ("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash))])
            case .inputBotInlineMessageID64(let _data):
                return ("inputBotInlineMessageID64", [("dcId", ConstructorParameterDescription(_data.dcId)), ("ownerId", ConstructorParameterDescription(_data.ownerId)), ("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash))])
            }
        }

        public static func parse_inputBotInlineMessageID(_ reader: BufferReader) -> InputBotInlineMessageID? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Int64?
            _3 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.InputBotInlineMessageID.inputBotInlineMessageID(Cons_inputBotInlineMessageID(dcId: _1!, id: _2!, accessHash: _3!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineMessageID64(_ reader: BufferReader) -> InputBotInlineMessageID? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: Int64?
            _4 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.InputBotInlineMessageID.inputBotInlineMessageID64(Cons_inputBotInlineMessageID64(dcId: _1!, ownerId: _2!, id: _3!, accessHash: _4!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputBotInlineResult: TypeConstructorDescription {
        public class Cons_inputBotInlineResult: TypeConstructorDescription {
            public var flags: Int32
            public var id: String
            public var type: String
            public var title: String?
            public var description: String?
            public var url: String?
            public var thumb: Api.InputWebDocument?
            public var content: Api.InputWebDocument?
            public var sendMessage: Api.InputBotInlineMessage
            public init(flags: Int32, id: String, type: String, title: String?, description: String?, url: String?, thumb: Api.InputWebDocument?, content: Api.InputWebDocument?, sendMessage: Api.InputBotInlineMessage) {
                self.flags = flags
                self.id = id
                self.type = type
                self.title = title
                self.description = description
                self.url = url
                self.thumb = thumb
                self.content = content
                self.sendMessage = sendMessage
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineResult", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("type", ConstructorParameterDescription(self.type)), ("title", ConstructorParameterDescription(self.title)), ("description", ConstructorParameterDescription(self.description)), ("url", ConstructorParameterDescription(self.url)), ("thumb", ConstructorParameterDescription(self.thumb)), ("content", ConstructorParameterDescription(self.content)), ("sendMessage", ConstructorParameterDescription(self.sendMessage))])
            }
        }
        public class Cons_inputBotInlineResultDocument: TypeConstructorDescription {
            public var flags: Int32
            public var id: String
            public var type: String
            public var title: String?
            public var description: String?
            public var document: Api.InputDocument
            public var sendMessage: Api.InputBotInlineMessage
            public init(flags: Int32, id: String, type: String, title: String?, description: String?, document: Api.InputDocument, sendMessage: Api.InputBotInlineMessage) {
                self.flags = flags
                self.id = id
                self.type = type
                self.title = title
                self.description = description
                self.document = document
                self.sendMessage = sendMessage
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineResultDocument", [("flags", ConstructorParameterDescription(self.flags)), ("id", ConstructorParameterDescription(self.id)), ("type", ConstructorParameterDescription(self.type)), ("title", ConstructorParameterDescription(self.title)), ("description", ConstructorParameterDescription(self.description)), ("document", ConstructorParameterDescription(self.document)), ("sendMessage", ConstructorParameterDescription(self.sendMessage))])
            }
        }
        public class Cons_inputBotInlineResultGame: TypeConstructorDescription {
            public var id: String
            public var shortName: String
            public var sendMessage: Api.InputBotInlineMessage
            public init(id: String, shortName: String, sendMessage: Api.InputBotInlineMessage) {
                self.id = id
                self.shortName = shortName
                self.sendMessage = sendMessage
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineResultGame", [("id", ConstructorParameterDescription(self.id)), ("shortName", ConstructorParameterDescription(self.shortName)), ("sendMessage", ConstructorParameterDescription(self.sendMessage))])
            }
        }
        public class Cons_inputBotInlineResultPhoto: TypeConstructorDescription {
            public var id: String
            public var type: String
            public var photo: Api.InputPhoto
            public var sendMessage: Api.InputBotInlineMessage
            public init(id: String, type: String, photo: Api.InputPhoto, sendMessage: Api.InputBotInlineMessage) {
                self.id = id
                self.type = type
                self.photo = photo
                self.sendMessage = sendMessage
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBotInlineResultPhoto", [("id", ConstructorParameterDescription(self.id)), ("type", ConstructorParameterDescription(self.type)), ("photo", ConstructorParameterDescription(self.photo)), ("sendMessage", ConstructorParameterDescription(self.sendMessage))])
            }
        }
        case inputBotInlineResult(Cons_inputBotInlineResult)
        case inputBotInlineResultDocument(Cons_inputBotInlineResultDocument)
        case inputBotInlineResultGame(Cons_inputBotInlineResultGame)
        case inputBotInlineResultPhoto(Cons_inputBotInlineResultPhoto)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputBotInlineResult(let _data):
                if boxed {
                    buffer.appendInt32(-2000710887)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeString(_data.id, buffer: buffer, boxed: false)
                serializeString(_data.type, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeString(_data.title!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    serializeString(_data.description!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 3) != 0 {
                    serializeString(_data.url!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 4) != 0 {
                    _data.thumb!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 5) != 0 {
                    _data.content!.serialize(buffer, true)
                }
                _data.sendMessage.serialize(buffer, true)
                break
            case .inputBotInlineResultDocument(let _data):
                if boxed {
                    buffer.appendInt32(-459324)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeString(_data.id, buffer: buffer, boxed: false)
                serializeString(_data.type, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeString(_data.title!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    serializeString(_data.description!, buffer: buffer, boxed: false)
                }
                _data.document.serialize(buffer, true)
                _data.sendMessage.serialize(buffer, true)
                break
            case .inputBotInlineResultGame(let _data):
                if boxed {
                    buffer.appendInt32(1336154098)
                }
                serializeString(_data.id, buffer: buffer, boxed: false)
                serializeString(_data.shortName, buffer: buffer, boxed: false)
                _data.sendMessage.serialize(buffer, true)
                break
            case .inputBotInlineResultPhoto(let _data):
                if boxed {
                    buffer.appendInt32(-1462213465)
                }
                serializeString(_data.id, buffer: buffer, boxed: false)
                serializeString(_data.type, buffer: buffer, boxed: false)
                _data.photo.serialize(buffer, true)
                _data.sendMessage.serialize(buffer, true)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputBotInlineResult(let _data):
                return ("inputBotInlineResult", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("type", ConstructorParameterDescription(_data.type)), ("title", ConstructorParameterDescription(_data.title)), ("description", ConstructorParameterDescription(_data.description)), ("url", ConstructorParameterDescription(_data.url)), ("thumb", ConstructorParameterDescription(_data.thumb)), ("content", ConstructorParameterDescription(_data.content)), ("sendMessage", ConstructorParameterDescription(_data.sendMessage))])
            case .inputBotInlineResultDocument(let _data):
                return ("inputBotInlineResultDocument", [("flags", ConstructorParameterDescription(_data.flags)), ("id", ConstructorParameterDescription(_data.id)), ("type", ConstructorParameterDescription(_data.type)), ("title", ConstructorParameterDescription(_data.title)), ("description", ConstructorParameterDescription(_data.description)), ("document", ConstructorParameterDescription(_data.document)), ("sendMessage", ConstructorParameterDescription(_data.sendMessage))])
            case .inputBotInlineResultGame(let _data):
                return ("inputBotInlineResultGame", [("id", ConstructorParameterDescription(_data.id)), ("shortName", ConstructorParameterDescription(_data.shortName)), ("sendMessage", ConstructorParameterDescription(_data.sendMessage))])
            case .inputBotInlineResultPhoto(let _data):
                return ("inputBotInlineResultPhoto", [("id", ConstructorParameterDescription(_data.id)), ("type", ConstructorParameterDescription(_data.type)), ("photo", ConstructorParameterDescription(_data.photo)), ("sendMessage", ConstructorParameterDescription(_data.sendMessage))])
            }
        }

        public static func parse_inputBotInlineResult(_ reader: BufferReader) -> InputBotInlineResult? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            _2 = parseString(reader)
            var _3: String?
            _3 = parseString(reader)
            var _4: String?
            if Int(_1 ?? 0) & Int(1 << 1) != 0 {
                _4 = parseString(reader)
            }
            var _5: String?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                _5 = parseString(reader)
            }
            var _6: String?
            if Int(_1 ?? 0) & Int(1 << 3) != 0 {
                _6 = parseString(reader)
            }
            var _7: Api.InputWebDocument?
            if Int(_1 ?? 0) & Int(1 << 4) != 0 {
                if let signature = reader.readInt32() {
                    _7 = Api.parse(reader, signature: signature) as? Api.InputWebDocument
                }
            }
            var _8: Api.InputWebDocument?
            if Int(_1 ?? 0) & Int(1 << 5) != 0 {
                if let signature = reader.readInt32() {
                    _8 = Api.parse(reader, signature: signature) as? Api.InputWebDocument
                }
            }
            var _9: Api.InputBotInlineMessage?
            if let signature = reader.readInt32() {
                _9 = Api.parse(reader, signature: signature) as? Api.InputBotInlineMessage
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 1) == 0) || _4 != nil
            let _c5 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _5 != nil
            let _c6 = (Int(_1 ?? 0) & Int(1 << 3) == 0) || _6 != nil
            let _c7 = (Int(_1 ?? 0) & Int(1 << 4) == 0) || _7 != nil
            let _c8 = (Int(_1 ?? 0) & Int(1 << 5) == 0) || _8 != nil
            let _c9 = _9 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 && _c8 && _c9 {
                return Api.InputBotInlineResult.inputBotInlineResult(Cons_inputBotInlineResult(flags: _1!, id: _2!, type: _3!, title: _4, description: _5, url: _6, thumb: _7, content: _8, sendMessage: _9!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineResultDocument(_ reader: BufferReader) -> InputBotInlineResult? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            _2 = parseString(reader)
            var _3: String?
            _3 = parseString(reader)
            var _4: String?
            if Int(_1 ?? 0) & Int(1 << 1) != 0 {
                _4 = parseString(reader)
            }
            var _5: String?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                _5 = parseString(reader)
            }
            var _6: Api.InputDocument?
            if let signature = reader.readInt32() {
                _6 = Api.parse(reader, signature: signature) as? Api.InputDocument
            }
            var _7: Api.InputBotInlineMessage?
            if let signature = reader.readInt32() {
                _7 = Api.parse(reader, signature: signature) as? Api.InputBotInlineMessage
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 1) == 0) || _4 != nil
            let _c5 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _5 != nil
            let _c6 = _6 != nil
            let _c7 = _7 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 {
                return Api.InputBotInlineResult.inputBotInlineResultDocument(Cons_inputBotInlineResultDocument(flags: _1!, id: _2!, type: _3!, title: _4, description: _5, document: _6!, sendMessage: _7!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineResultGame(_ reader: BufferReader) -> InputBotInlineResult? {
            var _1: String?
            _1 = parseString(reader)
            var _2: String?
            _2 = parseString(reader)
            var _3: Api.InputBotInlineMessage?
            if let signature = reader.readInt32() {
                _3 = Api.parse(reader, signature: signature) as? Api.InputBotInlineMessage
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.InputBotInlineResult.inputBotInlineResultGame(Cons_inputBotInlineResultGame(id: _1!, shortName: _2!, sendMessage: _3!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputBotInlineResultPhoto(_ reader: BufferReader) -> InputBotInlineResult? {
            var _1: String?
            _1 = parseString(reader)
            var _2: String?
            _2 = parseString(reader)
            var _3: Api.InputPhoto?
            if let signature = reader.readInt32() {
                _3 = Api.parse(reader, signature: signature) as? Api.InputPhoto
            }
            var _4: Api.InputBotInlineMessage?
            if let signature = reader.readInt32() {
                _4 = Api.parse(reader, signature: signature) as? Api.InputBotInlineMessage
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.InputBotInlineResult.inputBotInlineResultPhoto(Cons_inputBotInlineResultPhoto(id: _1!, type: _2!, photo: _3!, sendMessage: _4!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputBusinessAwayMessage: TypeConstructorDescription {
        public class Cons_inputBusinessAwayMessage: TypeConstructorDescription {
            public var flags: Int32
            public var shortcutId: Int32
            public var schedule: Api.BusinessAwayMessageSchedule
            public var recipients: Api.InputBusinessRecipients
            public init(flags: Int32, shortcutId: Int32, schedule: Api.BusinessAwayMessageSchedule, recipients: Api.InputBusinessRecipients) {
                self.flags = flags
                self.shortcutId = shortcutId
                self.schedule = schedule
                self.recipients = recipients
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBusinessAwayMessage", [("flags", ConstructorParameterDescription(self.flags)), ("shortcutId", ConstructorParameterDescription(self.shortcutId)), ("schedule", ConstructorParameterDescription(self.schedule)), ("recipients", ConstructorParameterDescription(self.recipients))])
            }
        }
        case inputBusinessAwayMessage(Cons_inputBusinessAwayMessage)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputBusinessAwayMessage(let _data):
                if boxed {
                    buffer.appendInt32(-2094959136)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt32(_data.shortcutId, buffer: buffer, boxed: false)
                _data.schedule.serialize(buffer, true)
                _data.recipients.serialize(buffer, true)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputBusinessAwayMessage(let _data):
                return ("inputBusinessAwayMessage", [("flags", ConstructorParameterDescription(_data.flags)), ("shortcutId", ConstructorParameterDescription(_data.shortcutId)), ("schedule", ConstructorParameterDescription(_data.schedule)), ("recipients", ConstructorParameterDescription(_data.recipients))])
            }
        }

        public static func parse_inputBusinessAwayMessage(_ reader: BufferReader) -> InputBusinessAwayMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Api.BusinessAwayMessageSchedule?
            if let signature = reader.readInt32() {
                _3 = Api.parse(reader, signature: signature) as? Api.BusinessAwayMessageSchedule
            }
            var _4: Api.InputBusinessRecipients?
            if let signature = reader.readInt32() {
                _4 = Api.parse(reader, signature: signature) as? Api.InputBusinessRecipients
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.InputBusinessAwayMessage.inputBusinessAwayMessage(Cons_inputBusinessAwayMessage(flags: _1!, shortcutId: _2!, schedule: _3!, recipients: _4!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputBusinessBotRecipients: TypeConstructorDescription {
        public class Cons_inputBusinessBotRecipients: TypeConstructorDescription {
            public var flags: Int32
            public var users: [Api.InputUser]?
            public var excludeUsers: [Api.InputUser]?
            public init(flags: Int32, users: [Api.InputUser]?, excludeUsers: [Api.InputUser]?) {
                self.flags = flags
                self.users = users
                self.excludeUsers = excludeUsers
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBusinessBotRecipients", [("flags", ConstructorParameterDescription(self.flags)), ("users", ConstructorParameterDescription(self.users)), ("excludeUsers", ConstructorParameterDescription(self.excludeUsers))])
            }
        }
        case inputBusinessBotRecipients(Cons_inputBusinessBotRecipients)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputBusinessBotRecipients(let _data):
                if boxed {
                    buffer.appendInt32(-991587810)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 4) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.users!.count))
                    for item in _data.users! {
                        item.serialize(buffer, true)
                    }
                }
                if Int(_data.flags) & Int(1 << 6) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.excludeUsers!.count))
                    for item in _data.excludeUsers! {
                        item.serialize(buffer, true)
                    }
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputBusinessBotRecipients(let _data):
                return ("inputBusinessBotRecipients", [("flags", ConstructorParameterDescription(_data.flags)), ("users", ConstructorParameterDescription(_data.users)), ("excludeUsers", ConstructorParameterDescription(_data.excludeUsers))])
            }
        }

        public static func parse_inputBusinessBotRecipients(_ reader: BufferReader) -> InputBusinessBotRecipients? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: [Api.InputUser]?
            if Int(_1 ?? 0) & Int(1 << 4) != 0 {
                if let _ = reader.readInt32() {
                    _2 = Api.parseVector(reader, elementSignature: 0, elementType: Api.InputUser.self)
                }
            }
            var _3: [Api.InputUser]?
            if Int(_1 ?? 0) & Int(1 << 6) != 0 {
                if let _ = reader.readInt32() {
                    _3 = Api.parseVector(reader, elementSignature: 0, elementType: Api.InputUser.self)
                }
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1 ?? 0) & Int(1 << 4) == 0) || _2 != nil
            let _c3 = (Int(_1 ?? 0) & Int(1 << 6) == 0) || _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.InputBusinessBotRecipients.inputBusinessBotRecipients(Cons_inputBusinessBotRecipients(flags: _1!, users: _2, excludeUsers: _3))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputBusinessChatLink: TypeConstructorDescription {
        public class Cons_inputBusinessChatLink: TypeConstructorDescription {
            public var flags: Int32
            public var message: String
            public var entities: [Api.MessageEntity]?
            public var title: String?
            public init(flags: Int32, message: String, entities: [Api.MessageEntity]?, title: String?) {
                self.flags = flags
                self.message = message
                self.entities = entities
                self.title = title
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBusinessChatLink", [("flags", ConstructorParameterDescription(self.flags)), ("message", ConstructorParameterDescription(self.message)), ("entities", ConstructorParameterDescription(self.entities)), ("title", ConstructorParameterDescription(self.title))])
            }
        }
        case inputBusinessChatLink(Cons_inputBusinessChatLink)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputBusinessChatLink(let _data):
                if boxed {
                    buffer.appendInt32(292003751)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeString(_data.message, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.entities!.count))
                    for item in _data.entities! {
                        item.serialize(buffer, true)
                    }
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    serializeString(_data.title!, buffer: buffer, boxed: false)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputBusinessChatLink(let _data):
                return ("inputBusinessChatLink", [("flags", ConstructorParameterDescription(_data.flags)), ("message", ConstructorParameterDescription(_data.message)), ("entities", ConstructorParameterDescription(_data.entities)), ("title", ConstructorParameterDescription(_data.title))])
            }
        }

        public static func parse_inputBusinessChatLink(_ reader: BufferReader) -> InputBusinessChatLink? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            _2 = parseString(reader)
            var _3: [Api.MessageEntity]?
            if Int(_1 ?? 0) & Int(1 << 0) != 0 {
                if let _ = reader.readInt32() {
                    _3 = Api.parseVector(reader, elementSignature: 0, elementType: Api.MessageEntity.self)
                }
            }
            var _4: String?
            if Int(_1 ?? 0) & Int(1 << 1) != 0 {
                _4 = parseString(reader)
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = (Int(_1 ?? 0) & Int(1 << 0) == 0) || _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 1) == 0) || _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.InputBusinessChatLink.inputBusinessChatLink(Cons_inputBusinessChatLink(flags: _1!, message: _2!, entities: _3, title: _4))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputBusinessGreetingMessage: TypeConstructorDescription {
        public class Cons_inputBusinessGreetingMessage: TypeConstructorDescription {
            public var shortcutId: Int32
            public var recipients: Api.InputBusinessRecipients
            public var noActivityDays: Int32
            public init(shortcutId: Int32, recipients: Api.InputBusinessRecipients, noActivityDays: Int32) {
                self.shortcutId = shortcutId
                self.recipients = recipients
                self.noActivityDays = noActivityDays
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBusinessGreetingMessage", [("shortcutId", ConstructorParameterDescription(self.shortcutId)), ("recipients", ConstructorParameterDescription(self.recipients)), ("noActivityDays", ConstructorParameterDescription(self.noActivityDays))])
            }
        }
        case inputBusinessGreetingMessage(Cons_inputBusinessGreetingMessage)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputBusinessGreetingMessage(let _data):
                if boxed {
                    buffer.appendInt32(26528571)
                }
                serializeInt32(_data.shortcutId, buffer: buffer, boxed: false)
                _data.recipients.serialize(buffer, true)
                serializeInt32(_data.noActivityDays, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputBusinessGreetingMessage(let _data):
                return ("inputBusinessGreetingMessage", [("shortcutId", ConstructorParameterDescription(_data.shortcutId)), ("recipients", ConstructorParameterDescription(_data.recipients)), ("noActivityDays", ConstructorParameterDescription(_data.noActivityDays))])
            }
        }

        public static func parse_inputBusinessGreetingMessage(_ reader: BufferReader) -> InputBusinessGreetingMessage? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.InputBusinessRecipients?
            if let signature = reader.readInt32() {
                _2 = Api.parse(reader, signature: signature) as? Api.InputBusinessRecipients
            }
            var _3: Int32?
            _3 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.InputBusinessGreetingMessage.inputBusinessGreetingMessage(Cons_inputBusinessGreetingMessage(shortcutId: _1!, recipients: _2!, noActivityDays: _3!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputBusinessIntro: TypeConstructorDescription {
        public class Cons_inputBusinessIntro: TypeConstructorDescription {
            public var flags: Int32
            public var title: String
            public var description: String
            public var sticker: Api.InputDocument?
            public init(flags: Int32, title: String, description: String, sticker: Api.InputDocument?) {
                self.flags = flags
                self.title = title
                self.description = description
                self.sticker = sticker
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBusinessIntro", [("flags", ConstructorParameterDescription(self.flags)), ("title", ConstructorParameterDescription(self.title)), ("description", ConstructorParameterDescription(self.description)), ("sticker", ConstructorParameterDescription(self.sticker))])
            }
        }
        case inputBusinessIntro(Cons_inputBusinessIntro)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputBusinessIntro(let _data):
                if boxed {
                    buffer.appendInt32(163867085)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeString(_data.title, buffer: buffer, boxed: false)
                serializeString(_data.description, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    _data.sticker!.serialize(buffer, true)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputBusinessIntro(let _data):
                return ("inputBusinessIntro", [("flags", ConstructorParameterDescription(_data.flags)), ("title", ConstructorParameterDescription(_data.title)), ("description", ConstructorParameterDescription(_data.description)), ("sticker", ConstructorParameterDescription(_data.sticker))])
            }
        }

        public static func parse_inputBusinessIntro(_ reader: BufferReader) -> InputBusinessIntro? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            _2 = parseString(reader)
            var _3: String?
            _3 = parseString(reader)
            var _4: Api.InputDocument?
            if Int(_1 ?? 0) & Int(1 << 0) != 0 {
                if let signature = reader.readInt32() {
                    _4 = Api.parse(reader, signature: signature) as? Api.InputDocument
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 0) == 0) || _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.InputBusinessIntro.inputBusinessIntro(Cons_inputBusinessIntro(flags: _1!, title: _2!, description: _3!, sticker: _4))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputBusinessRecipients: TypeConstructorDescription {
        public class Cons_inputBusinessRecipients: TypeConstructorDescription {
            public var flags: Int32
            public var users: [Api.InputUser]?
            public init(flags: Int32, users: [Api.InputUser]?) {
                self.flags = flags
                self.users = users
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputBusinessRecipients", [("flags", ConstructorParameterDescription(self.flags)), ("users", ConstructorParameterDescription(self.users))])
            }
        }
        case inputBusinessRecipients(Cons_inputBusinessRecipients)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputBusinessRecipients(let _data):
                if boxed {
                    buffer.appendInt32(1871393450)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 4) != 0 {
                    buffer.appendInt32(481674261)
                    buffer.appendInt32(Int32(_data.users!.count))
                    for item in _data.users! {
                        item.serialize(buffer, true)
                    }
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputBusinessRecipients(let _data):
                return ("inputBusinessRecipients", [("flags", ConstructorParameterDescription(_data.flags)), ("users", ConstructorParameterDescription(_data.users))])
            }
        }

        public static func parse_inputBusinessRecipients(_ reader: BufferReader) -> InputBusinessRecipients? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: [Api.InputUser]?
            if Int(_1 ?? 0) & Int(1 << 4) != 0 {
                if let _ = reader.readInt32() {
                    _2 = Api.parseVector(reader, elementSignature: 0, elementType: Api.InputUser.self)
                }
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1 ?? 0) & Int(1 << 4) == 0) || _2 != nil
            if _c1 && _c2 {
                return Api.InputBusinessRecipients.inputBusinessRecipients(Cons_inputBusinessRecipients(flags: _1!, users: _2))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    indirect enum InputChannel: TypeConstructorDescription {
        public class Cons_inputChannel: TypeConstructorDescription {
            public var channelId: Int64
            public var accessHash: Int64
            public init(channelId: Int64, accessHash: Int64) {
                self.channelId = channelId
                self.accessHash = accessHash
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputChannel", [("channelId", ConstructorParameterDescription(self.channelId)), ("accessHash", ConstructorParameterDescription(self.accessHash))])
            }
        }
        public class Cons_inputChannelFromMessage: TypeConstructorDescription {
            public var peer: Api.InputPeer
            public var msgId: Int32
            public var channelId: Int64
            public init(peer: Api.InputPeer, msgId: Int32, channelId: Int64) {
                self.peer = peer
                self.msgId = msgId
                self.channelId = channelId
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputChannelFromMessage", [("peer", ConstructorParameterDescription(self.peer)), ("msgId", ConstructorParameterDescription(self.msgId)), ("channelId", ConstructorParameterDescription(self.channelId))])
            }
        }
        case inputChannel(Cons_inputChannel)
        case inputChannelEmpty
        case inputChannelFromMessage(Cons_inputChannelFromMessage)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputChannel(let _data):
                if boxed {
                    buffer.appendInt32(-212145112)
                }
                serializeInt64(_data.channelId, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                break
            case .inputChannelEmpty:
                if boxed {
                    buffer.appendInt32(-292807034)
                }
                break
            case .inputChannelFromMessage(let _data):
                if boxed {
                    buffer.appendInt32(1536380829)
                }
                _data.peer.serialize(buffer, true)
                serializeInt32(_data.msgId, buffer: buffer, boxed: false)
                serializeInt64(_data.channelId, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputChannel(let _data):
                return ("inputChannel", [("channelId", ConstructorParameterDescription(_data.channelId)), ("accessHash", ConstructorParameterDescription(_data.accessHash))])
            case .inputChannelEmpty:
                return ("inputChannelEmpty", [])
            case .inputChannelFromMessage(let _data):
                return ("inputChannelFromMessage", [("peer", ConstructorParameterDescription(_data.peer)), ("msgId", ConstructorParameterDescription(_data.msgId)), ("channelId", ConstructorParameterDescription(_data.channelId))])
            }
        }

        public static func parse_inputChannel(_ reader: BufferReader) -> InputChannel? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Int64?
            _2 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.InputChannel.inputChannel(Cons_inputChannel(channelId: _1!, accessHash: _2!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputChannelEmpty(_ reader: BufferReader) -> InputChannel? {
            return Api.InputChannel.inputChannelEmpty
        }
        public static func parse_inputChannelFromMessage(_ reader: BufferReader) -> InputChannel? {
            var _1: Api.InputPeer?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.InputPeer
            }
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Int64?
            _3 = reader.readInt64()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.InputChannel.inputChannelFromMessage(Cons_inputChannelFromMessage(peer: _1!, msgId: _2!, channelId: _3!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputChatPhoto: TypeConstructorDescription {
        public class Cons_inputChatPhoto: TypeConstructorDescription {
            public var id: Api.InputPhoto
            public init(id: Api.InputPhoto) {
                self.id = id
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputChatPhoto", [("id", ConstructorParameterDescription(self.id))])
            }
        }
        public class Cons_inputChatUploadedPhoto: TypeConstructorDescription {
            public var flags: Int32
            public var file: Api.InputFile?
            public var video: Api.InputFile?
            public var videoStartTs: Double?
            public var videoEmojiMarkup: Api.VideoSize?
            public init(flags: Int32, file: Api.InputFile?, video: Api.InputFile?, videoStartTs: Double?, videoEmojiMarkup: Api.VideoSize?) {
                self.flags = flags
                self.file = file
                self.video = video
                self.videoStartTs = videoStartTs
                self.videoEmojiMarkup = videoEmojiMarkup
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputChatUploadedPhoto", [("flags", ConstructorParameterDescription(self.flags)), ("file", ConstructorParameterDescription(self.file)), ("video", ConstructorParameterDescription(self.video)), ("videoStartTs", ConstructorParameterDescription(self.videoStartTs)), ("videoEmojiMarkup", ConstructorParameterDescription(self.videoEmojiMarkup))])
            }
        }
        case inputChatPhoto(Cons_inputChatPhoto)
        case inputChatPhotoEmpty
        case inputChatUploadedPhoto(Cons_inputChatUploadedPhoto)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputChatPhoto(let _data):
                if boxed {
                    buffer.appendInt32(-1991004873)
                }
                _data.id.serialize(buffer, true)
                break
            case .inputChatPhotoEmpty:
                if boxed {
                    buffer.appendInt32(480546647)
                }
                break
            case .inputChatUploadedPhoto(let _data):
                if boxed {
                    buffer.appendInt32(-1110593856)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    _data.file!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 1) != 0 {
                    _data.video!.serialize(buffer, true)
                }
                if Int(_data.flags) & Int(1 << 2) != 0 {
                    serializeDouble(_data.videoStartTs!, buffer: buffer, boxed: false)
                }
                if Int(_data.flags) & Int(1 << 3) != 0 {
                    _data.videoEmojiMarkup!.serialize(buffer, true)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputChatPhoto(let _data):
                return ("inputChatPhoto", [("id", ConstructorParameterDescription(_data.id))])
            case .inputChatPhotoEmpty:
                return ("inputChatPhotoEmpty", [])
            case .inputChatUploadedPhoto(let _data):
                return ("inputChatUploadedPhoto", [("flags", ConstructorParameterDescription(_data.flags)), ("file", ConstructorParameterDescription(_data.file)), ("video", ConstructorParameterDescription(_data.video)), ("videoStartTs", ConstructorParameterDescription(_data.videoStartTs)), ("videoEmojiMarkup", ConstructorParameterDescription(_data.videoEmojiMarkup))])
            }
        }

        public static func parse_inputChatPhoto(_ reader: BufferReader) -> InputChatPhoto? {
            var _1: Api.InputPhoto?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.InputPhoto
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputChatPhoto.inputChatPhoto(Cons_inputChatPhoto(id: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputChatPhotoEmpty(_ reader: BufferReader) -> InputChatPhoto? {
            return Api.InputChatPhoto.inputChatPhotoEmpty
        }
        public static func parse_inputChatUploadedPhoto(_ reader: BufferReader) -> InputChatPhoto? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Api.InputFile?
            if Int(_1 ?? 0) & Int(1 << 0) != 0 {
                if let signature = reader.readInt32() {
                    _2 = Api.parse(reader, signature: signature) as? Api.InputFile
                }
            }
            var _3: Api.InputFile?
            if Int(_1 ?? 0) & Int(1 << 1) != 0 {
                if let signature = reader.readInt32() {
                    _3 = Api.parse(reader, signature: signature) as? Api.InputFile
                }
            }
            var _4: Double?
            if Int(_1 ?? 0) & Int(1 << 2) != 0 {
                _4 = reader.readDouble()
            }
            var _5: Api.VideoSize?
            if Int(_1 ?? 0) & Int(1 << 3) != 0 {
                if let signature = reader.readInt32() {
                    _5 = Api.parse(reader, signature: signature) as? Api.VideoSize
                }
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1 ?? 0) & Int(1 << 0) == 0) || _2 != nil
            let _c3 = (Int(_1 ?? 0) & Int(1 << 1) == 0) || _3 != nil
            let _c4 = (Int(_1 ?? 0) & Int(1 << 2) == 0) || _4 != nil
            let _c5 = (Int(_1 ?? 0) & Int(1 << 3) == 0) || _5 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 {
                return Api.InputChatPhoto.inputChatUploadedPhoto(Cons_inputChatUploadedPhoto(flags: _1!, file: _2, video: _3, videoStartTs: _4, videoEmojiMarkup: _5))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputChatTheme: TypeConstructorDescription {
        public class Cons_inputChatTheme: TypeConstructorDescription {
            public var emoticon: String
            public init(emoticon: String) {
                self.emoticon = emoticon
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputChatTheme", [("emoticon", ConstructorParameterDescription(self.emoticon))])
            }
        }
        public class Cons_inputChatThemeUniqueGift: TypeConstructorDescription {
            public var slug: String
            public init(slug: String) {
                self.slug = slug
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputChatThemeUniqueGift", [("slug", ConstructorParameterDescription(self.slug))])
            }
        }
        case inputChatTheme(Cons_inputChatTheme)
        case inputChatThemeEmpty
        case inputChatThemeUniqueGift(Cons_inputChatThemeUniqueGift)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputChatTheme(let _data):
                if boxed {
                    buffer.appendInt32(-918689444)
                }
                serializeString(_data.emoticon, buffer: buffer, boxed: false)
                break
            case .inputChatThemeEmpty:
                if boxed {
                    buffer.appendInt32(-2094627709)
                }
                break
            case .inputChatThemeUniqueGift(let _data):
                if boxed {
                    buffer.appendInt32(-2014978076)
                }
                serializeString(_data.slug, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputChatTheme(let _data):
                return ("inputChatTheme", [("emoticon", ConstructorParameterDescription(_data.emoticon))])
            case .inputChatThemeEmpty:
                return ("inputChatThemeEmpty", [])
            case .inputChatThemeUniqueGift(let _data):
                return ("inputChatThemeUniqueGift", [("slug", ConstructorParameterDescription(_data.slug))])
            }
        }

        public static func parse_inputChatTheme(_ reader: BufferReader) -> InputChatTheme? {
            var _1: String?
            _1 = parseString(reader)
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputChatTheme.inputChatTheme(Cons_inputChatTheme(emoticon: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputChatThemeEmpty(_ reader: BufferReader) -> InputChatTheme? {
            return Api.InputChatTheme.inputChatThemeEmpty
        }
        public static func parse_inputChatThemeUniqueGift(_ reader: BufferReader) -> InputChatTheme? {
            var _1: String?
            _1 = parseString(reader)
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputChatTheme.inputChatThemeUniqueGift(Cons_inputChatThemeUniqueGift(slug: _1!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputChatlist: TypeConstructorDescription {
        public class Cons_inputChatlistDialogFilter: TypeConstructorDescription {
            public var filterId: Int32
            public init(filterId: Int32) {
                self.filterId = filterId
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputChatlistDialogFilter", [("filterId", ConstructorParameterDescription(self.filterId))])
            }
        }
        case inputChatlistDialogFilter(Cons_inputChatlistDialogFilter)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputChatlistDialogFilter(let _data):
                if boxed {
                    buffer.appendInt32(-203367885)
                }
                serializeInt32(_data.filterId, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputChatlistDialogFilter(let _data):
                return ("inputChatlistDialogFilter", [("filterId", ConstructorParameterDescription(_data.filterId))])
            }
        }

        public static func parse_inputChatlistDialogFilter(_ reader: BufferReader) -> InputChatlist? {
            var _1: Int32?
            _1 = reader.readInt32()
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputChatlist.inputChatlistDialogFilter(Cons_inputChatlistDialogFilter(filterId: _1!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputCheckPasswordSRP: TypeConstructorDescription {
        public class Cons_inputCheckPasswordSRP: TypeConstructorDescription {
            public var srpId: Int64
            public var A: Buffer
            public var M1: Buffer
            public init(srpId: Int64, A: Buffer, M1: Buffer) {
                self.srpId = srpId
                self.A = A
                self.M1 = M1
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputCheckPasswordSRP", [("srpId", ConstructorParameterDescription(self.srpId)), ("A", ConstructorParameterDescription(self.A)), ("M1", ConstructorParameterDescription(self.M1))])
            }
        }
        case inputCheckPasswordEmpty
        case inputCheckPasswordSRP(Cons_inputCheckPasswordSRP)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputCheckPasswordEmpty:
                if boxed {
                    buffer.appendInt32(-1736378792)
                }
                break
            case .inputCheckPasswordSRP(let _data):
                if boxed {
                    buffer.appendInt32(-763367294)
                }
                serializeInt64(_data.srpId, buffer: buffer, boxed: false)
                serializeBytes(_data.A, buffer: buffer, boxed: false)
                serializeBytes(_data.M1, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputCheckPasswordEmpty:
                return ("inputCheckPasswordEmpty", [])
            case .inputCheckPasswordSRP(let _data):
                return ("inputCheckPasswordSRP", [("srpId", ConstructorParameterDescription(_data.srpId)), ("A", ConstructorParameterDescription(_data.A)), ("M1", ConstructorParameterDescription(_data.M1))])
            }
        }

        public static func parse_inputCheckPasswordEmpty(_ reader: BufferReader) -> InputCheckPasswordSRP? {
            return Api.InputCheckPasswordSRP.inputCheckPasswordEmpty
        }
        public static func parse_inputCheckPasswordSRP(_ reader: BufferReader) -> InputCheckPasswordSRP? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Buffer?
            _2 = parseBytes(reader)
            var _3: Buffer?
            _3 = parseBytes(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.InputCheckPasswordSRP.inputCheckPasswordSRP(Cons_inputCheckPasswordSRP(srpId: _1!, A: _2!, M1: _3!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputClientProxy: TypeConstructorDescription {
        public class Cons_inputClientProxy: TypeConstructorDescription {
            public var address: String
            public var port: Int32
            public init(address: String, port: Int32) {
                self.address = address
                self.port = port
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputClientProxy", [("address", ConstructorParameterDescription(self.address)), ("port", ConstructorParameterDescription(self.port))])
            }
        }
        case inputClientProxy(Cons_inputClientProxy)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputClientProxy(let _data):
                if boxed {
                    buffer.appendInt32(1968737087)
                }
                serializeString(_data.address, buffer: buffer, boxed: false)
                serializeInt32(_data.port, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputClientProxy(let _data):
                return ("inputClientProxy", [("address", ConstructorParameterDescription(_data.address)), ("port", ConstructorParameterDescription(_data.port))])
            }
        }

        public static func parse_inputClientProxy(_ reader: BufferReader) -> InputClientProxy? {
            var _1: String?
            _1 = parseString(reader)
            var _2: Int32?
            _2 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            if _c1 && _c2 {
                return Api.InputClientProxy.inputClientProxy(Cons_inputClientProxy(address: _1!, port: _2!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputCollectible: TypeConstructorDescription {
        public class Cons_inputCollectiblePhone: TypeConstructorDescription {
            public var phone: String
            public init(phone: String) {
                self.phone = phone
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputCollectiblePhone", [("phone", ConstructorParameterDescription(self.phone))])
            }
        }
        public class Cons_inputCollectibleUsername: TypeConstructorDescription {
            public var username: String
            public init(username: String) {
                self.username = username
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputCollectibleUsername", [("username", ConstructorParameterDescription(self.username))])
            }
        }
        case inputCollectiblePhone(Cons_inputCollectiblePhone)
        case inputCollectibleUsername(Cons_inputCollectibleUsername)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputCollectiblePhone(let _data):
                if boxed {
                    buffer.appendInt32(-1562241884)
                }
                serializeString(_data.phone, buffer: buffer, boxed: false)
                break
            case .inputCollectibleUsername(let _data):
                if boxed {
                    buffer.appendInt32(-476815191)
                }
                serializeString(_data.username, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputCollectiblePhone(let _data):
                return ("inputCollectiblePhone", [("phone", ConstructorParameterDescription(_data.phone))])
            case .inputCollectibleUsername(let _data):
                return ("inputCollectibleUsername", [("username", ConstructorParameterDescription(_data.username))])
            }
        }

        public static func parse_inputCollectiblePhone(_ reader: BufferReader) -> InputCollectible? {
            var _1: String?
            _1 = parseString(reader)
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputCollectible.inputCollectiblePhone(Cons_inputCollectiblePhone(phone: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputCollectibleUsername(_ reader: BufferReader) -> InputCollectible? {
            var _1: String?
            _1 = parseString(reader)
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputCollectible.inputCollectibleUsername(Cons_inputCollectibleUsername(username: _1!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputContact: TypeConstructorDescription {
        public class Cons_inputPhoneContact: TypeConstructorDescription {
            public var flags: Int32
            public var clientId: Int64
            public var phone: String
            public var firstName: String
            public var lastName: String
            public var note: Api.TextWithEntities?
            public init(flags: Int32, clientId: Int64, phone: String, firstName: String, lastName: String, note: Api.TextWithEntities?) {
                self.flags = flags
                self.clientId = clientId
                self.phone = phone
                self.firstName = firstName
                self.lastName = lastName
                self.note = note
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputPhoneContact", [("flags", ConstructorParameterDescription(self.flags)), ("clientId", ConstructorParameterDescription(self.clientId)), ("phone", ConstructorParameterDescription(self.phone)), ("firstName", ConstructorParameterDescription(self.firstName)), ("lastName", ConstructorParameterDescription(self.lastName)), ("note", ConstructorParameterDescription(self.note))])
            }
        }
        case inputPhoneContact(Cons_inputPhoneContact)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputPhoneContact(let _data):
                if boxed {
                    buffer.appendInt32(1780335806)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                serializeInt64(_data.clientId, buffer: buffer, boxed: false)
                serializeString(_data.phone, buffer: buffer, boxed: false)
                serializeString(_data.firstName, buffer: buffer, boxed: false)
                serializeString(_data.lastName, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    _data.note!.serialize(buffer, true)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputPhoneContact(let _data):
                return ("inputPhoneContact", [("flags", ConstructorParameterDescription(_data.flags)), ("clientId", ConstructorParameterDescription(_data.clientId)), ("phone", ConstructorParameterDescription(_data.phone)), ("firstName", ConstructorParameterDescription(_data.firstName)), ("lastName", ConstructorParameterDescription(_data.lastName)), ("note", ConstructorParameterDescription(_data.note))])
            }
        }

        public static func parse_inputPhoneContact(_ reader: BufferReader) -> InputContact? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: String?
            _3 = parseString(reader)
            var _4: String?
            _4 = parseString(reader)
            var _5: String?
            _5 = parseString(reader)
            var _6: Api.TextWithEntities?
            if Int(_1 ?? 0) & Int(1 << 0) != 0 {
                if let signature = reader.readInt32() {
                    _6 = Api.parse(reader, signature: signature) as? Api.TextWithEntities
                }
            }
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = (Int(_1 ?? 0) & Int(1 << 0) == 0) || _6 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 {
                return Api.InputContact.inputPhoneContact(Cons_inputPhoneContact(flags: _1!, clientId: _2!, phone: _3!, firstName: _4!, lastName: _5!, note: _6))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    indirect enum InputDialogPeer: TypeConstructorDescription {
        public class Cons_inputDialogPeer: TypeConstructorDescription {
            public var peer: Api.InputPeer
            public init(peer: Api.InputPeer) {
                self.peer = peer
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputDialogPeer", [("peer", ConstructorParameterDescription(self.peer))])
            }
        }
        public class Cons_inputDialogPeerCommunity: TypeConstructorDescription {
            public var community: Api.InputChannel
            public init(community: Api.InputChannel) {
                self.community = community
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputDialogPeerCommunity", [("community", ConstructorParameterDescription(self.community))])
            }
        }
        public class Cons_inputDialogPeerFolder: TypeConstructorDescription {
            public var folderId: Int32
            public init(folderId: Int32) {
                self.folderId = folderId
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputDialogPeerFolder", [("folderId", ConstructorParameterDescription(self.folderId))])
            }
        }
        case inputDialogPeer(Cons_inputDialogPeer)
        case inputDialogPeerCommunity(Cons_inputDialogPeerCommunity)
        case inputDialogPeerFolder(Cons_inputDialogPeerFolder)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputDialogPeer(let _data):
                if boxed {
                    buffer.appendInt32(-55902537)
                }
                _data.peer.serialize(buffer, true)
                break
            case .inputDialogPeerCommunity(let _data):
                if boxed {
                    buffer.appendInt32(1777300164)
                }
                _data.community.serialize(buffer, true)
                break
            case .inputDialogPeerFolder(let _data):
                if boxed {
                    buffer.appendInt32(1684014375)
                }
                serializeInt32(_data.folderId, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputDialogPeer(let _data):
                return ("inputDialogPeer", [("peer", ConstructorParameterDescription(_data.peer))])
            case .inputDialogPeerCommunity(let _data):
                return ("inputDialogPeerCommunity", [("community", ConstructorParameterDescription(_data.community))])
            case .inputDialogPeerFolder(let _data):
                return ("inputDialogPeerFolder", [("folderId", ConstructorParameterDescription(_data.folderId))])
            }
        }

        public static func parse_inputDialogPeer(_ reader: BufferReader) -> InputDialogPeer? {
            var _1: Api.InputPeer?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.InputPeer
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputDialogPeer.inputDialogPeer(Cons_inputDialogPeer(peer: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputDialogPeerCommunity(_ reader: BufferReader) -> InputDialogPeer? {
            var _1: Api.InputChannel?
            if let signature = reader.readInt32() {
                _1 = Api.parse(reader, signature: signature) as? Api.InputChannel
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputDialogPeer.inputDialogPeerCommunity(Cons_inputDialogPeerCommunity(community: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputDialogPeerFolder(_ reader: BufferReader) -> InputDialogPeer? {
            var _1: Int32?
            _1 = reader.readInt32()
            let _c1 = _1 != nil
            if _c1 {
                return Api.InputDialogPeer.inputDialogPeerFolder(Cons_inputDialogPeerFolder(folderId: _1!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum InputDocument: TypeConstructorDescription {
        public class Cons_inputDocument: TypeConstructorDescription {
            public var id: Int64
            public var accessHash: Int64
            public var fileReference: Buffer
            public init(id: Int64, accessHash: Int64, fileReference: Buffer) {
                self.id = id
                self.accessHash = accessHash
                self.fileReference = fileReference
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("inputDocument", [("id", ConstructorParameterDescription(self.id)), ("accessHash", ConstructorParameterDescription(self.accessHash)), ("fileReference", ConstructorParameterDescription(self.fileReference))])
            }
        }
        case inputDocument(Cons_inputDocument)
        case inputDocumentEmpty

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .inputDocument(let _data):
                if boxed {
                    buffer.appendInt32(448771445)
                }
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.accessHash, buffer: buffer, boxed: false)
                serializeBytes(_data.fileReference, buffer: buffer, boxed: false)
                break
            case .inputDocumentEmpty:
                if boxed {
                    buffer.appendInt32(1928391342)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .inputDocument(let _data):
                return ("inputDocument", [("id", ConstructorParameterDescription(_data.id)), ("accessHash", ConstructorParameterDescription(_data.accessHash)), ("fileReference", ConstructorParameterDescription(_data.fileReference))])
            case .inputDocumentEmpty:
                return ("inputDocumentEmpty", [])
            }
        }

        public static func parse_inputDocument(_ reader: BufferReader) -> InputDocument? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Buffer?
            _3 = parseBytes(reader)
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            if _c1 && _c2 && _c3 {
                return Api.InputDocument.inputDocument(Cons_inputDocument(id: _1!, accessHash: _2!, fileReference: _3!))
            }
            else {
                return nil
            }
        }
        public static func parse_inputDocumentEmpty(_ reader: BufferReader) -> InputDocument? {
            return Api.InputDocument.inputDocumentEmpty
        }
    }
}
