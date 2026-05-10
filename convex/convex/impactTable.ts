/**
 * BinSight CO₂-equivalent impact table.
 *
 * Numbers are the *avoided* GHG emissions when a unit of material is
 * recycled or composted instead of landfilled, expressed in
 * **kg CO₂e per kg of material** (negative numbers in the EPA tables -
 * we store positive "savings" here).
 *
 * Source: U.S. EPA WARM (Waste Reduction Model) v16 - managed-by-pathway
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
  // Plastics - recycled vs. landfilled, national grid
  pet: factor(1.07, 0.025, "EPA WARM v16 - PET, recycled vs. landfilled"),
  hdpe: factor(0.86, 0.05, "EPA WARM v16 - HDPE, recycled vs. landfilled"),
  ldpe: factor(0.69, 0.01, "EPA WARM v16 - LDPE film, recycled vs. landfilled"),
  // Thin flexible plastic (chip bags, candy wrappers, food pouches, plastic
  // bags). Empty wrapper mass typically 3-8g - use 0.005kg as the default.
  film: factor(0.69, 0.005, "EPA WARM v16 - LDPE film, recycled vs. landfilled (flexible packaging)"),
  wrapper: factor(0.69, 0.005, "EPA WARM v16 - LDPE film, recycled vs. landfilled (flexible packaging)"),
  pp: factor(1.02, 0.03, "EPA WARM v16 - PP, recycled vs. landfilled"),
  ps: factor(2.43, 0.02, "EPA WARM v16 - PS, recycled vs. landfilled"),
  plastic: factor(0.95, 0.03, "EPA WARM v16 - mixed plastics, recycled vs. landfilled"),

  // Metals
  aluminum: factor(9.13, 0.015, "EPA WARM v16 - aluminum cans, recycled vs. landfilled"),
  steel: factor(1.79, 0.15, "EPA WARM v16 - steel cans, recycled vs. landfilled"),
  tin: factor(1.79, 0.05, "EPA WARM v16 - steel/tin cans, recycled vs. landfilled"),

  // Paper & fiber
  paper: factor(3.15, 0.01, "EPA WARM v16 - mixed paper, recycled vs. landfilled"),
  cardboard: factor(3.14, 0.05, "EPA WARM v16 - corrugated cardboard, recycled vs. landfilled"),
  newspaper: factor(2.69, 0.05, "EPA WARM v16 - newsprint, recycled vs. landfilled"),

  // Glass
  glass: factor(0.28, 0.4, "EPA WARM v16 - glass, recycled vs. landfilled"),

  // Catch-alls
  mixed: factor(0.5, 0.05, "BinSight estimate - mixed/unsorted recyclable"),
  unknown: factor(0.0, 0.05, "Unknown material - no impact credited"),
};

export const COMPOST_FACTORS: Record<string, ImpactFactor> = {
  organic: factor(0.21, 0.1, "EPA WARM v16 - food waste, composted vs. landfilled"),
  food: factor(0.21, 0.1, "EPA WARM v16 - food waste, composted vs. landfilled"),
  yard: factor(0.18, 0.5, "EPA WARM v16 - yard trimmings, composted vs. landfilled"),
  paper: factor(0.16, 0.01, "EPA WARM v16 - paper, composted vs. landfilled"),
  cardboard: factor(0.16, 0.05, "EPA WARM v16 - cardboard, composted vs. landfilled"),
  unknown: factor(0.15, 0.1, "BinSight estimate - generic compostable"),
};

export type Co2Estimate = {
  co2Kg: number;
  co2KgLow: number;
  co2KgHigh: number;
  method: string;
  massKg: number;
};

/**
 * Per-source mass uncertainty (fraction of mass).
 *   verified (search snippet w/ explicit grams) → ±5%
 *   model    (vision estimate from the photo)  → ±20%
 *   default  (no estimate, WARM fallback used)  → ±30%
 *
 * Combined with the WARM factor band (±20% on midKgPerKg) using a
 * relative-error sum so the displayed CO₂e range honestly widens when
 * we're guessing the mass.
 */
const MASS_UNCERTAINTY: Record<string, number> = {
  verified: 0.05,
  model: 0.20,
  default: 0.30,
};

/**
 * Compute the avoided-CO2 estimate for a single item.
 *
 * @param material  free-form material string (lowercased internally)
 * @param decision  recycle | compost | trash | hazard
 * @param massGramsHint  optional model-supplied mass in grams; undefined → defaults
 * @param massSource    where the mass came from (controls range width)
 */
export function estimateCo2(
  material: string | undefined,
  decision: string | undefined,
  massGramsHint: number | undefined,
  massSource: "verified" | "model" | "default" = "model",
): Co2Estimate {
  // Streaming partial JSON can hand us undefined fields before the model
  // has finished writing them — coerce to safe strings instead of crashing.
  const m = normalizeMaterial(material);
  const d = decision ?? "trash";

  // Trash and hazard contribute zero credited savings (hazard might even be
  // negative impact, but we don't claim a credit for it).
  if (d !== "recycle" && d !== "compost") {
    const fallbackMass = pickFactor(m, d).defaultMassKg;
    return {
      co2Kg: 0,
      co2KgLow: 0,
      co2KgHigh: 0,
      method: d === "hazard"
        ? "Hazardous: must be diverted; no recycling credit applied."
        : "Landfilled: no avoided emissions credit applied.",
      massKg: massGramsHint !== undefined ? massGramsHint / 1000 : fallbackMass,
    };
  }

  const f = pickFactor(m, d);
  const haveHint =
    massGramsHint !== undefined && Number.isFinite(massGramsHint) && massGramsHint > 0;
  const massKg = haveHint ? (massGramsHint as number) / 1000 : f.defaultMassKg;
  // If no hint was supplied we fell back to the WARM default mass — that's
  // the highest-uncertainty case regardless of what the caller said.
  const effectiveSource = haveHint ? massSource : "default";
  const massFrac = MASS_UNCERTAINTY[effectiveSource] ?? MASS_UNCERTAINTY.model;
  const factorFrac = RANGE_FRAC; // ±20% on the WARM factor itself

  // Combine the two relative-error bands. Using a simple sum is
  // conservative (true propagation in quadrature would be tighter) but
  // makes the displayed range visibly honest about mass guessing.
  const totalFrac = Math.min(0.6, massFrac + factorFrac);
  const mid = f.midKgPerKg * massKg;

  return {
    co2Kg: round3(mid),
    co2KgLow: round3(mid * (1 - totalFrac)),
    co2KgHigh: round3(mid * (1 + totalFrac)),
    method: f.source,
    massKg,
  };
}

/** Public-API: look up the WARM default mass (grams) for a material. */
export function defaultMassG(material: string | undefined, decision: string | undefined): number {
  const m = normalizeMaterial(material);
  const d = decision ?? "trash";
  return pickFactor(m, d).defaultMassKg * 1000;
}

/**
 * Map the model's free-form material string to one of our WARM factor keys.
 * Catches common variants like "flexible plastic", "metallized film",
 * "candy wrapper", "chip bag" → "film" so the default mass is realistic
 * (a Skittles bag is ~5g, not the 30g generic-plastic default).
 */
export function normalizeMaterial(raw: string | undefined): string {
  const m = (raw ?? "unknown").toLowerCase().trim();
  if (!m) return "unknown";
  if (/(film|wrapper|pouch|chip bag|candy bag|metalliz|multi.?layer|flexible)/.test(m)) {
    return "film";
  }
  if (/(cardboard|corrugated)/.test(m)) return "cardboard";
  if (/news/.test(m)) return "newspaper";
  if (/glass/.test(m)) return "glass";
  if (/aluminu?m/.test(m)) return "aluminum";
  if (/steel|tin/.test(m)) return "steel";
  if (/pet\b|polyethylene terephthalate/.test(m)) return "pet";
  if (/hdpe/.test(m)) return "hdpe";
  if (/ldpe/.test(m)) return "ldpe";
  if (/polypropylene|\bpp\b/.test(m)) return "pp";
  if (/polystyrene|styrofoam|\bps\b/.test(m)) return "ps";
  if (/paper/.test(m)) return "paper";
  if (/plastic/.test(m)) return "plastic";
  if (/food|organic|compost/.test(m)) return "organic";
  return m;
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
