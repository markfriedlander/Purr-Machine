// LocalAPIServer.swift
// Purr Machine
//
// Local HTTP/JSON API for Purr Machine. NWListener-based, bearer-token auth,
// no dependencies. Modeled on the Hal Universal LocalAPIServer pattern.
//
// Purr Machine API port: 8767  (Posey=8765, Hal=8766, PurrMachine=8767)
//
// On first launch a random token is generated and stored in the Keychain. On
// each app launch the API prints "<host>:<port>:<token>" to the console and
// copies the same string to the pasteboard so Mark can hand it to CC.
//
// API surface — every endpoint except /health requires
//   Authorization: Bearer <token>
//
//   GET  /health                 — liveness, no auth
//   GET  /state                  — full state snapshot
//   POST /kitten/select          — {"name": "Floozy"} or {"tag": 1}
//   POST /play                   — {"name": "Floozy"} (optional, defaults to selected)
//   POST /stop                   — stop playback + haptics
//   POST /timer/cycle            — same as tapping the timer button
//   POST /timer/set              — {"index": 0..3} or {"seconds": 600|1200|1800|-1}
//   POST /haptics/pattern        — full arbitrary CHHapticPattern (events + curves)
//   POST /haptics/dynamic        — {"intensity": 0..1, "sharpness": 0..1}
//   POST /haptics/stop           — stop haptics only, leave audio playing
//
// All mutating endpoints return the new /state snapshot.

import Foundation
import Network
import Security
import UIKit
import CoreHaptics

// ========== BLOCK 1: LocalAPIServer - lifecycle + token + address - START ==========
final class LocalAPIServer {

    /// Process-wide singleton. The toolbar antenna toggle, SceneDelegate, and
    /// API handlers all reach the same instance through `.shared`.
    static let shared = LocalAPIServer()

    static let apiPort: UInt16 = 8767

    private var listener: NWListener?

    var isRunning: Bool { listener != nil }

    /// Synthesized at any time from local IP + port + Keychain token. Safe to
    /// read before the listener reaches `.ready` — we know the values up front.
    var connectionInfo: String {
        "\(Self.localIPAddress()):\(Self.apiPort):\(Self.loadOrCreateToken())"
    }

    // --- Token storage (Keychain) ---
    private static let keychainService = "com.HeatherAndMark.PurrMachine"
    private static let keychainAccount = "localAPIToken"

    static func loadOrCreateToken() -> String {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService as CFString,
            kSecAttrAccount: keychainAccount as CFString,
            kSecReturnData:  true,
        ]
        var item: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let add: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService as CFString,
            kSecAttrAccount: keychainAccount as CFString,
            kSecValueData:   Data(token.utf8) as CFData,
        ]
        SecItemAdd(add as CFDictionary, nil)
        return token
    }

    private var apiToken: String { Self.loadOrCreateToken() }

    // --- Local Wi-Fi IP discovery ---
    //
    // Prefers `en0` (iPhone Wi-Fi) over any other `en*` interface, and prefers
    // a real routable IP (10/8, 172.16/12, 192.168/16) over a link-local
    // (169.254/16) address. The link-local block is what iOS hands out for
    // its USB-Ethernet tether to the Mac — we want to advertise the Wi-Fi
    // address so the API is reachable from any host on the LAN, not just the
    // Mac via cable.
    static func localIPAddress() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "127.0.0.1" }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(name: String, ip: String)] = []
        var ptr = ifaddr
        while let iface = ptr?.pointee {
            defer { ptr = ptr?.pointee.ifa_next }
            guard iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: iface.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: hostname)
            guard !ip.isEmpty, ip != "0.0.0.0" else { continue }
            candidates.append((name, ip))
        }

        func score(_ c: (name: String, ip: String)) -> Int {
            var s = 0
            if c.name == "en0"            { s += 100 }       // Wi-Fi on iPhone
            if !c.ip.hasPrefix("169.254") { s += 50  }       // routable beats link-local
            if c.ip.hasPrefix("192.168")
               || c.ip.hasPrefix("10.")
               || c.ip.hasPrefix("172.")  { s += 10  }
            return s
        }

        return candidates.max(by: { score($0) < score($1) })?.ip ?? "127.0.0.1"
    }

    var connectionURL: String { "\(Self.localIPAddress()):\(Self.apiPort)" }

    func start() {
        guard !isRunning else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.apiPort)!)
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global(qos: .userInitiated))
                Task { await self?.handleConnection(conn) }
            }
            l.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let info = self.connectionInfo
                    print("PurrAPI: Ready — \(info)")
                    DispatchQueue.main.async {
                        UIPasteboard.general.string = info
                        Self.writeConnectionFile(info)
                    }
                case .failed(let e):
                    print("PurrAPI: Failed — \(e)")
                default:
                    break
                }
            }
            l.start(queue: .global(qos: .userInitiated))
            listener = l
        } catch {
            print("PurrAPI: Could not start NWListener — \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        print("PurrAPI: Stopped")
    }

    /// Write the connection info to `Documents/api_connection.txt`. On the
    /// iOS Simulator this file is readable from the Mac at
    ///   ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<APP>/Documents/api_connection.txt
    /// On a physical device the file is sandboxed; the alert + clipboard
    /// remain the developer-facing surfaces there.
    private static func writeConnectionFile(_ info: String) {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent("api_connection.txt")
        try? info.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
// ========== BLOCK 1: LocalAPIServer - lifecycle + token + address - END ==========

// ========== BLOCK 2: LocalAPIServer - HTTP parsing - START ==========
extension LocalAPIServer {

    fileprivate struct ParsedRequest {
        let method: String
        let path: String
        let token: String?
        let body: Data?
    }

    fileprivate func handleConnection(_ conn: NWConnection) async {
        guard let data = await receiveRequest(conn),
              let req  = parseRequest(data) else {
            respond(conn, status: 400, body: "{\"error\":\"Bad request\"}")
            return
        }
        if req.path == "/health" {
            let body = "{\"ok\":true,\"app\":\"PurrMachine\",\"port\":\(Self.apiPort)}"
            respond(conn, status: 200, body: body)
            return
        }
        guard req.token == apiToken else {
            respond(conn, status: 401, body: "{\"error\":\"Unauthorized\"}")
            return
        }
        let (status, body) = await route(req)
        respond(conn, status: status, body: body)
    }

    fileprivate func receiveRequest(_ conn: NWConnection) async -> Data? {
        await withCheckedContinuation { cont in
            var buf = Data()
            func next() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { chunk, _, done, err in
                    if let chunk { buf.append(chunk) }
                    if let text = String(data: buf, encoding: .utf8), text.contains("\r\n\r\n") {
                        let parts = text.components(separatedBy: "\r\n\r\n")
                        let hdr   = parts[0]
                        let body  = parts.dropFirst().joined(separator: "\r\n\r\n")
                        if let clLine = hdr.components(separatedBy: "\r\n")
                            .first(where: { $0.lowercased().hasPrefix("content-length:") }),
                           let cl = Int(clLine.components(separatedBy: ":").last?
                                            .trimmingCharacters(in: .whitespaces) ?? "") {
                            if body.utf8.count >= cl { cont.resume(returning: buf); return }
                        } else {
                            cont.resume(returning: buf); return
                        }
                    }
                    if done || err != nil { cont.resume(returning: buf.isEmpty ? nil : buf) }
                    else { next() }
                }
            }
            next()
        }
    }

    fileprivate func parseRequest(_ data: Data) -> ParsedRequest? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let split = text.components(separatedBy: "\r\n\r\n")
        guard let hdrBlock = split.first else { return nil }
        let lines = hdrBlock.components(separatedBy: "\r\n")
        guard let reqLine = lines.first else { return nil }
        let rp = reqLine.components(separatedBy: " ")
        guard rp.count >= 2 else { return nil }
        var token: String?
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("authorization: bearer ") {
                token = String(line.dropFirst("authorization: bearer ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        let bodyStr  = split.dropFirst().joined(separator: "\r\n\r\n")
        let bodyData = bodyStr.isEmpty ? nil : bodyStr.data(using: .utf8)
        return ParsedRequest(method: rp[0], path: rp[1], token: token, body: bodyData)
    }

    fileprivate func respond(_ conn: NWConnection, status: Int, body: String) {
        let phrase: String
        switch status {
        case 200: phrase = "OK"
        case 400: phrase = "Bad Request"
        case 401: phrase = "Unauthorized"
        case 404: phrase = "Not Found"
        case 500: phrase = "Internal Server Error"
        case 503: phrase = "Service Unavailable"
        default:  phrase = "Error"
        }
        let bodyData = body.data(using: .utf8) ?? Data()
        let header = "HTTP/1.1 \(status) \(phrase)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var resp = header.data(using: .utf8)!
        resp.append(bodyData)
        conn.send(content: resp, completion: .contentProcessed { _ in conn.cancel() })
    }
}
// ========== BLOCK 2: LocalAPIServer - HTTP parsing - END ==========

// ========== BLOCK 3: LocalAPIServer - routing - START ==========
extension LocalAPIServer {

    fileprivate func route(_ req: ParsedRequest) async -> (Int, String) {
        switch (req.method, req.path) {
        case ("GET",  "/state"):           return await handleState()
        case ("POST", "/kitten/select"):   return await handleKittenSelect(body: req.body)
        case ("POST", "/play"):            return await handlePlay(body: req.body)
        case ("POST", "/stop"):            return await handleStop()
        case ("POST", "/timer/cycle"):     return await handleTimerCycle()
        case ("POST", "/timer/set"):       return await handleTimerSet(body: req.body)
        case ("POST", "/haptics/pattern"): return await handleHapticsPattern(body: req.body)
        case ("POST", "/haptics/dynamic"): return await handleHapticsDynamic(body: req.body)
        case ("POST", "/haptics/stop"):    return await handleHapticsStop()
        default:                           return (404, "{\"error\":\"Not found\"}")
        }
    }

    private func stateJSONString() async -> String {
        await MainActor.run {
            let snap = AppState.shared.snapshotDictionary()
            return Self.serialize(snap)
        }
    }

    private static func serialize(_ obj: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "{}"
    }
}
// ========== BLOCK 3: LocalAPIServer - routing - END ==========

// ========== BLOCK 4: LocalAPIServer - simple handlers - START ==========
extension LocalAPIServer {

    fileprivate func handleState() async -> (Int, String) {
        (200, await stateJSONString())
    }

    fileprivate func handleStop() async -> (Int, String) {
        await MainActor.run { AppState.shared.stop() }
        return (200, await stateJSONString())
    }

    fileprivate func handleTimerCycle() async -> (Int, String) {
        await MainActor.run { _ = AppState.shared.cycleTimer() }
        return (200, await stateJSONString())
    }

    fileprivate func handleHapticsStop() async -> (Int, String) {
        await MainActor.run { AppState.shared.stopHapticsOnly() }
        return (200, await stateJSONString())
    }

    fileprivate func handleKittenSelect(body: Data?) async -> (Int, String) {
        guard let json = Self.parseJSONObject(body) else {
            return (400, "{\"error\":\"Body must be JSON object\"}")
        }
        let kitten: Kitten?
        if let name = json["name"] as? String { kitten = Kitten.from(name: name) }
        else if let tag = json["tag"] as? Int { kitten = Kitten(rawValue: tag) }
        else { return (400, "{\"error\":\"Provide 'name' or 'tag'\"}") }
        guard let k = kitten else { return (400, "{\"error\":\"Unknown kitten\"}") }
        await MainActor.run { AppState.shared.toggle(k) }
        return (200, await stateJSONString())
    }

    fileprivate func handlePlay(body: Data?) async -> (Int, String) {
        let target: Kitten? = {
            guard let json = Self.parseJSONObject(body) else { return nil }
            if let name = json["name"] as? String { return Kitten.from(name: name) }
            if let tag  = json["tag"]  as? Int    { return Kitten(rawValue: tag) }
            return nil
        }()
        await MainActor.run {
            let kitten = target ?? AppState.shared.selectedKitten
            AppState.shared.play(kitten)
        }
        return (200, await stateJSONString())
    }

    fileprivate func handleTimerSet(body: Data?) async -> (Int, String) {
        guard let json = Self.parseJSONObject(body) else {
            return (400, "{\"error\":\"Body must be JSON object\"}")
        }
        if let index = json["index"] as? Int {
            let (ok, count): (Bool, Int) = await MainActor.run {
                let opts = AppState.shared.timerOptions
                return (opts.indices.contains(index), opts.count)
            }
            guard ok else {
                return (400, "{\"error\":\"index out of range 0..\(count - 1)\"}")
            }
            await MainActor.run { AppState.shared.setTimerIndex(index) }
            return (200, await stateJSONString())
        }
        if let seconds = json["seconds"] as? Int {
            let result: (idx: Int?, opts: [Int]) = await MainActor.run {
                let opts = AppState.shared.timerOptions
                return (opts.firstIndex(of: seconds), opts)
            }
            guard let idx = result.idx else {
                return (400, "{\"error\":\"seconds must be one of \(result.opts)\"}")
            }
            await MainActor.run { AppState.shared.setTimerIndex(idx) }
            return (200, await stateJSONString())
        }
        return (400, "{\"error\":\"Provide 'index' or 'seconds'\"}")
    }

    private static func parseJSONObject(_ body: Data?) -> [String: Any]? {
        guard let body else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}
// ========== BLOCK 4: LocalAPIServer - simple handlers - END ==========

// ========== BLOCK 5: LocalAPIServer - haptic pattern decoding - START ==========
extension LocalAPIServer {

    fileprivate func handleHapticsDynamic(body: Data?) async -> (Int, String) {
        guard let json = Self.parseJSONObject(body) else {
            return (400, "{\"error\":\"Body must be JSON object\"}")
        }
        let intensity = (json["intensity"] as? NSNumber).map { $0.floatValue }
        let sharpness = (json["sharpness"] as? NSNumber).map { $0.floatValue }
        if intensity == nil && sharpness == nil {
            return (400, "{\"error\":\"Provide 'intensity' and/or 'sharpness'\"}")
        }
        do {
            try await MainActor.run {
                try AppState.shared.sendDynamicHaptic(intensity: intensity, sharpness: sharpness)
            }
            return (200, await stateJSONString())
        } catch {
            return (500, "{\"error\":\"\(Self.jsonEscape(error.localizedDescription))\"}")
        }
    }

    fileprivate func handleHapticsPattern(body: Data?) async -> (Int, String) {
        guard let json = Self.parseJSONObject(body) else {
            return (400, "{\"error\":\"Body must be JSON object\"}")
        }
        let rawEvents  = (json["events"]  as? [[String: Any]]) ?? []
        let rawCurves  = (json["parameterCurves"] as? [[String: Any]]) ?? []
        let rawDynamic = (json["dynamicParameters"] as? [[String: Any]]) ?? []
        let events:  [CHHapticEvent]
        let curves:  [CHHapticParameterCurve]
        let dynamic: [CHHapticDynamicParameter]
        do {
            events  = try rawEvents.map { try Self.decodeEvent($0) }
            curves  = try rawCurves.map { try Self.decodeCurve($0) }
            dynamic = try rawDynamic.map { try Self.decodeDynamic($0) }
        } catch {
            return (400, "{\"error\":\"\(Self.jsonEscape(error.localizedDescription))\"}")
        }
        if events.isEmpty {
            return (400, "{\"error\":\"At least one event required\"}")
        }
        do {
            try await MainActor.run {
                try AppState.shared.playAPIHapticPattern(
                    events: events, parameterCurves: curves, dynamicParameters: dynamic
                )
            }
            return (200, await stateJSONString())
        } catch {
            return (500, "{\"error\":\"\(Self.jsonEscape(error.localizedDescription))\"}")
        }
    }

    private static func decodeEvent(_ dict: [String: Any]) throws -> CHHapticEvent {
        let typeStr = (dict["type"] as? String ?? "continuous").lowercased()
        let eventType: CHHapticEvent.EventType
        switch typeStr {
        case "continuous":          eventType = .hapticContinuous
        case "transient", "tap":    eventType = .hapticTransient
        default: throw apiError("Unknown event type '\(typeStr)' — use 'continuous' or 'transient'")
        }
        let time     = (dict["time"]     as? NSNumber)?.doubleValue ?? 0
        let duration = (dict["duration"] as? NSNumber)?.doubleValue ?? 0
        var params: [CHHapticEventParameter] = []
        if let v = (dict["intensity"] as? NSNumber)?.floatValue {
            params.append(CHHapticEventParameter(parameterID: .hapticIntensity, value: v))
        }
        if let v = (dict["sharpness"] as? NSNumber)?.floatValue {
            params.append(CHHapticEventParameter(parameterID: .hapticSharpness, value: v))
        }
        if let v = (dict["attackTime"]   as? NSNumber)?.floatValue {
            params.append(CHHapticEventParameter(parameterID: .attackTime,   value: v))
        }
        if let v = (dict["decayTime"]    as? NSNumber)?.floatValue {
            params.append(CHHapticEventParameter(parameterID: .decayTime,    value: v))
        }
        if let v = (dict["releaseTime"]  as? NSNumber)?.floatValue {
            params.append(CHHapticEventParameter(parameterID: .releaseTime,  value: v))
        }
        if let v = (dict["sustained"]    as? NSNumber)?.floatValue {
            params.append(CHHapticEventParameter(parameterID: .sustained,    value: v))
        }
        if eventType == .hapticContinuous {
            return CHHapticEvent(eventType: eventType, parameters: params,
                                 relativeTime: time, duration: duration)
        } else {
            return CHHapticEvent(eventType: eventType, parameters: params, relativeTime: time)
        }
    }

    private static func decodeCurve(_ dict: [String: Any]) throws -> CHHapticParameterCurve {
        guard let pStr = dict["parameter"] as? String else {
            throw apiError("Curve missing 'parameter'")
        }
        let pid: CHHapticDynamicParameter.ID
        switch pStr {
        case "HapticIntensityControl": pid = .hapticIntensityControl
        case "HapticSharpnessControl": pid = .hapticSharpnessControl
        case "HapticAttackTimeControl":  pid = .hapticAttackTimeControl
        case "HapticDecayTimeControl":   pid = .hapticDecayTimeControl
        case "HapticReleaseTimeControl": pid = .hapticReleaseTimeControl
        default: throw apiError("Unknown curve parameter '\(pStr)'")
        }
        let time = (dict["time"] as? NSNumber)?.doubleValue ?? 0
        guard let points = dict["controlPoints"] as? [[String: Any]], !points.isEmpty else {
            throw apiError("Curve requires non-empty 'controlPoints'")
        }
        let cps: [CHHapticParameterCurve.ControlPoint] = try points.map { p in
            guard let t = (p["time"]  as? NSNumber)?.doubleValue,
                  let v = (p["value"] as? NSNumber)?.floatValue else {
                throw apiError("Control point requires 'time' and 'value'")
            }
            return CHHapticParameterCurve.ControlPoint(relativeTime: t, value: v)
        }
        return CHHapticParameterCurve(parameterID: pid, controlPoints: cps, relativeTime: time)
    }

    private static func decodeDynamic(_ dict: [String: Any]) throws -> CHHapticDynamicParameter {
        guard let pStr = dict["parameter"] as? String,
              let v = (dict["value"] as? NSNumber)?.floatValue else {
            throw apiError("Dynamic parameter requires 'parameter' and 'value'")
        }
        let time = (dict["time"] as? NSNumber)?.doubleValue ?? 0
        let pid: CHHapticDynamicParameter.ID
        switch pStr {
        case "HapticIntensityControl": pid = .hapticIntensityControl
        case "HapticSharpnessControl": pid = .hapticSharpnessControl
        case "HapticAttackTimeControl":  pid = .hapticAttackTimeControl
        case "HapticDecayTimeControl":   pid = .hapticDecayTimeControl
        case "HapticReleaseTimeControl": pid = .hapticReleaseTimeControl
        default: throw apiError("Unknown dynamic parameter '\(pStr)'")
        }
        return CHHapticDynamicParameter(parameterID: pid, value: v, relativeTime: time)
    }

    private static func apiError(_ msg: String) -> NSError {
        NSError(domain: "PurrMachine.API", code: 400,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }

    private static func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
    }
}
// ========== BLOCK 5: LocalAPIServer - haptic pattern decoding - END ==========
