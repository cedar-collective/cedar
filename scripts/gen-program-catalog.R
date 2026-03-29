suppressMessages({library(qs); library(dplyr)})
setwd("/Users/fwgibbs/Dropbox/projects/cedar")
ap <- qread("data/academic_studies.qs")
env <- new.env()
source("R/lists/subj_dept_map.R", local=env)
source("R/lists/mappings.R", local=env)
uc <- env$subj_dept_map; p2d <- env$major_to_dept; cname2code <- env$college_name_to_code
d2c <- { u <- uc[!duplicated(uc$dept_code),]; setNames(u$college_code, u$dept_code) }

premaj_canon <- c(
  FAFS="AFST",FAMS="AMST",FANT="ANTH",FASP="ASPH",FBIC="BIOC",FBIO="BIOL",
  FCCS="CCS",FCHB="CHBI",FCHM="CHEM",FCLC="CLCS",FCLS="CLST",FCOM="COM",FCRI="CRIM",
  FEAS="EAS",FECO="ECON",FENP="ENGP",FENS="ENGS",FEPS="EPS",FESC="ENSC",
  FFRE="FREN",FGEO="GEOG",FGRM="GRMN",FHIS="HIST",FINT="INTS",FJMC="JRMC",
  FLIN="LING",FLNG="LANG",FLTA="LTAM",FMAT="MATH",FMCO="MCOM",FNAT="NATV",
  FPAP="PAP",FPHI="PHIL",FPHY="PHYC",FPOL="POLS",FPOR="PORT",FPSY="PSY",
  FRLS="RLST",FRUS="RUSL",FSHS="SHS",FSIG="SIGN",FSOC="SOC",FSPA="SPAN",
  FSTA="STAT",FWGS="WGSS",FWMS="WMST",FFCS="FCS",
  FAHI="ARTH",FAST="ARTS",FDAN="DANC",FDTP="THEA",FFDA="FDMA",FFDM="FDMA",
  FIDA="FDMA",FMAR="FDMA",FMUE="MUS",FMUS="MUS",FRTE="ARTE",FTHR="THEA",
  FAT="ATED",FCST="FCS",FCHE="HED",FELE="EDUC",FES="PHED",FHED="HED",
  FNDI="NDIT",FPE="PHED",FSEC="SED",FSPC="SPCD",
  FNAP="NURS",FNRS="NURS",FBAD="BADM",
  FCE="CE",FCH="CBE",FCP="CPE",FCS="CS",FEE="ECE",FME="ME",FNE="NE",FCON="CE",
  FARC="ARCH",FENV="ENVD",FHIL="HNRS",FITT="IADL",FPHS="PHRM",FPOH="POHE"
)
xvar_explicit <- c(
  XBAM="BADM",XFBA="BADM",XBAD="BADM",XCBA="CBA",XPJM="BADP",
  XCHE="HED",XFCH="HED",XITT="IADL",XFIT="IADL",XMGM="MGMT",
  XECO="ECON",XJMC="JRMC",XNAT="NATV",
  XFCC="CCS",XFEC="ECON",XFJM="JRMC",XFNA="NATV",XFPY="PSY",
  XEDU="EDUC",XELE="EDUC",XOIL="OILS",XSED="SED",XCMG="CE",
  XDEH="DEHY",XEE="ECE",XPE="PHED",XBSN="NURS"
)
extra_p2d <- c(
  ACCT="ACCT",BADM="MGMT",MGMT="MGMT",MKTG="MKTG",ENTR="ENTR",BCIS="BCIS",
  CBA="MGMT",ISA="MGMT",EMBA="MGMT",PJMG="MGMT",BADP="MGMT",
  NURP="NURS",NUAP="NURS",NUR="NURS",PHRD="PHRM",PHRS="PHRM",PTHE="PT",
  POHE="HSCI",DEHY="DEHY",RADS="RADS",PAST="PAST",PHRM="PHRM",
  CLCS="ENGL",CLST="LCL",JRMC="CJ",MCOM="CJ",ENGS="ENGL",ENGP="ENGL",
  ENSC="EPS",CHBI="BIOL",BIOC="BIOC",BIOM="BIOM",PAP="PHYS",ASPH="PHYS",
  INTS="ISI",RUSL="LCL",RLST="RELG",GEOG="GES",GRMN="LCL",FREN="LCL",
  PORT="SPAN",SIGN="LING",COM="CJ",CRWR="ENGL",SPLP="SHS",
  CSD="SHS",GESP="GES",GERS="LCL",
  ARCT="ARCH",FILM="FDMA",ARTH="ARTH",THEA="THEA",MUS="MUS",DANC="DANC",
  FDMA="FDMA",ARTE="ARTS",IDAR="FDMA",MA="FDMA",IFDM="FDMA",DTP="THEA",
  MUSE="MUS",DRAM="THEA",THTD="THEA",
  LAW="LAW",ELED="EDUC",TESL="LLSS",HED="HED",MSET="MSET",ATED="ATED",
  NUTR="NUTR",LLSS="LLSS",EDPY="EDPY",FCS="FCS",COUN="COUN",LEAD="LEAD",
  PHED="PHED",SED="EDUC",CHED="HED",ES="PHED",NDIT="NUTR",HDFR="FCS",
  PE="PHED",SPCD="SPED",COED="COUN",MCTC="EDUC",TLTE="EDUC",ELNG="LING",
  PESE="PHED",EDAG="EDPY",
  BME="BME",ECE="ECE",CBE="CBE",NSME="NSME",NSMS="NSME",CHE="CBE",EE="ECE",
  CPE="CPE",CONM="CE",MFGE="ME",
  GLNS="GLNS",OILS="OILS",IADL="IADL",OCTH="OCTH",ITT="IADL",TTR="IADL",
  ABA="PSYC",AGC="COUN",ASD="PSYC",MCH="HSCI",PHSC="HSCI",
  CSCE="CS",HPR="ARCH",URBI="CRP",PUPO="PADM",MUSP="MUS",TPC="ENGL",
  RSJ="SOCI",CTS="CHEM",AT="ATED",HES="HSCI",
  STLW="LAW",OPEN="PHYS",OLIT="IADL",FRST="LCL",SPPR="SPAN",
  LIBA="LAIS",HILA="HNRS",IDLA="HNRS",ENVD="CRP",HNRS="HNRS",
  ACTI="RADS",AMRI="RADS",CTOM="RADS",MRI="RADS",SCTO="RADS",SMRI="RADS",
  MED="BIOM",FPMD="PHRM",PHARMD="PHRM",
  LAIS="LAIS"
)
for (nm in names(extra_p2d)) if (is.na(p2d[nm])) p2d[nm] <- extra_p2d[nm]
for (d in unique(uc$dept_code)) if (is.na(p2d[d])) p2d[d] <- d
for (nm in names(premaj_canon)) { can <- premaj_canon[nm]; if (is.na(p2d[nm]) && !is.na(p2d[can])) p2d[nm] <- p2d[can] }

known_suffixes <- c("AS","FA","EH","ED","MG","EN","AP","ME","PH","PO","NU","LW","HC","UC","LL","GP","PA")
progs <- unique(ap[, c("Program Code","Program","Degree","Actual College")])
names(progs) <- c("full","name","deg","col_text")
parts <- strsplit(progs$full, "-")
progs$d_abbr <- sapply(parts,`[`,1); progs$p_mid <- sapply(parts,`[`,2)
progs$c_suff <- sapply(parts,function(x) if(length(x)>=3) x[3] else NA_character_)
progs <- progs[is.na(progs$c_suff)|progs$c_suff %in% known_suffixes, ]
progs <- progs[!is.na(progs$p_mid) & progs$deg != "Non-Degree Program", ]

real_F_progs <- c("FREN","FDMA","FCS","FS","FRST","FCST")
progs$prog_type <- ifelse(grepl("^X", progs$p_mid), "variant",
                  ifelse(progs$p_mid %in% names(premaj_canon) |
                         (grepl("Pre", progs$name, fixed=TRUE) & !(progs$p_mid %in% real_F_progs)),
                         "pre_major", "degree"))

progs$canonical <- NA_character_
pm <- progs$prog_type=="pre_major" & progs$p_mid %in% names(premaj_canon)
progs$canonical[pm] <- premaj_canon[progs$p_mid[pm]]
v <- progs$prog_type=="variant"
progs$canonical[v] <- ifelse(!is.na(xvar_explicit[progs$p_mid[v]]),
                             xvar_explicit[progs$p_mid[v]], sub("^X","",progs$p_mid[v]))

lookup_dept <- function(code){
  if(is.na(code)) return(NA_character_)
  d <- p2d[code]; if(!is.na(d)) return(d)
  if(code %in% unique(uc$dept_code)) return(code)
  NA_character_
}
progs$dept <- sapply(progs$p_mid, lookup_dept)
need_can <- is.na(progs$dept) & !is.na(progs$canonical)
progs$dept[need_can] <- sapply(progs$canonical[need_can], lookup_dept)

progs$col <- d2c[progs$dept]
fb <- is.na(progs$col); progs$col[fb] <- cname2code[progs$col_text[fb]]

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
progs$lev <- mapply(get_lev, progs$deg, progs$d_abbr)
progs$lev[progs$d_abbr=="PMS"] <- "Graduate"
progs$lev[grepl("ME in Mfg|ME in Manuf", progs$deg)] <- "Graduate"

cat("Unmapped dept (",sum(is.na(progs$dept)),"):\n")
if(sum(is.na(progs$dept))>0) {
  df <- progs[is.na(progs$dept),c("full","name","col_text","prog_type","canonical")]
  for(i in seq_len(nrow(df))) cat(sprintf("  %-22s | %-32s | %-28s | %s | %s\n",
    df$full[i],df$name[i],df$col_text[i],df$prog_type[i],ifelse(is.na(df$canonical[i]),"",df$canonical[i])))
}
cat("Other level (",sum(progs$lev=="Other"),"):\n")
if(sum(progs$lev=="Other")>0) print(progs[progs$lev=="Other",c("full","deg")])
cat("Total rows:",nrow(progs),"\n")
saveRDS(progs,"data/program_catalog_draft.rds")
cat("Draft saved.\n")
# This won't run, just for reference - the script was already complete
