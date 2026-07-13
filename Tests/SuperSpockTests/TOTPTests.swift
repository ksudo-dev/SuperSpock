import XCTest
@testable import SuperSpock

final class TOTPTests: XCTestCase {
    func testRFC6238SHA1Vector() {
        let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        XCTAssertEqual(TOTP.code(secret: secret, date: Date(timeIntervalSince1970: 59), digits: 8), "94287082")
    }
    func testBadSecret() { XCTAssertNil(TOTP.code(secret: "!!!")) }
    func testExtractsOTPAuthSecret() {
        XCTAssertEqual(TOTP.secret(from: "otpauth://totp/GLKVM?secret=GEZDGNBVGY3TQOJQ&issuer=GLKVM"), "GEZDGNBVGY3TQOJQ")
    }
    func testRejectsRotatingCodeAsSecret() { XCTAssertNil(TOTP.secret(from: "123456")) }
}
