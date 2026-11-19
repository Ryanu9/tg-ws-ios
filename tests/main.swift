// Host tests for the Foundation-only part of the WsBridge module (parser, routing, request, store).
// Built on Linux in CI:  swiftc -o wstests <WsBridge sources> tests/main.swift && ./wstests
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

var failures = 0
func check(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}
func eq<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: Int = #line) {
    check(actual == expected, "\(message): expected <\(expected)> got <\(actual)>", line: line)
}

// MARK: - Parser: control frames

eq(WsParser.parse("  ").kind, .ignore, "blank")
eq(WsParser.parse("ping").kind, .ping, "plain ping")
eq(WsParser.parse("PONG").kind, .ping, "plain pong")
eq(WsParser.parse("{\"type\":\"CONNECTED\"}").kind, .connected, "connected")
eq(WsParser.parse("{\"type\":\"heartbeat\"}").kind, .ping, "heartbeat")

// MARK: - Parser: plain text

do {
    let r = WsParser.parse("hello world")
    eq(r.kind, .message, "plain kind")
    eq(r.text, "hello world", "plain text")
    eq(r.images, [], "plain images")
}

// MARK: - Parser: tgpush frame with markdown image + blogger prefix

do {
    let r = WsParser.parse("{\"seq\":42,\"id\":123,\"senderName\":\"bot\",\"content\":\"【Trader Bamp】\\n买入 **BTC** ![img](https://x.com/a.png)\"}")
    eq(r.seq, 42, "seq")
    eq(r.uid ?? "", "123", "numeric id")
    eq(r.sender ?? "", "bot", "sender")
    eq(r.blogger ?? "", "Trader Bamp", "bracket blogger")
    eq(r.images, ["https://x.com/a.png"], "md image")
    eq(r.text, "【Trader Bamp】\n买入 BTC", "text without image and bold markup")
}

// MARK: - Parser: lianyun nested JSON string

do {
    let inner = "{\"eventType\":\"SIGNAL\",\"content\":\"hello __world__\",\"actions\":{\"bloggerName\":\"Alice\",\"sourceMessageId\":\"m1\"},\"occurredAt\":\"2024-05-01T10:00:00.123456+08:00\"}"
    let innerEscaped = inner.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let r = WsParser.parse("{\"type\":\"EVENT\",\"payload\":{\"content\":\"" + innerEscaped + "\"}}")
    eq(r.kind, .message, "nested kind")
    eq(r.blogger ?? "", "Alice", "nested blogger")
    eq(r.eventType ?? "", "SIGNAL", "nested event type")
    eq(r.uid ?? "", "m1|SIGNAL", "uid from sourceMessageId")
    eq(r.text, "hello world", "nested text")
    eq(r.timeMs, 1714528800123, "nested occurredAt")
}

// MARK: - Parser: image arrays, links, bare images

do {
    let r = WsParser.parse("{\"text\":\"t\",\"images\":[{\"url\":\"https://a/b.jpg\"},\"https://c/d.webp\",\"nope\"]}")
    eq(r.images, ["https://a/b.jpg", "https://c/d.webp"], "image array")
    eq(r.text, "t", "image array text")
}
do {
    let r = WsParser.parse("see [docs](https://example.com/x) now")
    eq(r.text, "see docs https://example.com/x now", "md link")
}
do {
    let r = WsParser.parse("pic https://h.io/p.JPG?x=1 end")
    eq(r.images, ["https://h.io/p.JPG?x=1"], "bare image")
    eq(r.text, "pic  end", "bare image removed")
}
do {
    let r = WsParser.parse("a  \n\n\n\nb")
    eq(r.text, "a\n\nb", "whitespace normalisation")
}
do {
    let r = WsParser.parse("{\"foo\":1,\"bar\":2}")
    check(r.text.hasPrefix("（JSON · bar, foo）\n"), "json fallback: \(r.text)")
}
do {
    let r = WsParser.parse("{\"msg\":\"x\",\"card\":{\"kolName\":\"Bob\"}}")
    eq(r.blogger ?? "", "Bob", "card kolName")
}

// MARK: - Time parsing

eq(WsParser.parseTime("1714528800"), 1714528800000, "epoch seconds")
eq(WsParser.parseTime("1714528800123"), 1714528800123, "epoch millis")
eq(WsParser.parseTime("2024-05-01 10:00:00"), 1714528800000, "shanghai local time")
eq(WsParser.parseTime("2024-05-01T02:00:00Z"), 1714528800000, "iso utc")
eq(WsParser.parseTime("2024-05-01T02:00:00.123Z"), 1714528800123, "iso utc millis")
eq(WsParser.parseTime("garbage"), 0, "garbage time")

// MARK: - Routing

do {
    let sub = WsSubscription(id: "sub1", name: "Feed", url: "wss://example.com/ws")
    var r = WsParser.Result()
    r.blogger = "Trader Bamp"
    r.text = "【Trader Bamp】\n买入"
    let t = WsTarget.make(subscription: sub, result: r)
    eq(t.split, true, "split")
    eq(t.title, "Trader Bamp", "split title")
    eq(t.text, "买入", "prefix stripped")
    eq(t.postAuthor ?? "-", "-", "no signature in split channel")
    eq(t.channelId, 1517648324, "split channel id (same as Android)")

    var shared = sub
    shared.splitBySender = false
    let t2 = WsTarget.make(subscription: shared, result: r)
    eq(t2.split, false, "not split")
    eq(t2.title, "Feed", "shared title")
    eq(t2.postAuthor ?? "", "Trader Bamp", "signature")
    eq(t2.text, "【Trader Bamp】\n买入", "text kept")
    eq(t2.channelId, WsTarget.channelId(for: "sub1"), "shared channel id")
}
eq(WsTarget.channelId(for: "abc"), 2146906716, "channel id abc")
eq(WsTarget.channelId(for: "a1b2c3d4|s:博主甲"), 2024996114, "channel id unicode")
eq(WsStore.javaHash("wss://example.com/ws"), 1609103633, "java hash")
eq(WsStore.javaHash("ws://1.2.3.4:8095/ws"), -1353440321, "java hash negative")

// MARK: - Request building

do {
    var sub = WsSubscription(url: " wss://h.io/ws ", token: "Bearer abc d")
    sub.authMode = WsSubscription.authBoth
    sub.extraHeaders = "X-A: 1\n# comment\nbad line\nX-B : two:parts"
    let request = sub.makeRequest(since: 5)
    eq(request?.url?.absoluteString ?? "", "wss://h.io/ws?access_token=abc+d&since=5", "url with token and since")
    eq(request?.value(forHTTPHeaderField: "Authorization") ?? "", "Bearer abc d", "auth header")
    eq(request?.value(forHTTPHeaderField: "X-A") ?? "", "1", "extra header")
    eq(request?.value(forHTTPHeaderField: "X-B") ?? "", "two:parts", "extra header with colon")

    sub.authMode = WsSubscription.authNone
    let plain = sub.makeRequest(since: 0)
    eq(plain?.url?.absoluteString ?? "", "wss://h.io/ws", "no token, no since")
    check(plain?.value(forHTTPHeaderField: "Authorization") == nil, "no auth header")

    eq(WsSubscription(url: "").makeRequest(since: 0) == nil, true, "empty url")
    eq(WsSubscription(url: "ftp://x").makeRequest(since: 0) == nil, true, "bad scheme")
}

// MARK: - Subscription coding (tolerant of missing keys)

do {
    let data = "[{\"id\":\"x1\",\"url\":\"ws://a\"}]".data(using: .utf8)!
    let list = try! JSONDecoder().decode([WsSubscription].self, from: data)
    eq(list.count, 1, "decoded count")
    eq(list[0].enabled, true, "default enabled")
    eq(list[0].splitBySender, true, "default split")
    eq(list[0].authMode, WsSubscription.authHeader, "default auth")
    eq(list[0].displayName, WsSubscription.defaultName, "default name")
}

// MARK: - Store

do {
    let suite = "wsbridge-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = WsStore(defaults: defaults)
    eq(store.subscriptions.count, 0, "empty store")
    let sub = WsSubscription(id: "s1", url: "wss://example.com/ws")
    store.upsert(sub)
    eq(store.subscriptions.map { $0.id }, ["s1"], "upsert")
    eq(store.lastSeq(sub), 0, "initial seq")
    store.updateSeq(sub, 10)
    store.updateSeq(sub, 7)
    eq(store.lastSeq(sub), 10, "seq only grows")
    var moved = sub
    moved.url = "wss://other/ws"
    eq(store.lastSeq(moved), 0, "seq is per url")

    eq(store.checkAndMarkSeen(subscriptionId: "s1", uid: "u1"), false, "first uid")
    eq(store.checkAndMarkSeen(subscriptionId: "s1", uid: "u1"), true, "duplicate uid")
    eq(store.checkAndMarkSeen(subscriptionId: "s1", uid: nil), false, "nil uid never dedups")
    for i in 0 ..< 1600 {
        _ = store.checkAndMarkSeen(subscriptionId: "s1", uid: "n\(i)")
    }
    eq(store.checkAndMarkSeen(subscriptionId: "s1", uid: "u1"), false, "old uid evicted after 1500")
    store.persistSeen()
    let reloaded = WsStore(defaults: defaults)
    eq(reloaded.checkAndMarkSeen(subscriptionId: "s1", uid: "n1599"), true, "seen persisted")
    store.remove(id: "s1")
    eq(store.subscriptions.count, 0, "remove")
    defaults.removePersistentDomain(forName: suite)
}

if failures > 0 {
    print("\(failures) check(s) failed")
    exit(1)
}
print("all WsBridge host tests passed")
