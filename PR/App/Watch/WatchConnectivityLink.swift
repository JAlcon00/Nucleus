//
//  WatchConnectivityLink.swift
//  PR
//
//  SCRUM-255: lado iPhone del puente con WatchConnectivity (DG-1). El estado va por
//  `updateApplicationContext`, que sólo guarda el más reciente; lo del reloj llega por
//  `transferUserInfo`, una cola que se entrega en orden aunque la app esté cerrada.
//
//  `@unchecked Sendable`: WCSession no está marcado Sendable, pero Apple documenta su uso
//  desde cualquier hilo; lo mutable de esta clase va protegido por `lock`.
//

import Foundation
import PRCore
import PRDomain
import WatchConnectivity

nonisolated final class WatchConnectivityLink: NSObject, PhoneWorkoutLink, WCSessionDelegate, @unchecked Sendable {
    /// La clave con la que viajan los bytes en los dos sentidos.
    static let payloadKey = "payload"

    let messages: AsyncStream<WatchMessage>
    private let continuation: AsyncStream<WatchMessage>.Continuation
    private let session: WCSession
    private let logger = PRLogger(category: .sync)
    private let lock = NSLock()
    /// Lo último publicado: si la sesión aún no estaba activa, se manda al activarse.
    private var pending: WatchSessionSnapshot?

    /// `nil` en un dispositivo sin WatchConnectivity (por ejemplo, un iPad).
    init?(session: WCSession = .default) {
        guard WCSession.isSupported() else { return nil }
        self.session = session
        (messages, continuation) = AsyncStream.makeStream(of: WatchMessage.self)
        super.init()
        session.delegate = self
        session.activate()
    }

    func publish(_ snapshot: WatchSessionSnapshot) async {
        lock.withLock { pending = snapshot }
        sendPending()
    }

    /// Sin reloj emparejado o sin la app no hay a quién mandarle: no es un error.
    private func sendPending() {
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let snapshot = lock.withLock({ pending }) else { return }
        do {
            try session.updateApplicationContext([Self.payloadKey: WatchWireCodec.encode(snapshot)])
        } catch {
            logger.diagnostic("watch.publish.failed", level: .error)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        sendPending()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Al cambiar de reloj la sesión se desactiva: hay que activarla otra vez.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[Self.payloadKey] as? Data,
              let message = try? WatchWireCodec.decode(WatchMessage.self, from: data) else {
            logger.diagnostic("watch.message.unreadable", level: .error)
            return
        }
        continuation.yield(message)
    }
}
