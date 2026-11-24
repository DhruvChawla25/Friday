// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Testing

@testable import Friday

struct DockBadgeTests {
    @Test func numericBadge() {
        #expect(DockBadge.count(fromLSAppInfo: #""StatusLabel"={ "label"="12" }"#) == 12)
    }

    @Test func noBadgeIsZero() {
        #expect(DockBadge.count(fromLSAppInfo: #""StatusLabel"=[ NULL ]"#) == 0)
        #expect(DockBadge.count(fromLSAppInfo: #""StatusLabel"={ "label"=kCFNULL }"#) == 0)
        #expect(DockBadge.count(fromLSAppInfo: #""StatusLabel"={ "label"="" }"#) == 0)
    }

    @Test func dotBadgeCountsAsOne() {
        #expect(DockBadge.count(fromLSAppInfo: #""StatusLabel"={ "label"="•" }"#) == 1)
    }

    @Test func largeBadgeWithSeparatorOrPlus() {
        #expect(DockBadge.count(fromLSAppInfo: #""StatusLabel"={ "label"="1,204" }"#) == 1204)
        #expect(DockBadge.count(fromLSAppInfo: #""StatusLabel"={ "label"="99+" }"#) == 99)
    }

    @Test func unrelatedOutputIsNil() {
        #expect(DockBadge.count(fromLSAppInfo: "") == nil)
    }
}
