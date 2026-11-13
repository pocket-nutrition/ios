// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore
@testable import PocketNutritionVault

// MARK: - Fakes

private final class MemorySecrets: VaultSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    var failWrites = false

    init(_ value: String? = nil) { self.value = value }

    func read() throws -> String? { lock.withLock { value } }
    func write(_ secret: String) throws {
        if failWrites { throw VaultError.offline }
        lock.withLock { value = secret }
    }
    func delete() throws { lock.withLock { value = nil } }
}

private final class MemoryInstall: VaultInstallMarking, @unchecked Sendable {
    private let lock = NSLock()
    private var launched: Bool
    init(launched: Bool) { self.launched = launched }
    var hasLaunchedBefore: Bool { lock.withLock { launched } }
    func markLaunched() { lock.withLock { launched = true } }
}

/// A small in-memory vault: it keeps what register sends and checks what login and delete send, so the
/// model is tested against the behaviour of the protocol and not against scripted answers.
private final class FakeVault: VaultServing, @unchecked Sendable {
    private struct Account {
        let id: String
        let authHash: String
        let kdf: VaultKdf
        let keyring: String
    }

    private let lock = NSLock()
    private var accounts: [String: Account] = [:]
    private var keys: [String: String] = [:]
    private var issued = 0

    // Switches a test can flip.
    var registrationOpen = true
    var offline = false
    var lockedFor: Int?
    var preloginOverride: VaultKdf?
    var corruptKeyring = false

    private(set) var revoked: [String] = []
    private(set) var loginCalls = 0
    private(set) var registerCalls = 0

    func serverInfo() async throws -> VaultServerInfo {
        if offline { throw VaultError.offline }
        return try JSONDecoder().decode(
            VaultServerInfo.self,
            from: Data(
                #"{"name":"Test vault","version":"1","registration":"\#(registrationOpen ? "open" : "closed")","quota_bytes":1000}"#
                    .utf8))
    }

    func prelogin(username: String) async throws -> VaultKdf {
        if offline { throw VaultError.offline }
        if let preloginOverride { return preloginOverride }
        return lock.withLock { accounts[username]?.kdf } ?? VaultKdf(
            salt: Data(repeating: 7, count: 16).base64EncodedString(), opslimit: 3, memlimit: 64 * 1024 * 1024)
    }

    func register(_ request: VaultRegisterRequest) async throws -> VaultSession {
        if offline { throw VaultError.offline }
        guard registrationOpen else { throw VaultError.outcome(.registrationClosed) }
        return try lock.withLock {
            registerCalls += 1
            guard accounts[request.username] == nil else { throw VaultError.outcome(.usernameTaken) }
            let account = Account(
                id: "acc-\(accounts.count + 1)", authHash: request.authHash, kdf: request.kdf, keyring: request.keyring)
            accounts[request.username] = account
            return try session(for: request.username, account: account)
        }
    }

    func login(_ request: VaultLoginRequest) async throws -> VaultSession {
        if offline { throw VaultError.offline }
        return try lock.withLock {
            loginCalls += 1
            if let lockedFor { throw VaultError.outcome(.tooManyAttempts(retryAfter: lockedFor)) }
            guard let account = accounts[request.username], account.authHash == request.authHash else {
                throw VaultError.outcome(.invalidCredentials)
            }
            return try session(for: request.username, account: account)
        }
    }

    func logout(apiKey: String) async throws {
        if offline { throw VaultError.offline }
        lock.withLock {
            revoked.append(apiKey)
            keys[apiKey] = nil
        }
    }

    func deleteRecord(apiKey: String, id: String, revision: Int) async throws {}

    func deleteAccount(apiKey: String, authHash: String) async throws {
        if offline { throw VaultError.offline }
        try lock.withLock {
            guard let username = keys[apiKey], let account = accounts[username] else {
                throw VaultError.outcome(.unauthorized)
            }
            guard account.authHash == authHash else { throw VaultError.outcome(.unauthorized) }
            accounts[username] = nil
            keys = keys.filter { $0.value != username }
        }
    }

    var accountCount: Int { lock.withLock { accounts.count } }

    // Not used by the account model.
    func createDrop(apiKey: String, _ request: VaultDropRequest) async throws -> VaultDropToken {
        throw VaultError.offline
    }
    func sync(apiKey: String, since: Int) async throws -> VaultSyncPage { throw VaultError.offline }
    func putRecord(apiKey: String, id: String, _ write: VaultRecordWrite) async throws { throw VaultError.offline }

    /// Callers hold the lock.
    private func session(for username: String, account: Account) throws -> VaultSession {
        issued += 1
        let apiKey = "key-\(issued)"
        keys[apiKey] = username
        let keyring = corruptKeyring ? #"{"v":1}"# : account.keyring
        let body: [String: Any] = [
            "account_id": account.id, "api_key": apiKey, "key_id": "kid-\(issued)",
            "keyring": ["blob": keyring, "version": 1],
        ]
        return try JSONDecoder().decode(VaultSession.self, from: JSONSerialization.data(withJSONObject: body))
    }
}

private final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String] = []
    func add(_ url: String) { lock.withLock { urls.append(url) } }
    var all: [String] { lock.withLock { urls } }
}

private let serverURL = "https://vault.example"
private let goodPassphrase = "correct horse battery staple"

// MARK: - Tests

@Suite("vault account model")
@MainActor
struct VaultAccountModelTests {

    private func makeModel(
        _ server: FakeVault, secrets: MemorySecrets = MemorySecrets(), launched: Bool = true,
        remember: URLBox = URLBox()
    ) -> VaultAccountModel {
        VaultAccountModel(
            deviceLabel: "iPhone",
            makeServer: { _ in server },
            sessions: VaultSessionStore(secrets: secrets),
            install: MemoryInstall(launched: launched),
            rememberServerURL: { remember.add($0) }
        )
    }

    /// A model that has already checked the server.
    private func checked(
        _ server: FakeVault, secrets: MemorySecrets = MemorySecrets()
    ) async -> VaultAccountModel {
        let model = makeModel(server, secrets: secrets)
        await model.checkServer(serverURL)
        return model
    }

    private func createAccount(on model: VaultAccountModel, username: String = "alice") async {
        await model.prepareAccount(username: username, passphrase: goodPassphrase, confirmation: goodPassphrase)
        await model.registerPreparedAccount()
    }

    // MARK: Server

    @Test("a vault answering is accepted and its address remembered")
    func checkServerSucceeds() async {
        let remember = URLBox()
        let model = makeModel(FakeVault(), remember: remember)
        await model.checkServer("  \(serverURL) ")
        #expect(model.serverInfo?.name == "Test vault")
        #expect(model.error == nil)
        #expect(remember.all == ["https://vault.example"])
    }

    @Test("plain http and malformed addresses are refused before any call")
    func checkServerRefusesBadURLs() async {
        for raw in ["http://vault.example", "vault.example", "", "https://user:pw@vault.example"] {
            let model = makeModel(FakeVault())
            await model.checkServer(raw)
            #expect(model.error == .invalidServerURL, "\(raw)")
            #expect(model.serverInfo == nil)
        }
    }

    @Test("an unreachable server is reported as offline")
    func checkServerOffline() async {
        let server = FakeVault()
        server.offline = true
        let model = makeModel(server)
        await model.checkServer(serverURL)
        #expect(model.error == .offline)
    }

    // MARK: Create an account

    @Test("creating an account shows the recovery key first and registers only after it is confirmed")
    func registrationWaitsForTheRecoveryKey() async {
        let server = FakeVault()
        let model = await checked(server)
        await model.prepareAccount(username: " Alice ", passphrase: goodPassphrase, confirmation: goodPassphrase)

        #expect(VaultRecoveryKeyFormat.decode(model.pendingRecoveryKey ?? "") != nil)
        #expect(server.registerCalls == 0)
        #expect(model.phase == .signedOut)

        await model.registerPreparedAccount()
        #expect(model.phase == .signedIn(VaultAccountSummary(username: "alice", serverURL: URL(string: serverURL)!)))
        #expect(model.pendingRecoveryKey == nil)
        #expect(server.accountCount == 1)
    }

    @Test("the form is validated before any key is derived", arguments: [
        ("al", goodPassphrase, goodPassphrase, VaultAccountError.invalidUsername),
        ("alice", "short", "short", .passphraseTooShort),
        ("alice", goodPassphrase, goodPassphrase + "x", .passphraseMismatch),
    ])
    func prepareValidates(username: String, passphrase: String, confirmation: String, expected: VaultAccountError) async {
        let server = FakeVault()
        let model = await checked(server)
        await model.prepareAccount(username: username, passphrase: passphrase, confirmation: confirmation)
        #expect(model.error == expected)
        #expect(model.pendingRecoveryKey == nil)
    }

    @Test("a closed registration stops before deriving anything")
    func closedRegistration() async {
        let server = FakeVault()
        server.registrationOpen = false
        let model = await checked(server)
        await model.prepareAccount(username: "alice", passphrase: goodPassphrase, confirmation: goodPassphrase)
        #expect(model.error == .registrationClosed)
        #expect(model.pendingRecoveryKey == nil)
    }

    @Test("a taken username returns to the form, a network failure keeps the prepared account")
    func registrationFailures() async {
        let server = FakeVault()
        await createAccount(on: await checked(server), username: "alice")

        let taken = await checked(server)
        await taken.prepareAccount(username: "alice", passphrase: goodPassphrase, confirmation: goodPassphrase)
        await taken.registerPreparedAccount()
        #expect(taken.error == .usernameTaken)
        #expect(taken.pendingRecoveryKey == nil)
        #expect(taken.phase == .signedOut)

        let flaky = await checked(server)
        await flaky.prepareAccount(username: "bob", passphrase: goodPassphrase, confirmation: goodPassphrase)
        server.offline = true
        await flaky.registerPreparedAccount()
        #expect(flaky.error == .offline)
        #expect(flaky.pendingRecoveryKey != nil)
        server.offline = false
        await flaky.registerPreparedAccount()
        #expect(flaky.phase != .signedOut)
    }

    @Test("cancelling forgets the prepared account")
    func discard() async {
        let model = await checked(FakeVault())
        await model.prepareAccount(username: "alice", passphrase: goodPassphrase, confirmation: goodPassphrase)
        model.discardPendingAccount()
        #expect(model.pendingRecoveryKey == nil)
        await model.registerPreparedAccount()
        #expect(model.phase == .signedOut)
    }

    // MARK: Log in

    @Test("a second phone logs in with the passphrase and opens the same keys")
    func loginOnANewDevice() async throws {
        let server = FakeVault()
        let firstSecrets = MemorySecrets()
        await createAccount(on: await checked(server, secrets: firstSecrets))

        let secondSecrets = MemorySecrets()
        let second = await checked(server, secrets: secondSecrets)
        await second.login(username: "Alice", passphrase: goodPassphrase)
        #expect(second.error == nil)
        #expect(second.phase != .signedOut)

        let store = VaultSessionStore.self
        let a = try #require(store.init(secrets: firstSecrets).load())
        let b = try #require(store.init(secrets: secondSecrets).load())
        #expect(a.userKey == b.userKey)
        #expect(a.inboxPublicKey == b.inboxPublicKey)
        #expect(a.apiKey != b.apiKey)
    }

    @Test("a wrong passphrase links nothing")
    func wrongPassphrase() async {
        let server = FakeVault()
        await createAccount(on: await checked(server))
        let secrets = MemorySecrets()
        let model = await checked(server, secrets: secrets)
        await model.login(username: "alice", passphrase: "wrong passphrase here")
        #expect(model.error == .invalidCredentials)
        #expect(model.phase == .signedOut)
        #expect((try? secrets.read()) ?? nil == nil)
    }

    @Test("a lockout carries the seconds the server asked for")
    func lockout() async {
        let server = FakeVault()
        server.lockedFor = 600
        let model = await checked(server)
        await model.login(username: "alice", passphrase: goodPassphrase)
        #expect(model.error == .tooManyAttempts(600))
    }

    @Test("key-derivation settings below the floor are refused before deriving or logging in")
    func weakKdfIsRefused() async {
        let server = FakeVault()
        server.preloginOverride = VaultKdf(
            salt: Data(repeating: 1, count: 16).base64EncodedString(), opslimit: 1, memlimit: 8 * 1024 * 1024)
        let model = await checked(server)
        await model.login(username: "alice", passphrase: goodPassphrase)
        #expect(model.error == .unsafeKdf)
        #expect(server.loginCalls == 0)
    }

    @Test("a keyring that cannot be read revokes the device key the server just issued")
    func unreadableKeyringRevokesTheKey() async {
        let server = FakeVault()
        await createAccount(on: await checked(server))
        server.corruptKeyring = true
        let secrets = MemorySecrets()
        let model = await checked(server, secrets: secrets)
        await model.login(username: "alice", passphrase: goodPassphrase)
        #expect(model.error == .keyringUnreadable)
        #expect(server.revoked.count == 1)
        #expect((try? secrets.read()) ?? nil == nil)
    }

    @Test("a Keychain that refuses the session revokes the key and reports it")
    func keychainFailure() async {
        let server = FakeVault()
        await createAccount(on: await checked(server))
        let secrets = MemorySecrets()
        secrets.failWrites = true
        let model = await checked(server, secrets: secrets)
        await model.login(username: "alice", passphrase: goodPassphrase)
        #expect(model.error == .keychain)
        #expect(model.phase == .signedOut)
        #expect(server.revoked.count == 1)
    }

    @Test("login needs a checked server and a valid username")
    func loginPreconditions() async {
        let server = FakeVault()
        let unchecked = makeModel(server)
        await unchecked.login(username: "alice", passphrase: goodPassphrase)
        #expect(unchecked.error == .invalidServerURL)

        let model = await checked(server)
        await model.login(username: "a b", passphrase: goodPassphrase)
        #expect(model.error == .invalidUsername)
        #expect(server.loginCalls == 0)
    }

    // MARK: Sign out and erase

    @Test("logging out revokes the device key and wipes the phone")
    func logout() async {
        let server = FakeVault()
        let secrets = MemorySecrets()
        let model = await checked(server, secrets: secrets)
        await createAccount(on: model)

        let reached = await model.logout()
        #expect(reached)
        #expect(model.phase == .signedOut)
        #expect(server.revoked.count == 1)
        #expect((try? secrets.read()) ?? nil == nil)
    }

    @Test("logging out offline still signs the phone out, and says the server was not told")
    func logoutOffline() async {
        let server = FakeVault()
        let secrets = MemorySecrets()
        let model = await checked(server, secrets: secrets)
        await createAccount(on: model)
        server.offline = true

        let reached = await model.logout()
        #expect(!reached)
        #expect(model.phase == .signedOut)
        #expect((try? secrets.read()) ?? nil == nil)
    }

    @Test("erasing the account needs the passphrase, and a wrong one changes nothing")
    func deleteAccount() async {
        let server = FakeVault()
        let secrets = MemorySecrets()
        let model = await checked(server, secrets: secrets)
        await createAccount(on: model)

        await model.deleteAccount(passphrase: "not the passphrase")
        #expect(model.error == .invalidCredentials)
        #expect(model.phase != .signedOut)
        #expect(server.accountCount == 1)

        await model.deleteAccount(passphrase: goodPassphrase)
        #expect(model.error == nil)
        #expect(model.phase == .signedOut)
        #expect(server.accountCount == 0)
        #expect((try? secrets.read()) ?? nil == nil)
    }

    // MARK: Launch

    @Test("a relaunch restores the linked session")
    func restoresSession() async {
        let server = FakeVault()
        let secrets = MemorySecrets()
        await createAccount(on: await checked(server, secrets: secrets))

        let relaunched = makeModel(server, secrets: secrets, launched: true)
        #expect(relaunched.phase == .signedIn(VaultAccountSummary(username: "alice", serverURL: URL(string: serverURL)!)))
    }

    @Test("a fresh install does not inherit a session left in the Keychain")
    func freshInstallStartsSignedOut() async {
        let server = FakeVault()
        let secrets = MemorySecrets()
        await createAccount(on: await checked(server, secrets: secrets))

        let install = MemoryInstall(launched: false)
        let model = VaultAccountModel(
            deviceLabel: "iPhone", makeServer: { _ in server }, sessions: VaultSessionStore(secrets: secrets),
            install: install, rememberServerURL: { _ in })
        #expect(model.phase == .signedOut)
        #expect((try? secrets.read()) ?? nil == nil)
        #expect(install.hasLaunchedBefore)
    }
}
