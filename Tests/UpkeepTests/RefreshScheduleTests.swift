import Foundation
import Testing
@testable import Upkeep

@Test func intervalScheduleAdvancesFromLastSuccessfulCheck() {
    let lastCheck = Date(timeIntervalSince1970: 1_000)
    let now = lastCheck.addingTimeInterval((2 * 3_600) + 30)

    #expect(
        RefreshInterval.hourly.nextDate(
            after: lastCheck, now: now, dailyTimeMinutes: 9 * 60
        ) == lastCheck.addingTimeInterval(3 * 3_600)
    )
}

@Test func dailyScheduleUsesTheSelectedLocalTime() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let now = try #require(calendar.date(from: DateComponents(
        year: 2026, month: 7, day: 22, hour: 10
    )))
    let expected = try #require(calendar.date(from: DateComponents(
        year: 2026, month: 7, day: 23, hour: 9, minute: 30
    )))

    #expect(
        RefreshInterval.daily.nextDate(
            after: now, now: now, dailyTimeMinutes: (9 * 60) + 30, calendar: calendar
        ) == expected
    )
}

@Test func disabledScheduleHasNoNextCheck() {
    #expect(RefreshInterval.never.nextDate(after: Date(), dailyTimeMinutes: 0) == nil)
}
