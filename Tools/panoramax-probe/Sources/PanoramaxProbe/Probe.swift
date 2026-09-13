// SPDX-License-Identifier: MIT

import Foundation
import PanoramaxKit

@main
struct Probe {

    static let defaultHost = "panoramax.openstreetmap.fr"

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            exit(2)
        }
        let host = arguments.count > 1 ? arguments[1] : defaultHost

        guard let instance = PanoramaxInstance(websiteURL: host) else {
            fail("Instance illisible : \(host)")
        }

        do {
            switch command {
            case "config":  try await showConfiguration(instance)
            case "login":   try await login(instance, host: host)
            case "whoami":  try await whoami(instance, host: host)
            case "logout":  try await logout(instance, host: host)
            case "-h", "--help", "help": printUsage()
            default:
                printUsage()
                exit(2)
            }
        } catch {
            fail(describe(error))
        }
    }

    // MARK: - Commandes

    static func showConfiguration(_ instance: PanoramaxInstance) async throws {
        let client = PanoramaxClient(instance: instance, userAgent: userAgent)
        let configuration = try await client.configuration()

        print("Instance      \(configuration.name?.text() ?? "—")")
        print("Version       \(configuration.version ?? "—")")
        print("Licence photo \(configuration.license?.id ?? "non déclarée")")
        if let url = configuration.license?.url {
            print("              \(url.absoluteString)")
        }
        print("Inscription   \(configuration.auth?.registrationIsOpen == true ? "ouverte" : "fermée")")
        print("CGU à accepter \(configuration.auth?.enforceTosAcceptance == true ? "oui" : "non")")

        if let coverage = configuration.geoCoverage?.text() {
            print("\nCouverture géographique")
            print(stripHTML(coverage))
        }

        if let defaults = configuration.defaults {
            print("\nDécoupage par défaut de l'instance")
            printSetting("split_distance", defaults.splitDistance, unit: "m")
            printSetting("split_time", defaults.splitTime.map { Int($0) }, unit: "s")
            printSetting("duplicate_distance", defaults.duplicateDistance, unit: "m")
            printSetting("duplicate_rotation", defaults.duplicateRotation, unit: "°")
        }
        if let values = configuration.visibility?.possibleValues {
            print("  visibilités        \(values.joined(separator: ", "))")
        }
    }

    static func login(_ instance: PanoramaxInstance, host: String) async throws {
        let client = PanoramaxClient(instance: instance, userAgent: userAgent)

        print("1/3  Génération d'un jeton non revendiqué…")
        let token = try await client.generateToken(description: "panoramax-probe")

        guard let claimURL = token.claimURL else {
            fail("Le serveur n'a pas renvoyé d'URL de revendication.")
        }

        print("2/3  Ouvre cette adresse et connecte-toi :\n")
        print("     \(claimURL.absoluteString)\n")
        openInBrowser(claimURL)

        print("3/3  Attente de la revendication (5 min max)…")
        let user = try await client.waitForTokenClaim(
            every: .seconds(2),
            timeout: .seconds(300)
        )

        let store = TokenStore()
        try store.store(.init(id: token.id.uuidString, jwt: token.jwtToken), for: host)

        print("\nConnecté en tant que \(user.name) (\(user.id))")
        print("Jeton enregistré dans \(store.path)")
    }

    static func whoami(_ instance: PanoramaxInstance, host: String) async throws {
        guard let entry = TokenStore().entry(for: host) else {
            fail("Aucun jeton mémorisé pour \(host). Lance d'abord : panoramax-probe login \(host)")
        }
        let client = PanoramaxClient(instance: instance, token: entry.jwt, userAgent: userAgent)
        let user = try await client.currentUser()
        print("\(user.name) (\(user.id)) sur \(host)")
    }

    static func logout(_ instance: PanoramaxInstance, host: String) async throws {
        let store = TokenStore()
        guard let entry = store.entry(for: host) else {
            print("Aucun jeton mémorisé pour \(host).")
            return
        }
        let client = PanoramaxClient(instance: instance, token: entry.jwt, userAgent: userAgent)
        if let id = UUID(uuidString: entry.id) {
            do {
                try await client.revokeToken(id: id)
                print("Jeton révoqué côté serveur.")
            } catch {
                print("Révocation impossible (\(describe(error))) — le jeton est tout de même oublié ici.")
            }
        }
        try store.remove(host: host)
        print("Jeton oublié localement.")
    }

    // MARK: - Utilitaires

    static let userAgent = "panoramax-probe (iPanoramax)"

    /// Affiche un réglage d'instance, ou un tiret s'il n'est pas déclaré.
    static func printSetting(_ name: String, _ value: (some CustomStringConvertible)?, unit: String) {
        let rendered = value.map { $0.description } ?? "—"
        let label = name.padding(toLength: 20, withPad: " ", startingAt: 0)
        print("  \(label) \(rendered) \(unit)")
    }

    static func printUsage() {
        print("""
        panoramax-probe — éprouve PanoramaxKit contre une instance réelle

        Usage :
          panoramax-probe config [instance]   configuration publique de l'instance
          panoramax-probe login  [instance]   generate → claim → /users/me
          panoramax-probe whoami [instance]   vérifie le jeton mémorisé
          panoramax-probe logout [instance]   révoque et oublie le jeton

        Instance par défaut : \(defaultHost)
        """)
    }

    static func openInBrowser(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try? process.run()
    }

    static func stripHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func describe(_ error: Error) -> String {
        (error as? PanoramaxError)?.errorDescription ?? error.localizedDescription
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("Erreur : " + message + "\n").utf8))
        exit(1)
    }
}
