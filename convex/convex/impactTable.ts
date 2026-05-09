// Placeholder kg-CO2-equivalent saved per kg of material recycled vs landfilled.
// Replace with a citable dataset (e.g. EPA WARM) before publishing claims.
export const CO2_KG_PER_KG: Record<string, number> = {
  pet: 2.5,
  hdpe: 1.8,
  aluminum: 9.1,
  steel: 1.8,
  paper: 1.1,
  cardboard: 1.0,
  glass: 0.6,
  organic: 0.3,
  mixed: 0.0,
  unknown: 0.0,
};

// Per-item assumed mass (kg) — used to convert "1 bottle" into a CO2 estimate
// when the model doesn't supply mass. Conservative defaults.
export const DEFAULT_MASS_KG: Record<string, number> = {
  pet: 0.025,
  hdpe: 0.05,
  aluminum: 0.015,
  steel: 0.15,
  paper: 0.01,
  cardboard: 0.05,
  glass: 0.4,
  organic: 0.1,
  mixed: 0.05,
  unknown: 0.05,
};

export function estimateCo2Kg(material: string, decision: string): number {
  if (decision !== "recycle" && decision !== "compost") return 0;
  const m = material.toLowerCase();
  const factor = CO2_KG_PER_KG[m] ?? CO2_KG_PER_KG.unknown;
  const mass = DEFAULT_MASS_KG[m] ?? DEFAULT_MASS_KG.unknown;
  return Number((factor * mass).toFixed(3));
}
