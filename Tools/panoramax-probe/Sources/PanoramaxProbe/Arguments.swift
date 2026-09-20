// SPDX-License-Identifier: MIT

import Foundation

/// Ligne de commande décortiquée : positionnels, drapeaux, options valuées.
///
/// Pas d'ArgumentParser : la sonde n'a besoin que de ça, et le projet tient à
/// n'avoir qu'une seule dépendance externe — MapLibre, pour la carte.
struct Arguments {

    /// Options attendant une valeur ; tout autre `--xxx` est un drapeau.
    static let valued: Set<String> = ["lat", "lon", "alt", "heading", "title", "token"]

    private(set) var positional: [String] = []
    private(set) var flags: Set<String> = []
    private(set) var options: [String: String] = [:]

    init(_ raw: [String]) {
        var index = 0
        while index < raw.count {
            let argument = raw[index]
            if argument.hasPrefix("--") {
                let name = String(argument.dropFirst(2))
                if Self.valued.contains(name), index + 1 < raw.count {
                    options[name] = raw[index + 1]
                    index += 1
                } else {
                    flags.insert(name)
                }
            } else {
                positional.append(argument)
            }
            index += 1
        }
    }

    /// Positionnel à cet index, ou `nil`. Nommé autrement que la propriété
    /// `positional` : une méthode et une propriété de même nom se compilent,
    /// mais se relisent mal.
    func argument(at index: Int) -> String? {
        index < positional.count ? positional[index] : nil
    }

    func has(_ flag: String) -> Bool { flags.contains(flag) }

    func double(_ name: String) -> Double? {
        // Le séparateur décimal saisi peut être une virgule sur un clavier
        // français : l'accepter évite un « --lat 45,92 » silencieusement ignoré.
        options[name].flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }
}
