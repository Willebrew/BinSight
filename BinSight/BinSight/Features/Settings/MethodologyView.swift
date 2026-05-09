import SwiftUI

/// Static page explaining how BinSight measures impact. Linked from the
/// Dashboard footer and the Settings tab. Every claim is sourced -
/// "transparency" is a feature, not a footnote.
struct MethodologyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                section(
                    title: "Where the CO₂ numbers come from",
                    body: """
                    Every item you confirm is matched to an avoided-emissions factor from the U.S. EPA's WARM v16 model - the same dataset used by federal and municipal sustainability programs. We multiply the factor by the item's mass to get a per-item kg of CO₂e *avoided* compared to landfilling.
                    """,
                    link: ("EPA WARM →", "https://www.epa.gov/warm")
                )
                section(
                    title: "Why we show a range",
                    body: """
                    A single number would imply false precision. WARM's own sensitivity analyses span roughly ±20% based on grid mix, hauling distance, and contamination assumptions, so we always store and display a low / high band. The big number on your Dashboard is the midpoint.
                    """
                )
                section(
                    title: "How mass is estimated",
                    body: """
                    For each detected item, the model estimates mass in grams from visual cues (size, material density, how full a container looks). When it can't tell, we fall back to a conservative default per material (e.g. ~25 g for a PET bottle). Each item shows whether its mass came from the photo or a default.
                    """
                )
                section(
                    title: "Where decisions and sources come from",
                    body: """
                    Classifications come from Perplexity sonar-pro, which has live web search built in. We require the model to attach at least one source to every item, and we rank sources by tier - official (.gov / EPA / municipal) outranks authoritative (peer-reviewed, major news), which outranks community (forums, blogs). When your city's domain shows up, it's flagged as "local."
                    """
                )
                section(
                    title: "Why review-to-confirm matters",
                    body: """
                    Only items you've personally confirmed (swiped right) count toward your CO₂ totals. Pending items - and items you've ignored (swiped left) - don't accrue stats. You are the ground truth, and the dashboard reflects what you've actually validated.
                    """
                )
                section(
                    title: "Equivalences",
                    body: """
                    "0.5 kg CO₂e = 1.2 miles not driven" comes from the EPA Greenhouse Gas Equivalencies Calculator. Phone-charge equivalences come from EPA. Tree-month equivalences use USDA Forest Service urban tree sequestration averages.
                    """,
                    link: ("EPA Equivalencies →", "https://www.epa.gov/energy/greenhouse-gas-equivalencies-calculator")
                )
                section(
                    title: "What we don't (yet) account for",
                    body: """
                    • Regional grid mix differences (an aluminum can recycled near hydropower offsets more than one near coal). \n• Contamination penalties - a soiled container can downgrade the whole bale, which we currently model only via the "trash" decision. \n• Transportation emissions for take-back drop-offs. \nThese are on the roadmap; until then, treat the headline number as a rigorously-bounded estimate, not a precise measurement.
                    """
                )
            }
            .padding(20)
        }
        .navigationTitle("Methodology")
        .navigationBarTitleDisplayMode(.inline)
        .background(DuoBackdrop().ignoresSafeArea())
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            MascotArtView(mood: .thinking, size: 92, accessory: "function")
            Text("How BinSight measures impact")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
            Text("Every number you see - from individual scan CO₂ to the lifetime total on your Dashboard - has a citable source and an honest range.")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(BinSightTokens.Color.softInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 2))
    }

    private func section(title: String, body: String, link: (String, String)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(BinSightTokens.Color.ink)
            Text(body).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(BinSightTokens.Color.softInk)
            if let (label, urlString) = link, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square.fill").imageScale(.small)
                        Text(label).font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(BinSightTokens.Color.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(BinSightTokens.Color.accent)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 1.5))
    }
}
