import Foundation
import TelegramCore

public func hasBirthdayToday(cachedData: CachedUserData) -> Bool {
    if let birthday = cachedData.birthday {
        return hasBirthdayToday(birthday: birthday)
    }
    return false
}

public func hasBirthdayToday(birthday: TelegramBirthday) -> Bool {
    return hasBirthdayToday(birthday: birthday, now: Date(), calendar: gregorianCalendarForBirthdayCalculations())
}

func hasBirthdayToday(birthday: TelegramBirthday, now: Date, calendar: Calendar) -> Bool {
    let today = calendar.dateComponents(Set([.day, .month]), from: now)
    return today.day == Int(birthday.day) && today.month == Int(birthday.month)
}
