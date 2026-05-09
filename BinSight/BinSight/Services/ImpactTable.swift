import Foundation

/// Placeholder kg-CO₂-equivalent saved per item recycled. Mirrors the values
/// in `convex/impactTable.ts`. Replace with a citable dataset before
/// publishing claims.
enum ImpactTable {
    static let co2KgPerKg: [String: Double] = [
        "pet": 2.5, "hdpe": 1.8, "aluminum": 9.1, "steel": 1.8,
        "paper": 1.1, "cardboard": 1.0, "glass": 0.6, "organic": 0.3,
        "mixed": 0.0, "unknown": 0.0,
    ]
    static let defaultMassKg: [String: Double] = [
        "pet": 0.025, "hdpe": 0.05, "aluminum": 0.015, "steel": 0.15,
        "paper": 0.01, "cardboard": 0.05, "glass": 0.4, "organic": 0.1,
        "mixed": 0.05, "unknown": 0.05,
    ]

    static func estimate(material: String, decision: String) -> Double {
        guard decision == "recycle" || decision == "compost" else { return 0 }
        let m = material.lowercased()
        let factor = co2KgPerKg[m] ?? co2KgPerKg["unknown"]!
        let mass = defaultMassKg[m] ?? defaultMassKg["unknown"]!
        return (factor * mass).rounded(toPlaces: 3)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (self * f).rounded() / f
    }
}
