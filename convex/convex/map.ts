import { v } from "convex/values";
import { query } from "./_generated/server";

/**
 * Maps full US state names → 2-letter postal codes. Reverse-geocoding
 * sometimes stores "Colorado" while the iOS layer stores "CO" for the
 * same scan, which would split one Denver into two cells. We normalize
 * to the postal code so both forms collapse onto the same key.
 */
const US_STATE_ABBR: Record<string, string> = {
  alabama: "AL", alaska: "AK", arizona: "AZ", arkansas: "AR", california: "CA",
  colorado: "CO", connecticut: "CT", delaware: "DE", florida: "FL", georgia: "GA",
  hawaii: "HI", idaho: "ID", illinois: "IL", indiana: "IN", iowa: "IA",
  kansas: "KS", kentucky: "KY", louisiana: "LA", maine: "ME", maryland: "MD",
  massachusetts: "MA", michigan: "MI", minnesota: "MN", mississippi: "MS",
  missouri: "MO", montana: "MT", nebraska: "NE", nevada: "NV",
  "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM", "new york": "NY",
  "north carolina": "NC", "north dakota": "ND", ohio: "OH", oklahoma: "OK",
  oregon: "OR", pennsylvania: "PA", "rhode island": "RI", "south carolina": "SC",
  "south dakota": "SD", tennessee: "TN", texas: "TX", utah: "UT", vermont: "VT",
  virginia: "VA", washington: "WA", "west virginia": "WV", wisconsin: "WI",
  wyoming: "WY", "district of columbia": "DC",
};

const US_COUNTRY_ALIASES = new Set([
  "us", "usa", "u.s.", "u.s.a.", "united states", "united states of america",
]);

function normCountry(raw: string | undefined): string {
  const s = (raw ?? "").trim();
  if (!s) return "";
  if (US_COUNTRY_ALIASES.has(s.toLowerCase())) return "United States";
  return s;
}

function normState(raw: string | undefined, country: string): string {
  const s = (raw ?? "").trim();
  if (!s) return "";
  if (country === "United States") {
    const abbr = US_STATE_ABBR[s.toLowerCase()];
    if (abbr) return abbr;
    if (/^[A-Z]{2}$/.test(s)) return s;
    return s.toUpperCase().length === 2 ? s.toUpperCase() : s;
  }
  return s;
}

function normCity(raw: string | undefined): string {
  const s = (raw ?? "").trim();
  if (!s) return "";
  // Title-case so "denver" / "DENVER" / "Denver" all collapse to the
  // same key.
  return s
    .split(/\s+/)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join(" ");
}

/**
 * Anonymized aggregation of done classifications by administrative region.
 * Returns counts only - never per-user data, never exact coordinates.
 */
export const aggregate = query({
  args: { level: v.union(v.literal("country"), v.literal("state"), v.literal("city")) },
  handler: async (ctx, { level }) => {
    const rows = await ctx.db
      .query("classifications")
      .withIndex("by_status", (q) => q.eq("status", "done"))
      .collect();

    type Cell = {
      key: string;
      label: string;
      scans: number;
      itemsTotal: number;
      itemsRecycled: number;
      itemsTrashed: number;
      itemsHazard: number;
      co2Kg: number;
      uniqueUsers: Set<string>;
      lastActivity: number;
      hazardRate: number;       // computed at finalize
      diversionRate: number;    // computed at finalize
      activeDays: Set<string>;
    };
    const cells = new Map<string, Cell>();
    for (const r of rows) {
      const country = normCountry(r.country);
      const state = normState(r.state, country);
      const city = normCity(r.city);

      const key =
        level === "country" ? country
        : level === "state" ? [country, state].filter(Boolean).join(" / ")
        : [country, state, city].filter(Boolean).join(" / ");
      if (!key) continue;
      const label =
        level === "country" ? country
        : level === "state" ? state
        : (state ? `${city}, ${state}` : city);

      let cell = cells.get(key);
      if (!cell) {
        cell = {
          key, label,
          scans: 0,
          itemsTotal: 0,
          itemsRecycled: 0,
          itemsTrashed: 0,
          itemsHazard: 0,
          co2Kg: 0,
          uniqueUsers: new Set(),
          lastActivity: 0,
          hazardRate: 0,
          diversionRate: 0,
          activeDays: new Set(),
        };
        cells.set(key, cell);
      }
      cell.scans += 1;
      if (r.userId) cell.uniqueUsers.add(String(r.userId));
      if (r.capturedAt > cell.lastActivity) cell.lastActivity = r.capturedAt;
      cell.activeDays.add(new Date(r.capturedAt).toISOString().slice(0, 10));
      for (const it of r.items) {
        if (it.reviewState !== "confirmed") continue;
        cell.itemsTotal += 1;
        cell.co2Kg += it.co2Kg ?? 0;
        if (it.decision === "recycle" || it.decision === "compost") cell.itemsRecycled += 1;
        else if (it.decision === "hazard") cell.itemsHazard += 1;
        else cell.itemsTrashed += 1;
      }
    }

    // Finalize: rates + serializable shape (no Sets).
    const out = Array.from(cells.values()).map((c) => {
      const denom = c.itemsTotal || 1;
      return {
        key: c.key,
        label: c.label,
        // Renamed to be unambiguous + back-compat-friendly:
        count: c.scans,           // legacy alias used by UI (was scans)
        recycled: c.itemsRecycled, // legacy alias used by UI
        scans: c.scans,
        itemsTotal: c.itemsTotal,
        itemsRecycled: c.itemsRecycled,
        itemsTrashed: c.itemsTrashed,
        itemsHazard: c.itemsHazard,
        co2Kg: Math.round(c.co2Kg * 1000) / 1000,
        uniqueUsers: c.uniqueUsers.size,
        activeDays: c.activeDays.size,
        lastActivity: c.lastActivity,
        diversionRate: Math.round((c.itemsRecycled / denom) * 100) / 100,
        hazardRate: Math.round((c.itemsHazard / denom) * 100) / 100,
      };
    });
    // Rank by total CO2 saved (most-impactful regions first), tiebreak on scans.
    out.sort((a, b) => (b.co2Kg - a.co2Kg) || (b.scans - a.scans));
    return out;
  },
});
