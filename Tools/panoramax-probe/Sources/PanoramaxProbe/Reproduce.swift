// SPDX-License-Identifier: MIT

import Foundation
import PanoramaxKit

/// Établit — ou infirme — la reproductibilité d'un refus de l'API.
///
/// Un bug se signale sur des faits, pas sur une observation isolée. Cette
/// commande envoie une matrice de corps à `POST /api/upload_sets`, répète
/// chaque cas plusieurs fois pour écarter l'accident, et supprime derrière elle
/// tout ce qu'elle crée.
///
/// Les corps sont écrits en JSON littéral, jamais construits par notre
/// encodeur : ce qui est affiché est exactement ce qui part sur le réseau. La
/// dernière fois que ces deux choses ont divergé, la conclusion tirée était
/// fausse.
enum ReproduceProbe {

    struct TestCase {
        let label: String
        let json: String
    }

    static let title = "iPanoramax repro"

    static func cases() -> [TestCase] {
        [
            TestCase(
                label: "témoin — sans user_agent",
                json: #"{"title":"\#(title)"}"#
            ),
            TestCase(
                label: "témoin enrichi — sans user_agent",
                json: #"{"title":"\#(title)","estimated_nb_files":1,"sort_method":"time-asc","visibility":"owner-only"}"#
            ),
            TestCase(
                label: #"user_agent "panoramax-probe (iPanoramax)""#,
                json: #"{"title":"\#(title)","user_agent":"panoramax-probe (iPanoramax)"}"#
            ),
            TestCase(
                label: #"user_agent "iPanoramax" — un mot"#,
                json: #"{"title":"\#(title)","user_agent":"iPanoramax"}"#
            ),
            TestCase(
                label: #"user_agent "iPanoramax 1.0" — avec espace"#,
                json: #"{"title":"\#(title)","user_agent":"iPanoramax 1.0"}"#
            ),
            TestCase(
                label: #"user_agent "iPanoramax (test)" — avec parenthèses"#,
                json: #"{"title":"\#(title)","user_agent":"iPanoramax (test)"}"#
            ),
            TestCase(
                label: "user_agent vide",
                json: #"{"title":"\#(title)","user_agent":""}"#
            ),
            TestCase(
                label: "user_agent null",
                json: #"{"title":"\#(title)","user_agent":null}"#
            )
        ]
    }

    static func run(
        instance: PanoramaxInstance,
        host: String,
        arguments: Arguments
    ) async throws {
        guard let entry = TokenStore().entry(for: host) else {
            Probe.fail("Aucun jeton pour \(host). Lance d'abord : panoramax-probe login \(host)")
        }
        let client = PanoramaxClient(instance: instance, token: entry.jwt, userAgent: Probe.userAgent)
        let repeats = max(1, Int(arguments.options["repeats"] ?? "3") ?? 3)

        let configuration = try? await client.configuration()
        print("Instance   \(host)")
        print("API        \(configuration?.version ?? "non déclarée")")
        print("Route      POST /api/upload_sets")
        print("Essais     \(repeats) par cas")
        print()

        var created: [UUID] = []
        var results: [(TestCase, [Int])] = []

        for testCase in cases() {
            var statuses: [Int] = []
            for _ in 1...repeats {
                do {
                    let response = try await client.raw(
                        "POST",
                        path: "upload_sets",
                        body: Data(testCase.json.utf8),
                        contentType: "application/json"
                    )
                    statuses.append(response.statusCode)
                    if let id = uploadSetID(from: response) {
                        created.append(id)
                    }
                } catch {
                    print("  \(testCase.label) : échec de transport — \(Probe.describe(error))")
                    statuses.append(-1)
                }
            }
            results.append((testCase, statuses))
            print("  \(verdict(statuses))  \(testCase.label)")
        }

        print("\n--- Détail ---")
        for (testCase, statuses) in results {
            print("\n\(testCase.label)")
            print("  corps    \(testCase.json)")
            print("  statuts  \(statuses.map(String.init).joined(separator: " "))")
        }

        print("\n--- Nettoyage ---")
        await cleanUp(client, created: created, host: host)

        print("\n--- Conclusion ---")
        summarize(results)
    }

    /// `2xx` → accepté, `5xx` → refusé, mélange → intermittent.
    static func verdict(_ statuses: [Int]) -> String {
        let accepted = statuses.filter { (200..<300).contains($0) }.count
        if accepted == statuses.count { return "ACCEPTÉ " }
        if accepted == 0 { return "REFUSÉ  " }
        return "VARIABLE"
    }

    static func uploadSetID(from response: PanoramaxRawResponse) -> UUID? {
        guard (200..<300).contains(response.statusCode) else { return nil }
        if let location = response.headers["Location"],
           let last = location.split(separator: "/").last,
           let id = UUID(uuidString: String(last)) {
            return id
        }
        // Repli sur le corps quand l'en-tête manque.
        guard let data = response.body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["id"] as? String
        else { return nil }
        return UUID(uuidString: raw)
    }

    static func cleanUp(_ client: PanoramaxClient, created: [UUID], host: String) async {
        guard !created.isEmpty else {
            print("Rien n'a été créé.")
            return
        }
        var failed: [UUID] = []
        for id in created {
            do {
                try await client.deleteUploadSet(id: id)
            } catch {
                failed.append(id)
            }
        }
        print("\(created.count - failed.count) / \(created.count) ensembles d'essai supprimés.")
        for id in failed {
            print("  à retirer à la main : \(id.uuidString)")
        }
        if !failed.isEmpty {
            print("  depuis https://\(host)/")
        }
    }

    static func summarize(_ results: [(TestCase, [Int])]) {
        let refused = results.filter { verdict($0.1).hasPrefix("REFUSÉ") }
        let variable = results.filter { verdict($0.1).hasPrefix("VARIABLE") }

        if refused.isEmpty && variable.isEmpty {
            print("Tous les cas passent. Le refus observé le 20 septembre n'est pas")
            print("reproductible en l'état — ne pas signaler sans nouvelle occurrence.")
            return
        }
        if !variable.isEmpty {
            print("Des cas sont intermittents : c'est le signe d'une charge serveur")
            print("plutôt que d'un corps refusé. À rejouer avant de conclure.")
            for (testCase, statuses) in variable {
                print("  \(testCase.label) → \(statuses.map(String.init).joined(separator: " "))")
            }
        }
        if !refused.isEmpty {
            print("Refusés systématiquement sur \(results.first?.1.count ?? 0) essais :")
            for (testCase, _) in refused {
                print("  • \(testCase.label)")
            }
        }
    }
}
