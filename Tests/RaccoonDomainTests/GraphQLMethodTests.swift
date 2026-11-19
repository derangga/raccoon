import RaccoonDomain
import Testing

struct GraphQLMethodTests {
    @Test(arguments: [
        ("GET", "POST"), ("HEAD", "POST"), ("get", "POST"), ("head", "POST"),
        ("POST", "POST"), ("PUT", "PUT"), ("PATCH", "PATCH"), ("DELETE", "DELETE"), ("OPTIONS", "OPTIONS"), ("PURGE", "PURGE"),
    ])
    func `picking GraphQL turns GET and HEAD into POST and keeps any other method`(method: String, result: String) {
        #expect(GraphQLMethod.forPick(method) == result)
    }
}
