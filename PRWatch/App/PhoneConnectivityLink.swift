//
//  PhoneConnectivityLink.swift
//  PRWatch
//
//  SCRUM-255: lado reloj del puente con WatchConnectivity (DG-1). Lo que el reloj manda va por
//  `transferUserInfo`: se entrega en orden aunque el iPhone esté apagado o lejos.
//
//  `@unchecked Sendable`: WCSession no está marcado Sendable, pero Apple documenta su uso
//  desde cualquier hilo. Esta clase no guarda estado mutable propio.
//

import Foundation
import PRCore
import PRDomain
import WatchConnectivity

nonisolated final class PhoneConnectivityLink: NSObject, WatchWorkoutLink, WCSessionDelegate, @unchecked Sendable {
    private static let payloadKey = "payload"

    let snapshots: AsyncStream<WatchSessionSnapshot>
    private let continuation: AsyncStream<WatchSessionSnapshot>.Continuation
    private let session: WCSession
    private let logger = PRLogger(category: .sync)

    init(session: WCSession = .default) {
        self.session = session
        (snapshots, continuation) = AsyncStream.makeStream(of: WatchSessionSnapshot.self)
        super.init()
        session.delegate = self
        session.activate()
    }

    /// Antes de activarse no se manda: el buzón del reloj lo reenvía después.
    func send(_ message: WatchMessage) async {
        guard session.activationState == .activated else { return }
        do {
            session.transferUserInfo([Self.payloadKey: try WatchWireCodec.encode(message)])
        } catch {
            logger.diagnostic("watch.send.failed", level: .error)
        }
    }

    /// Al activarse trae el último estado que el iPhone publicó mientras no había conexión.
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        receive(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        receive(context)
    }

    private func receive(_ context: [String: Any]) {
        guard let data = context[Self.payloadKey] as? Data else { return }
        do {
            continuation.yield(try WatchWireCodec.decode(WatchSessionSnapshot.self, from: data))
        } catch {
            logger.diagnostic("watch.snapshot.unreadable", level: .error)
        }
    }
}
