# CTX-001: Applicability notes for Sumner, Washington, USA

- **Status:** ACT-002 working notes. **Unverified, and not legal advice.** Every item below is a *plausibly applicable* rule taken from ACT-002's general knowledge, which may be outdated or incomplete. A Washington-licensed attorney or privacy professional should review this list before any household is enrolled (GATE-013, decision 3).
- **Context:** local-first deployment (all household data on the household's device, no bank connectivity, no advice; REV-005), used for an exploratory observation study (STUDY-001).
- **Date:** 2026-09-26

The confidence column is ACT-002's own estimate. It is not a verification.

| # | Rule (as ACT-002 understands it) | Why it may matter here | Confidence | What the design does now |
|---|---|---|---|---|
| W1 | **Washington all-party consent for recording** (RCW 9.73.030): recording a private conversation generally requires the consent of every party. | Recording study interviews. | Moderate–high | STUDY-001 takes handwritten or typed notes by default. It records audio only with the explicit consent of every person present, captured at the start of the recording. |
| W2 | **Washington My Health My Data Act** (RCW 19.373): a broad definition of "consumer health data", including inferences. | Household finances often reveal health (medical bills, therapy, pharmacy). Interview notes could capture it. | Moderate on existence, **low on applicability** to a small unfunded study | Notes must not record health details. Participants describe categories, not specifics. Have this reviewed. |
| W3 | **Washington data breach notification** (RCW 19.255): duties when personal information, such as a name plus a financial account number, is compromised. | Only matters if the researcher holds such data. | Moderate | The researcher collects no account numbers, amounts, or item contents (STUDY-001 §5). |
| W4 | **Washington Consumer Protection Act** (RCW 19.86): prohibits unfair or deceptive practices. | Privacy promises made to participants must be true. | Moderate | Consent materials promise only what ASM-013 supports. In particular, they must not claim the prototype is secure against someone with access to the device unless DEF-025 option B or A is built. |
| W5 | **Washington Securities Act** (RCW 21.20), investment-adviser provisions. | Giving financial or investment advice. | Moderate | The product gives no advice (REV-005). The researcher must not advise during sessions either (STUDY-001 §7). |
| W6 | **No comprehensive Washington consumer privacy statute**, as far as ACT-002 knows. Such bills have been proposed repeatedly. | If one has been enacted since, it may apply. | **Low**, likely out of date | Verify. |
| F1 | **FTC Act §5** (unfair or deceptive practices), federal. | Same as W4. | High on existence | Same as W4. |
| F2 | **Gramm-Leach-Bliley Act / FTC Safeguards Rule**, for "financial institutions". | Probably not triggered by a no-custody, no-service research prototype, but the boundary is technical. | Low on applicability | Keep no-custody. Have it reviewed if the prototype is ever distributed beyond the study. |
| F3 | **COPPA** (children under 13, online collection). | Households may include children. | High on existence; not triggered if children are not participants and nothing is collected online | Only adults participate (STUDY-001 §4). |
| F4 | **Common Rule** (45 CFR 46): human-subjects protections, mandatory mainly for federally funded or institutional research. | Probably not legally mandatory here. Its protections are still the right standard. | Moderate | STUDY-001 recommends independent ethics review (GATE-013, decision 2). |
| F5 | **Tax reporting of participant incentives** (information-return thresholds). | Paying participants. | Low on the current threshold amount | Keep incentives modest and check the current threshold. |
| S1 | **Safety resources.** National Domestic Violence Hotline, 1-800-799-7233. Washington has state and Pierce County advocacy services. | Studying member standing may surface coercion. | High for the national number; local services need listing | STUDY-001 §6 provides resources to every participant privately. Local contacts are to be added and verified before the study starts. |
