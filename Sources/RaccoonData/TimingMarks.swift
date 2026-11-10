import Foundation
import RaccoonDomain

extension Timing.Marks {
    /// A field copy of one transaction: no rule, so nothing here to get wrong but a name.
    init(_ transaction: URLSessionTaskTransactionMetrics) {
        self.init()
        fetchStart = transaction.fetchStartDate
        domainLookupStart = transaction.domainLookupStartDate
        domainLookupEnd = transaction.domainLookupEndDate
        connectStart = transaction.connectStartDate
        connectEnd = transaction.connectEndDate
        secureConnectionStart = transaction.secureConnectionStartDate
        secureConnectionEnd = transaction.secureConnectionEndDate
        requestStart = transaction.requestStartDate
        requestEnd = transaction.requestEndDate
        responseStart = transaction.responseStartDate
        responseEnd = transaction.responseEndDate
        reusedConnection = transaction.isReusedConnection
        protocolName = transaction.networkProtocolName
        remoteAddress = transaction.remoteAddress
        remotePort = transaction.remotePort
        tlsVersion = transaction.negotiatedTLSProtocolVersion?.rawValue
        // The encoded count: URLSession undoes Content-Encoding before Raccoon sees the body (environment-facts.md).
        bodyBytesOnWire = Int(transaction.countOfResponseBodyBytesReceived)
    }
}
