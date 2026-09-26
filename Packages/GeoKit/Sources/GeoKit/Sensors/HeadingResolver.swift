// SPDX-License-Identifier: MIT

import Foundation
import ImageMetadataKit

/// Choisit le cap à inscrire dans la photo, ou décide de n'en inscrire aucun.
///
/// Les deux sources ont chacune leur domaine de validité. La boussole
/// magnétique est fiable à pied mais faussée dans un véhicule — carrosserie,
/// support aimanté, haut-parleurs. La route issue du GPS est fiable en
/// mouvement mais n'a aucun sens à l'arrêt, où elle dérive au gré du bruit.
///
/// Quand aucune n'est utilisable, ce type rend `nil`, et rien n'est écrit.
/// Panoramax traite correctement un cap absent ; un cap faux dégrade la
/// séquence pour tous ceux qui la réutiliseront.
public struct HeadingResolver: Sendable {

    /// Au-delà de cette vitesse, la route GPS l'emporte. 2 m/s ≈ 7 km/h :
    /// au-dessus du pas de marche, en deçà du vélo lent.
    public var minimumSpeedForCourse: Double

    /// Une boussole qui s'annonce à plus de 20° près ne vaut pas la peine.
    public var maximumCompassUncertainty: Double

    public init(minimumSpeedForCourse: Double = 2.0, maximumCompassUncertainty: Double = 20) {
        self.minimumSpeedForCourse = minimumSpeedForCourse
        self.maximumCompassUncertainty = maximumCompassUncertainty
    }

    public func resolve(fix: Fix, compass: HeadingReading?) -> Heading? {
        if fix.hasValidSpeed, fix.speed > minimumSpeedForCourse, fix.hasValidCourse {
            return Heading(trueDegrees: fix.course, source: .gpsCourse)
        }
        if let compass, compass.isUsable, compass.accuracy <= maximumCompassUncertainty {
            return Heading(trueDegrees: compass.trueHeading, source: .magneticCompass)
        }
        return nil
    }
}
