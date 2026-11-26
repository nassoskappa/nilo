import Foundation
import Testing
@testable import NiloCore

/// "Now" is Wednesday 3 March 2027, 11:00, UTC.
let wednesday11 = utc.date(from: DateComponents(year: 2027, month: 3, day: 3, hour: 11))!

func when(_ text: String, allowPast: Bool = false) -> WhenReader.When? {
    WhenReader.read(text, now: wednesday11, calendar: utc, allowPast: allowPast)
}

func on(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 3, year: Int = 2027) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Suite("Reading when")
struct WhenReaderTests {
    @Test func weekdayAndBareHourMeansAfternoon() {
        #expect(when("Thursday at 3")?.date == on(4, 15))
    }

    @Test func amAndPmAreRespected() {
        #expect(when("tomorrow 10:30am")?.date == on(4, 10, 30))
        #expect(when("tomorrow at 9")?.date == on(4, 9))
        #expect(when("friday 7pm")?.date == on(5, 19))
        #expect(when("friday 12am")?.date == on(5, 0))
    }

    @Test func twentyFourHourTimes() {
        #expect(when("Friday 15:00")?.date == on(5, 15))
        #expect(when("Friday 10.15")?.date == on(5, 10, 15))
    }

    @Test func todaysWeekdayMeansTodayIfTheTimeIsAhead() {
        #expect(when("Wednesday at 2")?.date == on(3, 14))   // still ahead today
        #expect(when("Wednesday at 10")?.date == on(10, 10)) // already past: next week
    }

    @Test func nextAlwaysMeansNextWeekOnTheSameDay() {
        #expect(when("next Wednesday at 1pm")?.date == on(10, 13))
    }

    @Test func whichMeetingFallsBackToTheRequestsOwnWords() {
        #expect(Understand.meetingWords("Can you move the standup to 11:30 tomorrow") == "the standup")
        #expect(Understand.meetingWords("Reschedule my meeting with Maria to Monday 9am") == "my meeting with Maria")
        #expect(Understand.meetingWords("Add lunch on Friday") == nil)
    }

    @Test func headlines() {
        let plain = Understood.addMeeting(AddMeetingJob(title: "Meeting with Maria", people: ["Maria"], start: on(4, 15), end: on(4, 15, 30), tellPeople: true))
        #expect(JobText.lines(plain).headline == "Add a meeting with Maria")
        let named = Understood.addMeeting(AddMeetingJob(title: "Design review", people: [], start: on(4, 15), end: on(4, 16), tellPeople: false))
        #expect(JobText.lines(named).headline == "Add Design review")
    }

    @Test func nextAndShortWeekdayNames() {
        #expect(when("next Tue 1pm")?.date == on(9, 13))
        #expect(when("thurs noon")?.date == on(4, 12))
    }

    @Test func explicitDates() {
        #expect(when("27 November at 3")?.date == on(27, 15, month: 11))
        #expect(when("Nov 27th 10am")?.date == on(27, 10, month: 11))
        #expect(when("1 March at 3")?.date == on(1, 15, month: 3, year: 2028)) // already past this year
    }

    @Test func onlyATimeMeansTheNextOne() {
        #expect(when("at 3")?.date == on(3, 15))        // still ahead today
        #expect(when("at 10am")?.date == on(4, 10))     // already past: tomorrow
        #expect(when("my 10am", allowPast: true)?.date == on(3, 10)) // which meeting: today, even if past
    }

    @Test func onlyADayHasNoTime() {
        let w = when("Thursday")
        #expect(w?.day == on(4, 0))
        #expect(w?.date == nil)
    }

    @Test func otherDayWords() {
        #expect(when("day after tomorrow at 4")?.date == on(5, 16))
        #expect(when("in 3 days at 11")?.date == on(6, 11))
        #expect(when("today at 5")?.date == on(3, 17))
    }

    @Test func nonsenseIsNil() {
        #expect(when("whenever suits") == nil)
        #expect(when("at 25") == nil)
    }
}

@Suite("Understanding requests")
struct UnderstandTests {
    func job(_ form: RequestForm) -> Understood {
        Understand.job(from: form, now: wednesday11, calendar: utc)
    }

    @Test func addAMeetingWithAPerson() {
        let result = job(RequestForm(job: .addMeeting, title: "Meeting with Maria", people: ["Maria"], when: "Thursday at 3", tellPeople: true))
        #expect(result == .addMeeting(AddMeetingJob(title: "Meeting with Maria", people: ["Maria"], start: on(4, 15), end: on(4, 15, 30), tellPeople: true)))
    }

    @Test func aRealTitleAndLengthAreKept() {
        guard case .addMeeting(let j) = job(RequestForm(job: .addMeeting, title: "Design review", people: ["Joe", "Ana"], when: "next Tue 1pm", minutes: 60)) else {
            Issue.record("expected a meeting")
            return
        }
        #expect(j.title == "Design review")
        #expect(j.end == on(9, 14))
        #expect(j.tellPeople == false)
    }

    @Test func noWhenMeansAQuestion() {
        #expect(job(RequestForm(job: .addMeeting, people: ["Maria"])) == .question("When should it be?"))
        #expect(job(RequestForm(job: .addMeeting, people: ["Maria"], when: "Thursday")) == .question("What time?"))
    }

    @Test func tellingNobodyIsNotTelling() {
        guard case .addMeeting(let j) = job(RequestForm(job: .addMeeting, when: "Friday at 10", tellPeople: true)) else {
            Issue.record("expected a meeting")
            return
        }
        #expect(j.tellPeople == false)
        #expect(j.title == "Meeting")
    }

    @Test func moveAMeeting() {
        let result = job(RequestForm(job: .moveMeeting, when: "Friday at 10", meeting: "my 3pm", reason: "I'm stuck on a call", tellPeople: true))
        #expect(result == .moveMeeting(MoveMeetingJob(meeting: "my 3pm", currently: on(3, 15), newStart: on(5, 10), newMinutes: nil, reason: "I'm stuck on a call", tellPeople: true)))
    }

    @Test func moveNeedsWhichAndWhen() {
        #expect(job(RequestForm(job: .moveMeeting, when: "Friday at 10")) == .question("Which meeting should move?"))
        #expect(job(RequestForm(job: .moveMeeting, meeting: "the design review")) == .question("When should it move to?"))
    }

    @Test func otherRequestsAreNotJobs() {
        #expect(job(RequestForm(job: .other)) == .notAJob)
    }

    @Test func tellNeedsATellingWordInTheRequest() {
        let form = RequestForm(job: .addMeeting, people: ["Leo"], when: "Friday at 5", tellPeople: true)
        guard case .addMeeting(let quiet) = Understand.job(from: form, request: "Plan a catch up with Leo Friday at 5", now: wednesday11, calendar: utc),
              case .addMeeting(let told) = Understand.job(from: form, request: "Catch up with Leo Friday at 5 and let him know", now: wednesday11, calendar: utc) else {
            Issue.record("expected meetings")
            return
        }
        #expect(quiet.tellPeople == false)
        #expect(told.tellPeople == true)
    }

    @Test func aTimeLeftOutOfWhenIsReadFromTheRequest() {
        let form = RequestForm(job: .addMeeting, people: ["Tom"], when: "tomorrow")
        guard case .addMeeting(let j) = Understand.job(from: form, request: "Coffee with Tom tomorrow at 9", now: wednesday11, calendar: utc) else {
            Issue.record("expected a meeting")
            return
        }
        #expect(j.start == on(4, 9))
    }

    @Test func forAMoveTheMeetingsOwnTimeIsNotTheNewTime() {
        let form = RequestForm(job: .moveMeeting, when: "Friday", meeting: "my 3pm")
        guard case .moveMeeting(let j) = Understand.job(from: form, request: "Move my 3pm to Friday at 10", now: wednesday11, calendar: utc) else {
            Issue.record("expected a move")
            return
        }
        #expect(j.newStart == on(5, 10))
        #expect(j.currently == on(3, 15))
    }

    @Test func names() {
        #expect(ListText.join(["Maria"]) == "Maria")
        #expect(ListText.join(["Maria", "Joe"]) == "Maria and Joe")
        #expect(ListText.join(["Maria", "Joe", "Ana"]) == "Maria, Joe and Ana")
    }
}
