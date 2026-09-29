import Foundation
import JavaScriptCore

enum EngineError: Error, Equatable, Sendable {
    /// engines.js is missing from the bundle.
    case bundleNotFound
    /// The script or an engine function threw. `message` is the JavaScript error's description.
    case javaScriptException(message: String)
    /// The engine returned something that is not JSON (e.g. undefined).
    case invalidResult(function: String)
}

/// Runs the TypeScript game engines (backend/src/engines, bundled as
/// Resources/engines.js) in JavaScriptCore. Arguments and results cross the
/// boundary as JSON. See docs/adr/0011-engines-on-device-javascriptcore.md.
///
/// A JSContext is not thread-safe, so this class is deliberately not Sendable:
/// create and use an instance within one isolation domain.
final class EngineBridge {
    private let context: JSContext
    private let invoke: JSValue
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    convenience init(bundle: Bundle = Bundle(for: EngineBridge.self)) throws {
        guard let url = bundle.url(forResource: "engines", withExtension: "js") else {
            throw EngineError.bundleNotFound
        }
        try self.init(script: String(contentsOf: url, encoding: .utf8))
    }

    /// `script` must define the global `WadEngines`.
    init(script: String) throws {
        guard let context = JSContext() else {
            throw EngineError.javaScriptException(message: "could not create a JavaScript context")
        }
        self.context = context
        context.evaluateScript(script)
        try Self.throwPendingException(in: context)

        let invoke = context.evaluateScript(
            """
            (function (name, argumentsJSON) {
              var fn = WadEngines[name];
              if (typeof fn !== "function") throw new Error("unknown engine function: " + name);
              return JSON.stringify(fn.apply(null, JSON.parse(argumentsJSON)));
            })
            """
        )
        try Self.throwPendingException(in: context)
        guard let invoke, !invoke.isUndefined else {
            throw EngineError.javaScriptException(message: "could not install the engine call helper")
        }
        self.invoke = invoke
    }

    func scoreSkins(_ input: Engine.SkinsInput) throws -> Engine.SkinsResult {
        try call("scoreSkins", arguments: [input])
    }

    func scoreWad(_ input: Engine.WadInput) throws -> Engine.WadResult {
        try call("scoreWad", arguments: [input])
    }

    func scoreGreenies(_ input: Engine.GreeniesInput) throws -> Engine.GreeniesResult {
        try call("scoreGreenies", arguments: [input])
    }

    /// Ticks per player, keyed by user id and then hole number.
    func allocateTicks(players: [Engine.Player], holes: [Engine.HoleInfo]) throws -> [Engine.UserID: Engine.TicksByHole] {
        try call("allocateTicks", arguments: [players, holes])
    }

    /// Nets the per-game deltas into positions and pairwise transfers.
    func settle(_ gameDeltas: [Engine.Deltas]) throws -> Engine.Settlement {
        try call("settle", arguments: gameDeltas)
    }

    private func call<Result: Decodable>(_ function: String, arguments: [any Encodable]) throws -> Result {
        let encoded = try arguments.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        let argumentsJSON = "[" + encoded.joined(separator: ",") + "]"

        let result = invoke.call(withArguments: [function, argumentsJSON])
        try Self.throwPendingException(in: context)
        guard let result, result.isString, let json = result.toString() else {
            throw EngineError.invalidResult(function: function)
        }
        return try decoder.decode(Result.self, from: Data(json.utf8))
    }

    private static func throwPendingException(in context: JSContext) throws {
        guard let exception = context.exception else { return }
        context.exception = nil
        throw EngineError.javaScriptException(message: exception.toString() ?? "unknown JavaScript exception")
    }
}
