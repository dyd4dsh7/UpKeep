// Ed25519 signing for Upkeep self-update archives.
//
//   swift scripts/update-signing.swift generate <private-key-file>   # once; prints the public key
//   swift scripts/update-signing.swift public   <private-key-file>   # prints the public key
//   swift scripts/update-signing.swift sign     <archive> <private-key-file>   # prints the signature
//
// The private key file holds a base64 Curve25519 signing key. Keep it out of
// the repository and back it up: without it, releases cannot be verified by
// installed copies of Upkeep, and users must update manually once.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadKey(_ path: String) -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("Cannot read signing key at \(path)") }
    return key
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail("usage: update-signing.swift generate|public|sign …") }
switch arguments[1] {
case "generate":
    let path = arguments[2]
    guard !FileManager.default.fileExists(atPath: path) else { fail("\(path) already exists; refusing to overwrite a signing key.") }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
    guard FileManager.default.createFile(atPath: path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
                                         attributes: [.posixPermissions: 0o600]) else { fail("Cannot write \(path)") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(loadKey(arguments[2]).publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard arguments.count >= 4, let archive = FileManager.default.contents(atPath: arguments[2]) else { fail("Cannot read archive") }
    print(try loadKey(arguments[3]).signature(for: archive).base64EncodedString())
default:
    fail("unknown command \(arguments[1])")
}
