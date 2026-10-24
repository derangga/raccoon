import RaccoonDomain
import RaccoonTesting
import Synchronization

/// An in-memory Keychain that can be told to refuse one operation, and counts its reads.
final class FlakySecretStore: SecretStore {
    enum Operation: Hashable { case get, set, delete }

    let inner = InMemorySecretStore()
    private let refusals = Mutex<[Operation: SecretError]>([:])
    private let getCount = Mutex(0)

    func refuse(_ operation: Operation, with error: SecretError?) {
        refusals.withLock { $0[operation] = error }
    }

    var gets: Int { getCount.withLock { $0 } }

    private func check(_ operation: Operation) throws(SecretError) {
        if let error = refusals.withLock({ $0[operation] }) { throw error }
    }

    func get(environment: String?, name: VariableName) throws(SecretError) -> String? {
        getCount.withLock { $0 += 1 }
        try check(.get)
        return try inner.get(environment: environment, name: name)
    }

    func set(_ value: String, environment: String?, name: VariableName) throws(SecretError) {
        try check(.set)
        try inner.set(value, environment: environment, name: name)
    }

    func delete(environment: String?, name: VariableName) throws(SecretError) {
        try check(.delete)
        try inner.delete(environment: environment, name: name)
    }
}
