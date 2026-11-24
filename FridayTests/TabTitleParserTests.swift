import Testing

@testable import Friday

struct TabTitleParserTests {
    @Test func whatsappUnreadFromTitle() {
        #expect(TabTitleParser.whatsappUnread(in: ["(74) WhatsApp", "YouTube"]) == 74)
        #expect(TabTitleParser.whatsappUnread(in: ["(1,204) WhatsApp Business"]) == 1204)
    }

    @Test func whatsappWithoutUnreadIsZero() {
        #expect(TabTitleParser.whatsappUnread(in: ["WhatsApp"]) == 0)
    }

    @Test func noWhatsappTabIsNil() {
        #expect(TabTitleParser.whatsappUnread(in: ["Inbox (2) - a@b.com - Gmail", "WhatsApp call"]) == 0)
        #expect(TabTitleParser.whatsappUnread(in: ["GitHub", "Stitch - Projects"]) == nil)
    }

    @Test func gmailAccountsAreSeparatedAndSorted() {
        let titles = [
            "Inbox (5) - Work@Company.com - Company Mail",
            "Inbox - gamer@gmail.com - Gmail",
            "Inbox (12) - me@gmail.com - Gmail",
            "Inbox (13) - me@gmail.com - Gmail",
            "Spam (3) - me@gmail.com - Gmail",
            "Weekly report – Google Docs",
        ]
        #expect(
            TabTitleParser.gmailAccounts(in: titles) == [
                .init(email: "gamer@gmail.com", unread: 0),
                .init(email: "me@gmail.com", unread: 13),
            ]
        )
    }

    @Test func gmailWorkspaceTitleIncludingGmailSuffix() {
        let titles = ["Inbox (1,050) – person@thapar.edu – Thapar Institute Mail - Gmail"]
        #expect(TabTitleParser.gmailAccounts(in: titles) == [.init(email: "person@thapar.edu", unread: 1050)])
    }
}
