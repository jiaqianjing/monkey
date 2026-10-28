import Foundation
import Security

struct ChatGPTIdentity {
    let subject: String
    let email: String
}

enum ChatGPTIDTokenVerifier {
    /// Verifies RS256 with the trusted issuer's JWKS before inspecting account claims.
    static func verify(_ token: String, clientID: String, nonce: String?, jwks: Data, now: Date = Date()) throws -> ChatGPTIdentity {
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              let headerData = Data(base64URL: String(pieces[0])),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let claimsData = Data(base64URL: String(pieces[1])),
              let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              let signature = Data(base64URL: String(pieces[2])),
              header["alg"] as? String == "RS256",
              let kid = header["kid"] as? String,
              let keySet = try JSONSerialization.jsonObject(with: jwks) as? [String: Any],
              let keys = keySet["keys"] as? [[String: Any]],
              let jwk = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              (jwk["use"] as? String ?? "sig") == "sig",
              (jwk["alg"] as? String ?? "RS256") == "RS256",
              let modulus = jwk["n"] as? String, let exponent = jwk["e"] as? String,
              let n = Data(base64URL: modulus), let e = Data(base64URL: exponent) else {
            throw ChatGPTError.message("ChatGPT 身份签名格式不正确。")
        }
        let publicKeyDER = sequence(integer(n) + integer(e))
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        var keyError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(publicKeyDER as CFData, attributes as CFDictionary, &keyError) else {
            throw ChatGPTError.message("无法验证 ChatGPT 身份公钥。")
        }
        let signed = Data("\(pieces[0]).\(pieces[1])".utf8)
        guard SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                    signed as CFData, signature as CFData, nil) else {
            throw ChatGPTError.message("ChatGPT 身份签名校验失败。")
        }
        return try validateClaims(claims, clientID: clientID, nonce: nonce, now: now)
    }

    static func validateClaims(_ claims: [String: Any], clientID: String, nonce: String?, now: Date) throws -> ChatGPTIdentity {
        let audiences = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        let seconds = now.timeIntervalSince1970
        guard claims["iss"] as? String == ChatGPTOAuth.issuer,
              audiences.contains(clientID),
              let expiration = claims["exp"] as? Double, expiration > seconds,
              let subject = claims["sub"] as? String, !subject.isEmpty else {
            throw ChatGPTError.message("ChatGPT 身份、有效期或连接校验失败。")
        }
        if let authorizedParty = claims["azp"] as? String, authorizedParty != clientID {
            throw ChatGPTError.message("ChatGPT 身份所属应用不匹配。")
        }
        if audiences.count > 1 && claims["azp"] as? String != clientID {
            throw ChatGPTError.message("ChatGPT 身份所属应用不明确。")
        }
        if let notBefore = claims["nbf"] as? Double, notBefore > seconds + 30 {
            throw ChatGPTError.message("ChatGPT 身份尚未生效，请检查系统时间。")
        }
        if let issuedAt = claims["iat"] as? Double, issuedAt > seconds + 30 {
            throw ChatGPTError.message("ChatGPT 身份时间不正确，请检查系统时间。")
        }
        if let nonce, claims["nonce"] as? String != nonce {
            throw ChatGPTError.message("ChatGPT 登录随机数校验失败，请重新登录。")
        }
        return ChatGPTIdentity(subject: subject, email: claims["email"] as? String ?? "ChatGPT 账号")
    }

    private static func sequence(_ bytes: Data) -> Data { Data([0x30]) + length(bytes.count) + bytes }
    private static func integer(_ bytes: Data) -> Data {
        var positive = Data(bytes.drop(while: { $0 == 0 }))
        if positive.isEmpty { positive = Data([0]) }
        if positive.first! & 0x80 != 0 { positive.insert(0, at: 0) }
        return Data([0x02]) + length(positive.count) + positive
    }
    private static func length(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        var value = count
        var bytes = [UInt8]()
        while value > 0 { bytes.insert(UInt8(value & 0xff), at: 0); value >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
