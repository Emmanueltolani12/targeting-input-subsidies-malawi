# Malawi input subsidy programme data (FISP 2005/06-2019/20, AIP 2020/21-2024/25)

Compiled by the author in November 2026 for the district-by-season coverage instruments and the program prices used in the paper. Every value is copied as printed in a source; nothing is estimated, interpolated or summed. Each row gives `source_id` and `location_in_source` (PDF page plus table or quoted text). All four CSVs have an extra last column, `note`, that records source spellings, table-level problems and conflicts.

## Files

| File | Rows | Content |
|---|---|---|
| `fisp_aip_district_allocations.csv` | 4,490 | District values by season, measure and source |
| `programme_prices.csv` | 75 | Farmer price, and commercial price where given |
| `programme_national.csv` | 322 | National totals: beneficiaries, tonnes, coupons, cost and budget |
| `sources.csv` | 104 | Citation, URL, date accessed, name of the saved copy and reliability note |

## Main source: Logistics Unit final reports

The core source is the Logistics Unit's *Final Report on the Implementation of the (Agricultural/Farm) Input(s) Subsidy Programme*. The reports cover 2006/07-2013/14, 2015/16 and 2016/17, and are hosted by ReSAKSS (nodes 6595-6604).

- This is the unit that printed, distributed and reimbursed the coupons, and the evaluations by SOAS/Wadonda/MSU cite it.
- District tables were read from the PDF text layer.
- Every table was checked against its printed regional and national subtotals. Remaining mismatches are in the source and are described in `note`.
- Tables with blank cells were checked against the page image.

## District coverage by season

"28" means all IHPS districts are covered.

| Season | Source | District measures |
|---|---|---|
| 2005/06 | Dorward et al. 2007 interim evaluation, Table 4.3 | First-round coupon allocations and sales: maize (urea+NPK) and tobacco (CAN+D). 27 districts: Mwanza and Neno are one row, Likoma absent. Supplementary coupons (583,000) have no district split. No beneficiary numbers exist. |
| 2006/07 | LU 2007 | Fertiliser coupons: initial issue, December print, total, recovered (Mwanza/Neno one row, no Likoma). Fertiliser MT distributed by type (27, no Likoma). Maize seed vouchers available and redeemed (27). |
| 2007/08 | LU 2008 | MoA allocation of 9 Oct 2007: maize fertiliser+seed number, tobacco, maize seed only, flexible (28). Fertiliser MT distributed (27, no Likoma). Maize-only seed vouchers available and redeemed (28). |
| 2008/09 | LU 2009 | Beneficiaries by voucher category on the 12 Sept list (28). Revised NPK/urea and maize allocations, Jan 2009 (28). ADMARC/SFFRFM uplifts and sales MT (28; Phalombe sales cell truncated in print, left blank). Maize and flexible vouchers allocated and redeemed (28). |
| **2009/10** | LU 2010 | Farm families, beneficiaries allocated, beneficiaries registered (by sex of head), MT delivered by type, 50 kg bags available and sold, maize and legume vouchers allocated and redeemed: all 28. |
| 2010/11 | LU 2011 | Farm families, allocation, registration, NPK/urea/maize/legume vouchers returned, MT delivered, presumed sales: all 28. |
| 2011/12 | LU 2012 | As 2010/11, plus fertiliser vouchers submitted and maize/legume allocated and redeemed: all 28. |
| **2012/13** | LU 2013 | Farm families, July and final (2 Nov) beneficiary allocations, registration, fertiliser vouchers allocated and returned (ADMARC, SFFRFM, total), MT delivered and sold, maize and legume vouchers, hybrid/OPV seed MT: all 28. |
| 2013/14 | LU 2014 | Beneficiaries allocated, fertiliser vouchers allocated and recovered, MT delivered, target and sold: all 28. The seed tables are images in the PDF and were not transcribed. |
| 2014/15 | none official | News only: Karonga ADD total. Dowa district profile gives Dowa uptake only. |
| **2015/16** | LU 2016 | Fertiliser vouchers issued and submitted, fertiliser available (in vouchers), MT required and delivered, maize and legume vouchers allocated and returned: all 28. There is no separate beneficiary column. |
| 2016/17 | LU 2017 | Beneficiaries (900,000) and fertiliser vouchers allocated and recovered (NPK, urea): all 28. Seed is reported by supplier only. |
| 2017/18 | none official | News: Lilongwe, Salima, Mchinji beneficiaries; Likoma tonnes. |
| **2018/19** | none official | News: beneficiaries for Lilongwe, Mzimba, Kasungu, Salima, Mchinji, Nkhotakota; Mangochi coupons. The official guidelines have no district annex. |
| 2019/20 | none official | News: Nkhotakota coupons, Chikwawa beneficiaries. |
| 2020/21, 2021/22 | none official | News: Mzimba (2020/21); redemption % for Chikwawa and Nkhata Bay (2021/22). |
| 2022/23 | Ombudsman 2024, Appendices 1 and 3 | Fertiliser beneficiaries (28). EPA-schedule subtotals: beneficiaries, targeted and sold MT as of 30 Mar 2023 (28). |
| **2023/24** | Ombudsman 2024, Appendices 1 and 4 | Fertiliser and total beneficiaries (28). Redemption table: beneficiaries and % redeemed as of 10 Feb 2024 (28). News figures for 7 districts as cross-checks. |
| 2024/25 | none official | News (Malawi News Agency, Nov 2024): beneficiaries for 13 districts. Nation, Dec 2024: two-season totals. |

For the instrument, the strongest series are:
- 2009/10 to 2013/14: beneficiaries allocated, plus farm-family registers 2009-2012 as denominators.
- 2015/16 and 2016/17: coupons.
- 2022/23 and 2023/24: AIP beneficiaries.

**There are no public district allocations for FISP 2014/15 or 2017/18-2019/20, or for AIP 2020/21, 2021/22 and 2024/25.**
- The Logistics Unit/FISP annual implementation reports for 2014/15 and 2017/18-2019/20 exist (MwAPATA cites "FISP Annual Implementation Reports, 2010-2020") but are unpublished.
- They would have to be requested from the Ministry's FISP Coordinating Unit.

### District naming

- IHPS spellings are used. Source spellings (Chikhwawa, Nkhota Kota, Nkhata Bay, Chiladzulu) are kept in `note`.
- Split or merged units are kept as printed:
  - `Mwanza/Neno` (2006/07 coupons, 2005/06)
  - `Mzimba North`/`South` and `Lilongwe East`/`West` (Ombudsman)
  - `Dowa East`/`West` (Ombudsman Appendices 3 and 4)
  - `Lilongwe (EPA block 1 of 2)` and `Mzimba (EPA block 1 of 2)`, etc. (Appendix 3 subtotals carry no label)
  - ADD, region or council aggregates from news
- Add the parts together yourself where needed. Lilongwe city and rural are never separated in these sources.

## Prices (`programme_prices.csv`)

FISP farmer price per 50 kg bag:

| Season | Price (MWK) | Notes |
|---|---|---|
| 2005/06 | 950 | Maize fertiliser. Tobacco fertiliser 1,450 (Dorward) or 1,400 (Chinsinga). |
| 2006/07 | 950 | |
| 2007/08 | 900 | |
| 2008/09 | 800 | |
| 2009/10-2013/14 | 500 | |
| 2014/15 | 500 | News, plus an ambiguous Annual Economic Report statement. |
| 2015/16 | 3,500 | Retail price at the time: 19,500. |
| 2016/17-2018/19 | none fixed | Coupon value MK 15,000. The farmer paid the balance to the supplier. In 2018/19 one observed top-up (news) was K5,500 urea and K6,500 NPK, against commercial prices of K20,500 and K22,000. |
| 2019/20 | 4,500 | Announced at launch (news). Market price 19,500. |

FISP seed:

| Season | Farmer price |
|---|---|
| 2005/06 | OPV MK 150 per 3 kg pack (market 500) |
| 2006/07 | Voucher only, so free |
| 2007/08 | Hybrid top-up: maximum MK 90 in the executive summary, MK 900 in the seed section of the same report |
| 2009/10-2011/12 | Optional top-up of at most MK 100 |
| 2012/13-2013/14 | Optional top-up of at most MK 150 |
| 2015/16 | MK 1,500 per 5 kg maize pack, MK 500 per legume pack |

AIP farmer price per 50 kg bag (NPK and urea alike):

| Season | Price (MWK) | Notes |
|---|---|---|
| 2020/21 | 4,495 | IFPRI Policy Note 42 says 4,995; all other sources say 4,495. |
| 2021/22 | 7,500 | |
| 2022/23 | 15,000 | |
| 2023/24 | 15,000 | |
| 2024/25 | 15,000 | News only; AER 2026 gives no price. |

AIP seed and goats:
- Seed: MK 2,000 per pack in 2020/21. From 2021/22 there is no fixed seed price: the government paid a fixed amount per pack and the farmer paid the rest.
- Goats: MK 7,500 in 2021/22 and MK 15,000 from 2022/23.

Commercial prices the sources report (per 50 kg bag):

| Season | Commercial price (MWK) |
|---|---|
| 2020/21 | Urea 20,510 and NPK 21,000 (MwAPATA); urea 22,042 (IFPRI) |
| 2021/22 | Up to 38,000 |
| 2022/23 | About 75,000 (IFPRI); 64,000-65,000 (news) |
| 2023/24 | 70,000 |
| 2024/25 | 93,000-115,000 (news, Sept-Dec 2024) |

## National totals (`programme_national.csv`)

| Seasons | Sources |
|---|---|
| 2005/06 | Dorward et al. 2007 and 2008; Chinsinga 2007 |
| 2006/07-2016/17 | Logistics Unit reports: coupons, tonnes, redemptions, costs |
| 2014/15, 2017/18-2019/20 | Annual Economic Reports, draft Financial Statements, budget statements and documents, 2018/19 guidelines, MwAPATA WP 21/05 (budget share and subsidy rate), news |
| 2020/21-2024/25 | Annual Economic Reports 2021-2026 (main official series), IFPRI MaSSP, MwAPATA, World Bank Agriculture PER and Economic Monitors, news |

There is no FISP beneficiary count for 2005/06 in any source found.

## Inconsistencies to know about

**Ombudsman Appendix 1:**
- **Dowa and Kasungu rows:** the 2022/23 TOTAL column repeats the 2023/24 totals, and the 2023/24 FERTILIZER column (159,698 and 63,843) conflicts with TOTAL (101,658 and 90,698). The ADD and national totals and the printed % changes support FERTILIZER for 2022/23 and TOTAL for 2023/24. Use `beneficiaries_total` for 2023/24.
- **National 2023/24:** 1,500,000 in Appendix 1, 1,520,425 in Appendix 4 (10 Feb 2024) and 1,511,302 in AER 2025.
- **National 2022/23:** 2,483,521 (Ombudsman) vs 2,483,532 (AER 2024).
- **Appendix 2 (farming households)** was not transcribed: several values are implausible. For example, Dowa has 67,887 households but 164,598 fertiliser beneficiaries.

**Logistics Unit internal mismatches** (listed per row in `note`):
- Maize allocation rows sum to 1,483,781 against a printed 1,500,000 (2008/09).
- The national "unknown sex" figure is 17,353, but district rows sum to 37,518 (2012/13).
- Southern legume returns (2011/12).
- Some district rows are 1-3 units off their subtotals because of rounding.
- Unallocated reserves (40,000 in 2009/10; 130,000 in 2008/09; 60,000 in 2007/08; 509 "unknown" in 2011/12) are not in the district rows.

**Different tables in the same report give different district numbers.** These are kept as separate measures with their own location:
- allocation vs registration
- July vs November 2012 lists
- Ombudsman Appendices 1, 3 and 4

**News vs official 2023/24 figures:**
- Blantyre 60,249 vs 60,150
- Salima 36,404 vs 36,468
- Ntchisi 44,980 vs 43,898

**FISP 2018/19 beneficiaries:** 1,000,000 in the guidelines and AER 2019, against 1.5 million and 900,000 in news reports.

## Reliability

| Series | Confidence | Notes |
|---|---|---|
| Logistics Unit district and national series, 2006/07-2016/17 | High | Primary administrative data, internally checked |
| Ombudsman Appendix 1 | High, except Dowa and Kasungu | |
| Ombudsman Appendices 3 and 4 | Medium | Mid-season status; duplicated EPA blocks were dropped |
| Annual Economic Report national figures | High | |
| Prices | High for official seasons | 2014/15, 2019/20 and 2024/25 prices rest on news |
| All rows whose note starts with NEWS | Low | Single district officials or journalists; often targets or partial counts |

## Access notes

- Several SOAS/Wadonda/MSU evaluation reports (2008/09-2012/13) are on core.ac.uk and soas-repository.worktribe.com, which demand a human-verification click. They were not used, and eprints.soas.ac.uk no longer resolves.
- The OAPEN copy of Chirwa and Dorward (2013), massp.ifpri.info and canr.msu.edu also block automated access. IFPRI items were taken from CGSpace or the Wayback Machine.
- These evaluations mainly re-use the Logistics Unit figures that are already here.

The saved copies of the sources (PDFs and web captures listed in `local_file` of `sources.csv`) are kept by the author and are not part of the repository; every source can be retrieved from its URL.
