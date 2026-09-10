# CEDAR-INSTITUTION: Banner program-code conventions and overrides
# program_code_maps.R — Manual override maps for Banner program code parsing.
#
# These constants encode business logic that cannot be derived from Banner data alone.
# They are sourced by:
#   - transform-to-cedar.R (generate_program_map() when program_map.qs is stale/missing)
#   - load-funcs.R (makes them available in the Shiny app environment)
#
# Do NOT use raw palette or hardcoded dept values here — keep each map flat and named.
#
# Sections:
#   1. known_suffixes  — valid Banner program code college suffixes
#   2. real_F_progs    — F-prefix codes that are NOT pre-majors
#   3. premaj_canon    — F-prefix pre-major codes → target major codes
#   4. xvar_explicit   — X-prefix variant codes → canonical major codes
#   5. extra_p2d       — major_code → dept_code overrides for codes absent from subj_dept_map
#   6. allowed_unmapped_program_codes — reviewed Banner programs with no dept owner
#   7. get_lev()       — classify Banner degree description → degree level string

# ── 1. Valid college suffixes in Banner program codes (e.g. "BA-ANTH-AS") ───────

known_suffixes <- c("AS","FA","EH","ED","MG","EN","AP","ME","PH","PO","NU","LW",
                    "HC","UC","LL","GP","PA",
                    "GA","LA","TA","VA",  # branch campus: Gallup, Los Alamos, Taos, Valencia
                    # Legacy University Studies programs, administered through
                    # University College (UC). Unrecognised until 2026-09-09, and
                    # an unrecognised suffix makes generate_program_map() discard
                    # the program entirely -- no map row, no lookup, and its
                    # students in the dept_code identity fallback. 14 programs
                    # vanished this way, including BA-FLAI-US and BA-LAIS-US.
                    "US")

# The branch subset of the above, and the college every branch program belongs
# to regardless of what its main-campus equivalent department would imply.
# These were literals inside transform-to-cedar.R and catalog_lookups.R:
# platform code may READ institution constants, never contain them.
CEDAR_BRANCH_CAMPUS_SUFFIXES <- c("GA", "LA", "TA", "VA")
CEDAR_BRANCH_COLLEGE_CODE    <- "AD"

# ── 2. F-prefix codes that are true programs, not pre-majors ────────────────────
#
# Banner uses an F prefix for pre-majors, but some real programs simply start
# with F -- French, Film, Flamenco, Family Studies. These two vectors are the
# exceptions, and they are BOTH institution configuration: platform code reads
# them, and must never contain them.
#
# They answer the same question for two different consumers, and they DISAGREE.
# See ISSUES.md I9: 23,272 student-term rows carry a code the two lists classify
# differently. Reconciling them changes is_pre_major for about 1,741 students and
# needs someone who knows the catalog, so they are recorded here side by side
# rather than silently merged.

# Consumed by generate_program_map() when deciding prog_type.
real_F_progs <- c("FREN", "FDMA", "FCS", "FS", "FRST", "FCST")

# Consumed by transform_programs() when deriving is_pre_major. Was hardcoded
# inline in transform-to-cedar.R -- institution data inside platform code, which
# is how it drifted from real_F_progs unnoticed.
pre_major_exempt_codes <- c(
  "FA", "FLA", "FILM", "FDMA", "FFDA", "FFDM", "FMAR", "FIDA",
  "FLHC", "FLPR", "FLAI", "FS", "FES", "FPE", "FAT", "FNE",
  # An F prefix does not mean pre-major. FREN is French, FRST French Studies,
  # FCST Family & Child Studies -- real programs awarding degrees, flagged as
  # pre-majors on the strength of their first letter alone. Confirmed by
  # pre_major_basis: every one of their 4,007 rows read "code_convention", with
  # no supporting Pre- name anywhere. They were already in real_F_progs, so the
  # program map knew; only the transform did not.
  "FREN", "FRST", "FCST"
)

# ── 3. Pre-major (F-prefix) codes → canonical major codes ───────────────────────
#
# Banner uses F-prefix codes (e.g. FNRS, FPHY) for undeclared/pre-major students
# who intend to enter a specific program. This map resolves them to the target
# major_code so pre-major students can be linked to their intended program.

premaj_canon <- c(
  FAFS="AFST", FAMS="AMST", FANT="ANTH", FASP="ASPH", FBIC="BIOC", FBIO="BIOL",
  FCCS="CCS",  FCHB="CHBI", FCHM="CHEM", FCLC="CLCS", FCLS="CLST", FCOM="COM",
  FCRI="CRIM", FEAS="EAS",  FECO="ECON", FENP="ENGP", FENS="ENGS", FEPS="EPS",
  FESC="ENSC", FFRE="FREN", FGEO="GEOG", FGRM="GRMN", FHIS="HIST", FINT="INTS",
  FJMC="JRMC", FLIN="LING", FLNG="LANG", FLTA="LTAM", FMAT="MATH", FMCO="MCOM",
  FNAT="NATV", FPAP="PAP",  FPHI="PHIL", FPHY="PHYC", FPOL="POLS", FPOR="PORT",
  FPSY="PSY",  FRLS="RLST", FRUS="RUSL", FSHS="SHS",  FSIG="SIGN", FSOC="SOC",
  FSPA="SPAN", FSTA="STAT", FWGS="WGSS", FWMS="WMST", FFCS="FCS",
  FAHI="ARTH", FAST="ARTS", FDAN="DANC", FDTP="THEA", FFDA="FDMA", FFDM="FDMA",
  FIDA="FDMA", FMAR="FDMA", FMUE="MUS",  FMUS="MUS",  FRTE="ARTE", FTHR="THEA",
  FAT="ATED",  FCST="FCS",  FCHE="HED",  FELE="EDUC", FES="PHED",  FHED="HED",
  FNDI="NDIT", FPE="PHED",  FSEC="SED",  FSPC="SPCD",
  FNAP="NURS", FNRS="NURS", FBAD="BADM",
  FCE="CE",    FCH="CBE",   FCP="CPE",   FCS="CS",    FEE="ECE",   FME="ME",
  FNE="NE",    FCON="CE",   FARC="ARCH", FENV="ENVD", FHIL="HNRS", FITT="IADL",
  FPHS="PHRM", FPOH="POHE",
  # Pre-Liberal Arts & Integrative Studies. Confirmed against the catalog; the
  # declared form is LAIS, which is a real department.
  FLAI="LAIS",
  # Health pre-majors that Banner codes with an F prefix but never mapped to the
  # program they lead to. Without these the dept_code chain falls through to its
  # last resort -- the major code itself -- and the students land in a department
  # named after their own pre-major code. Radiologic Sciences reported 35
  # students at dept level when it had 229. See ISSUES.md I7.
  FRAD="RADS", FDEH="DEHY", FEMS="EMS", FMDL="MEDL"
)

# ── 4. Variant (X-prefix) codes → canonical major codes ─────────────────────────
#
# Banner uses X-prefix codes for cross-college or non-standard program variants.
# Where the simple rule "strip X → major code" fails, this map overrides it.

xvar_explicit <- c(
  XFDE="DEHY",  # Dental Hygiene variant; same phantom-department shape as FDEH
  XBAM="BADM", XFBA="BADM", XBAD="BADM", XCBA="CBA",  XPJM="BADP",
  XCHE="HED",  XFCH="HED",  XITT="IADL", XFIT="IADL", XMGM="MGMT",
  XECO="ECON", XJMC="JRMC", XNAT="NATV",
  XFCC="CCS",  XFEC="ECON", XFJM="JRMC", XFNA="NATV", XFPY="PSY",
  XEDU="EDUC", XELE="EDUC", XOIL="OILS", XSED="SED",  XCMG="CE",
  XDEH="DEHY", XEE="ECE",   XPE="PHED",  XBSN="NURS"
)

# ── 5. major_code → dept_code overrides ─────────────────────────────────────────
#
# subj_dept_map covers most major codes via subject_code identity, but some
# major codes differ from their Banner subject code (e.g. JRMC is in dept CJ).
# This map patches those gaps. Merged into p2d at generation time.

extra_p2d <- c(
  # ── Programs that first appeared after program_map.qs was last generated ────
  # Each of these had no map row, so the dept_code chain fell through to its
  # Tier 4 identity fallback and put the students in a department named after
  # their own program code. See ISSUES.md I7. Reasoning is recorded per entry
  # because the cost of a wrong department here is silent misattribution, which
  # is the same failure the mapping is being added to fix.
  GLPO="GLNS",  # Glob & Nat Secur Policy -> Global & National Security
  FILA="HNRS",  # Pre-Interdisc Liberal Arts; IDLA itself resolves to HNRS
  MDRC="HCHT",  # Health Info Tech Coding (Gallup) -> Health Careers Health Info Tech
  AAHS="HMSV",  # Human Services certificate (Gallup) -> Human Services
  CLSC="MEDL",  # MS Clinical Laboratory Science -> Medical Laboratory Sciences.
                # NOTE: CLNS "Clinical Sciences" is the other candidate; MEDL is
                # chosen on the "laboratory" match. Worth confirming with IR.
  EDST="EDUC",  # PHD Education Studies -> Education. Recorded under college GP
                # like every doctoral program, so the college gives no signal.
  DFP="THEA",   # BA Design for Performance (Fine Arts) -> Theatre, on the
                # reading that this is theatrical design. Worth confirming.

  ACCT="ACCT", BADM="MGMT", MGMT="MGMT", MKTG="MKTG", ENTR="ENTR", BCIS="BCIS",
  CBA="MGMT",  ISA="MGMT",  EMBA="MGMT", PJMG="MGMT", BADP="MGMT",
  NURP="NURS", NUAP="NURS", NUR="NURS",  PHRD="PHRM", PHRS="PHRM", PTHE="PT",
  POHE="HSCI", DEHY="DEHY", RADS="RADS", PAST="PAST", PHRM="PHRM",
  CLCS="ENGL", CLST="LCL",  JRMC="CJ",   MCOM="CJ",   ENGS="ENGL", ENGP="ENGL",
  ENSC="EPS",  CHBI="BIOL", BIOC="BIOC", BIOM="BIOM", PAP="PHYS",  ASPH="PHYS",
  INTS="ISI",  RUSL="LCL",  RLST="RELG", GEOG="GES",  GRMN="LCL",  FREN="LCL",
  PORT="SPAN", SIGN="LING", COM="CJ",    CRWR="ENGL", SPLP="SHS",
  CSD="SHS",   GESP="GES",  GERS="LCL",
  ARCT="ARCH", FILM="FDMA", ARTH="ARTH", THEA="THEA", MUS="MUS",   DANC="DANC",
  FDMA="FDMA", ARTE="ARTS", IDAR="FDMA", MA="FDMA",   IFDM="FDMA", DTP="THEA",
  MUSE="MUS",  DRAM="THEA", THTD="THEA",
  LAW="LAW",   ELED="EDUC", TESL="LLSS", HED="HED",   MSET="MSET", ATED="ATED",
  NUTR="NUTR", LLSS="LLSS", EDPY="EDPY", FCS="FCS",   COUN="COUN", LEAD="LEAD",
  PHED="PHED", SED="EDUC",  CHED="HED",  ES="PHED",   NDIT="NUTR", HDFR="FCS",
  PE="PHED",   SPCD="SPED", COED="COUN", MCTC="EDUC", TLTE="EDUC", ELNG="LING",
  PESE="PHED", EDAG="EDPY",
  BME="BME",   ECE="ECE",   CBE="CBE",   NSME="NSME", NSMS="NSME", CHE="CBE",
  EE="ECE",    CPE="CPE",   CONM="CE",   MFGE="ME",
  GLNS="GLNS", OILS="OILS", IADL="IADL", OCTH="OCTH", ITT="IADL",  TTR="IADL",
  ABA="PSYC",  AGC="COUN",  ASD="PSYC",  MCH="HSCI",  PHSC="HSCI",
  CSCE="CS",   HPR="ARCH",  URBI="CRP",  PUPO="PADM", HLAD="PADM", MUSP="MUS",  TPC="ENGL",
  RSJ="SOCI",  CTS="CHEM",  AT="ATED",   HES="HSCI",
  STLW="LAW",  OPEN="PHYS", OLIT="IADL", FRST="LCL",  SPPR="SPAN",
  LIBA="LAIS", HILA="HNRS", IDLA="HNRS", ENVD="CRP",  HNRS="HNRS",
  ACTI="RADS", AMRI="RADS", CTOM="RADS", MRI="RADS",  SCTO="RADS", SMRI="RADS",
  MED="BIOM",  FPMD="PHRM", PHARMD="PHRM",
  LAIS="LAIS",
  GIS="GES",   FOAN="ANTH"
)

# ── 6. Branch campus (AD) major_code → dept_code overrides ─────────────────────────
#
# Programs that exist at both main campus and branch campuses (GA/LA/TA/VA suffix)
# often share the same major_code (e.g. CRIM) but belong to different depts.
# generate_program_map() resolves dept via the main-campus subject_code lookup,
# which gives the wrong dept for these branch programs.
# This map is applied ONLY to branch campus suffix rows after the general dept lookup.
#
# Rules: add an entry here only when the branch campus dept differs from what
# the main-campus p2d lookup would produce. Codes already correct via subj_dept_map
# (e.g. CRJS → CJUS, ECED → ECED) do NOT need an entry.

ad_major_to_dept <- c(
  CRIM="CJUS",  # Branch campus CRIM → Criminal Justice (main campus maps to SOCI)
  BADM="BUSA",  # Branch campus BADM → Business Admin Branch (main campus maps to MGMT)
  AASN="NURS"   # Associate of Applied Science in Nursing → NURS dept (not in p2d)
)

# ── 6b. Major codes that legitimately have no academic department ──────────────
#
# Distinct from a mapping FAILURE. These programs are not owned by a department
# because no department owns them -- a Non-Degree or Undecided student has no
# academic home by definition, not by oversight. Without this list the
# identity-fallback screen reports them forever, and a page that cries wolf on
# its two largest entries teaches people to ignore it.
#
# The bar for adding a code: the program genuinely has no departmental owner,
# not merely that nobody has worked out which one it is. A code that SHOULD map
# somewhere belongs in extra_p2d, and until someone works it out it belongs on
# the Admin > Data & Usage > Mappings review list where it can be seen.

department_less_major_codes <- c(
  "NOND",  # Non-Degree — enrolled without pursuing a credential
  "UNDC"   # Undecided — has not declared a program
)

# ── 7. Reviewed programs with no department owner ──────────────────────────────
#
# These Banner programs are present in program_map but intentionally omitted from
# dept lookup vectors because Cedar has no defensible academic-department owner
# for them yet. Runtime startup surfaces unmapped rows in cedar_mapping_issues;
# transform-time regeneration should fail loudly until new rows are mapped above
# or reviewed and added here.

allowed_unmapped_program_codes <- c(
  # ── NEEDS RESEARCH (added 2026-09-09, ISSUES.md I7) ────────────────────────
  # These four have no defensible department owner that could be established
  # from the catalog alone. They are listed here so the regenerate stops failing
  # on them, NOT because the question is settled -- each is a real program whose
  # students currently have no department, and each needs someone who knows the
  # unit to answer it:
  #
  #   BS-ECME-ED    Early Childhood Multicultural Education, College of
  #                 Education. ECED (Early Childhood Education) exists but sits
  #                 in the AD/branch college, so it may be the wrong owner for a
  #                 main-campus BS; EDUC is the other candidate.
  #   BA-FS-AS      Family Studies, Arts & Sciences. The obvious match, FCS
  #                 (Family and Child Studies), is in College of Educ & Human
  #                 Sci -- a different college than the program is recorded in.
  #   MCM-CMGT      Construction Management, a graduate program. Candidates are
  #                 CNST/CT (Construction Technology, both AD/branch) and CE
  #                 (Civil Engineering); none is clearly the graduate owner.
  #   CERT-HHHA-TA  Holistic Health & Healing Arts certificate (Taos). No
  #                 department in subj_dept_map is a plausible match.
  #
  # Resolve by mapping in extra_p2d above and removing from this list.
  "BS-ECME-ED", "BA-FS-AS", "MCM-CMGT", "CERT-HHHA-TA",

  "AA-AAHS-GA", "AA-BUAD-VA", "AA-ECME-GA", "AA-ECME-VA", "AA-PBA-LA",
  "AA-PBA-TA", "AA-PPED-LA", "AA-SCTE-GA", "AAS-ARDT-VA", "AAS-BUSN-LA",
  "AAS-GDS-VA", "AAS-INCS-LA", "AFA-FA-TA", "AIS-INGV-VA", "AS-APHS-LA",
  "AS-ASNU-GA", "AS-ELTE-GA", "AS-GSCI-VA", "AS-HIT-GA", "AS-HIT-VA",
  "AS-MDLA-GA", "AS-PRSC-TA", "AS-SCI-GA", "AS-SCI-LA", "BA-EAST-AS",
  "BA-UNDC-AS", "BA-UNDC-UC", "CERT-DAST-GA", "CERT-EMBS-GA",
  "CERT-EMBS-LA", "CERT-ENTS-TA", "CERT-NEST-LA", "FPMD-UC", "MA-FS",
  "PHARMD-UC", "PHD-FS"
)

# ── 8. Degree level classifier ─────────────────────────────────────────────────
#
# Maps Banner degree description + degree abbreviation → standardized level string.
# Used row-wise via mapply() in generate_program_map().

get_lev <- function(d, ab) {
  if (grepl("^(Bachelor|BA in|BFA|BBA|BLA|BS in|BSN|BSDH|BSML|BSED|BAED|BISI|BEPD|BAA|Bachelors)", d)) return("Undergraduate")
  if (ab %in% c("BSCM","BSCE","BSCPE","BSCS","BSEE","BSME","BSNE","BSCNE","BSCHE","BSCPH","BEPD")) return("Undergraduate")
  if (grepl("^Associate", d)) return("Associate")
  if (grepl("^(Master|MFA|MBA|MPH|MPA|MCRP|MLA|MWR|MMU|MHA|MPP|MENG|MEME|MCM|MOT|MSN|MARCH|Doctor of Philosophy|Doctor of Education|PMS|Professional Master)", d)) return("Graduate")
  if (grepl("^Doctor of (Medicine|Nursing|Pharmacy|Physical|Occupational)", d)) return("Professional")
  if (grepl("^Juris Doctor", d)) return("Professional")
  if (grepl("^(Graduate Certificate|Cert with|One Year|Two Year|Post Mast|Education Specialist)", d)) return("Certificate")
  "Other"
}
