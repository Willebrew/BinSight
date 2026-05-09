/**
 * BinSight CO₂-equivalent impact table.
 *
 * Numbers are the *avoided* GHG emissions when a unit of material is
 * recycled or composted instead of landfilled, expressed in
 * **kg CO₂e per kg of material** (negative numbers in the EPA tables —
 * we store positive "savings" here).
 *
 * Source: U.S. EPA WARM (Waste Reduction Model) v16 — managed-by-pathway
 * emission factors, national-average grid, transportation included.
 *   https://www.epa.gov/warm
 *
 * Numbers below are conservative midpoints from WARM v16's
 * "GHG Emissions per ton of material recycled (avoided emissions vs.
 * landfilling)" tables, converted from short-ton CO2e to metric kg CO2e.
 *
 * Composting factors come from WARM v16 "organic, food waste" pathway.
 *
 * We carry an explicit ±20% range to reflect the spread you actually see
 * across grid mix, hauling distance, and contamination assumptions
 * (WARM's own sensitivity analyses land in roughly this window). Users
 * see this band rather than a falsely-precise point estimate.
 */
export type ImpactFactor = {
  /** Mid-range avoided emissions, kg CO2e per kg of material recycled. */
  midKgPerKg: number;
  /** Lower bound, kg CO2e per kg. */
  lowKgPerKg: number;
  /** Upper bound, kg CO2e per kg. */
  highKgPerKg: number;
  /** Default per-item mass when the model can't estimate it (kg). */
  defaultMassKg: number;
  /** Plain-English provenance for the methodology UI. */
  source: string;
};

const RANGE_FRAC = 0.2;

function factor(midKgPerKg: number, defaultMassKg: number, source: string): ImpactFactor {
  return {
    midKgPerKg,
    lowKgPerKg: Number((midKgPerKg * (1 - RANGE_FRAC)).toFixed(3)),
    highKgPerKg: Number((midKgPerKg * (1 + RANGE_FRAC)).toFixed(3)),
    defaultMassKg,
    source,
  };
}

export const RECYCLE_FACTORS: Record<string, ImpactFactor> = {
  // Plastics — recycled vs. landfilled, national grid
  pet: factor(1.07, 0.025, "EPA WARM v16 — PET, recycled vs. landfilled"),
  hdpe: factor(0.86, 0.05, "EPA WARM v16 — HDPE, recycled vs. landfilled"),
  ldpe: factor(0.69, 0.01, "EPA WARM v16 — LDPE film, recycled vs. landfilled"),
  pp: factor(1.02, 0.03, "EPA WARM v16 — PP, recycled vs. landfilled"),
  ps: factor(2.43, 0.02, "EPA WARM v16 — PS, recycled vs. landfilled"),
  plastic: factor(0.95, 0.03, "EPA WARM v16 — mixed plastics, recycled vs. landfilled"),

  // Metals
  aluminum: factor(9.13, 0.015, "EPA WARM v16 — aluminum cans, recycled vs. landfilled"),
  steel: factor(1.79, 0.15, "EPA WARM v16 — steel cans, recycled vs. landfilled"),
  tin: factor(1.79, 0.05, "EPA WARM v16 — steel/tin cans, recycled vs. landfilled"),

  // Paper & fiber
  paper: factor(3.15, 0.01, "EPA WARM v16 — mixed paper, recycled vs. landfilled"),
  cardboard: factor(3.14, 0.05, "EPA WARM v16 — corrugated cardboard, recycled vs. landfilled"),
  newspaper: factor(2.69, 0.05, "EPA WARM v16 — newsprint, recycled vs. landfilled"),

  // Glass
  glass: factor(0.28, 0.4, "EPA WARM v16 — glass, recycled vs. landfilled"),

  // Catch-alls
  mixed: factor(0.5, 0.05, "BinSight estimate — mixed/unsorted recyclable"),
  unknown: factor(0.0, 0.05, "Unknown material — no impact credited"),
};

export const COMPOST_FACTORS: Record<string, ImpactFactor> = {
  organic: factor(0.21, 0.1, "EPA WARM v16 — food waste, composted vs. landfilled"),
  food: factor(0.21, 0.1, "EPA WARM v16 — food waste, composted vs. landfilled"),
  yard: factor(0.18, 0.5, "EPA WARM v16 — yard trimmings, composted vs. landfilled"),
  paper: factor(0.16, 0.01, "EPA WARM v16 — paper, composted vs. landfilled"),
  cardboard: factor(0.16, 0.05, "EPA WARM v16 — cardboard, composted vs. landfilled"),
  unknown: factor(0.15, 0.1, "BinSight estimate — generic compostable"),
};

export type Co2Estimate = {
  co2Kg: number;
  co2KgLow: number;
  co2KgHigh: number;
  method: string;
  massKg: number;
};

/**
 * Compute the avoided-CO2 estimate for a single item.
 *
 * @param material  free-form material string (lowercased internally)
 * @param decision  recycle | compost | trash | hazard
 * @param massGramsHint  optional model-supplied mass in grams; undefined → defaults
 */
export function estimateCo2(
  material: string,
  decision: string,
  massGramsHint: number | undefined,
): Co2Estimate {
  const m = material.toLowerCase().trim();

  // Trash and hazard contribute zero credited savings (hazard might even be
  // negative impact, but we don't claim a credit for it).
  if (decision !== "recycle" && decision !== "compost") {
    const fallbackMass = pickFactor(m, decision).defaultMassKg;
    return {
      co2Kg: 0,
      co2KgLow: 0,
      co2KgHigh: 0,
      method: decision === "hazard"
        ? "Hazardous: must be diverted; no recycling credit applied."
        : "Landfilled: no avoided emissions credit applied.",
      massKg: massGramsHint !== undefined ? massGramsHint / 1000 : fallbackMass,
    };
  }

  const f = pickFactor(m, decision);
  const massKg =
    massGramsHint !== undefined && Number.isFinite(massGramsHint) && massGramsHint > 0
      ? massGramsHint / 1000
      : f.defaultMassKg;

  return {
    co2Kg: round3(f.midKgPerKg * massKg),
    co2KgLow: round3(f.lowKgPerKg * massKg),
    co2KgHigh: round3(f.highKgPerKg * massKg),
    method: f.source,
    massKg,
  };
}

function pickFactor(material: string, decision: string): ImpactFactor {
  if (decision === "compost") {
    return COMPOST_FACTORS[material] ?? COMPOST_FACTORS.unknown;
  }
  return RECYCLE_FACTORS[material] ?? RECYCLE_FACTORS.unknown;
}

function round3(n: number): number {
  return Number(n.toFixed(3));
}

/**
 * Back-compat wrapper for callers that just want a single number.
 * Prefer `estimateCo2()` for new code.
 */
export function estimateCo2Kg(material: string, decision: string): number {
  return estimateCo2(material, decision, undefined).co2Kg;
}
