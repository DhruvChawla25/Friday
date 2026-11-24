import Testing

@testable import Friday

struct RibbonModelTests {
    @Test func producesOneQuadPerSegment() {
        #expect(RibbonModel.quads(segments: 48).count == 48)
    }

    @Test func taperedTipsAndFiniteGeometry() {
        #expect(RibbonModel.width(0) < 0.001)
        #expect(RibbonModel.width(1) < 0.001)
        for quad in RibbonModel.quads(segments: 64) {
            #expect(quad.corners.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            #expect(abs(quad.normal.length - 1) < 0.001 || quad.normal.length == 0)
        }
    }

    @Test func fitsInsideUnitBox() {
        for quad in RibbonModel.quads(segments: 64) {
            for corner in quad.corners {
                #expect(abs(corner.x) <= 1.2 && abs(corner.y) <= 1.2 && abs(corner.z) <= 1.2)
            }
        }
    }
}
