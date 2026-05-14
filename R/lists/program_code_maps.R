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
#   6. get_lev()       — classify Banner degree description → degree level string

# ── 1. Valid college suffixes in Banner program codes (e.g. "BA-ANTH-AS") ───────

known_suffixes <- c("AS","FA","EH","ED","MG","EN","AP","ME","PH","PO","NU","LW",
                    "HC","UC","LL","GP","PA",
                    "GA","LA","TA","VA")  # branch campus: Gallup, Los Alamos, Taos, Valencia

# ── 2. F-prefix codes that are true programs, not pre-majors ────────────────────

real_F_progs <- c("FREN", "FDMA", "FCS", "FS", "FRST", "FCST")

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
  FPHS="PHRM", FPOH="POHE"
)

# ── 4. Variant (X-prefix) codes → canonical major codes ─────────────────────────
#
# Banner uses X-prefix codes for cross-college or non-standard program variants.
# Where the simple rule "strip X → major code" fails, this map overrides it.

xvar_explicit <- c(
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
  CSCE="CS",   HPR="ARCH",  URBI="CRP",  PUPO="PADM", MUSP="MUS",  TPC="ENGL",
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

# ── 8. Degree level classifier ───────────────────────────────────────────────────
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
