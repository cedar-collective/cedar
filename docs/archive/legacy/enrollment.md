---
title: Enrollment
layout: home
nav_order: 10
---

# Enrollment
One of the most useful features of CEDAR is aggregated and filtered enrollment reporting, which allows for a broader perspective---whether for a single semester or historical trends---that are not otherwise easily gained through MyReports data.


## Web Interface
The ENROLLMENT tab on the web tool provides aggregated and filtered enrollment reporting. The filtering is mostly self-explanatory.

- Special courses like thesis credits and similar are automatically filtered out. Let me know if you're not seeing a course that you need to.
- The most powerful control here is the `Group by` input box, which groups aggregated output. The grouping options are fields in DESR reports, and will look familiar.

For instance, you could look at:

### Enrollments for individual sections
- Select a course (or department or whatever) without any grouping

### Total enrollment of a course by term (group by SUBJ_CRSE and TERM)
- Select a course and group by SUBJ_CRSE and TERM
- If you don't group by TERM, all terms will be aggregated together

### Enrollments of a course by instructional method (F2F versus online) by term 
- Select a course and group by INST_METHOD and TERM

### How many sections of a course different instructors are teaching 
- Select a course and group by INST_NAME

### How many 2H courses is a department offering? 
- Select a Department, and group by PT.


---


## Command Line
CEDAR's CLI allows for finer control than via the web interface, but is generally slower because it loads data each command (but simple enrollment queries are still pretty quick).


### How do I see past enrollments for a course? 
Use the course filter: `Rscript cedar.R -f enrl -c 'HIST 491'` 

### How do I see past enrollments for an entire unit for a given semester? 
Use the dept and term filters: `Rscript cedar.R -f enrl -d ECON -t 202410` 

### How can I ignore the Dissertation and Independent Study sections? 
Use the "use exclude list" flag (--uel). Courses to be excluded are in the excluded_courses.R file.
`Rscript cedar.R -f enrl -d ECON -t 202410 --uel` 

  
### What have Physics enrollments been like in recent summers? 
The term filter understands term types (fall, spring, summer):
`Rscript cedar.R -f enrl  --uel -d PHYS -t summer` 


### How can I quickly see total enrollments for courses with many sections (like ENGL 1120)?
Use the `--group_cols` parameter with the name of columns (separated by columns) that you want to group
`Rscript cedar.R -f enrl --uel -c 'ENGL 1120' --group_cols SUBJ_CRSE`
`Rscript cedar.R -f enrl --uel -c 'ENGL 1120' --group_cols SUBJ_CRSE,TERM`


### What do 2H enrollments look like for a given term? 
Use the --pt (part of term) filter: `Rscript cedar.R -f enrl --college AS --pt 2H --uel -t 202410` 


### Why are courses listed multiple times?
Often because they are crosslisted with different values in the XL_SUBJ field. You can compress crosslisted courses into a single row by setting the -x flag to 'compress'.  

Compare:
- `Rscript cedar.R -f enrl -d AFST -t 202310`
- `Rscript cedar.R -f enrl -d AFST -t 202310 -x compress` 


### How can I filter out AOP enrollments? 
It almost always makes more sense to just combine the AOP and non-AOP sections in a single row, but there are two ways to handle AOP section display.

If you want to see the AOP sections stand out in an enrollment list: 
`Rscript cedar.R -f enrl -c 'SPAN 1110'  -t 202380 --aop compress` 

If you want the AOP sections to be totally merged into twin section: 
`Rscript cedar.R -f enrl -c 'SPAN 1110'  -t 202380 -x compress` 

  
### What do AOP enrollments look like for a dept? 

Use the --im filter (instructional method) for MOPS: 
`Rscript cedar.R -f enrl -d CCS --im MOPS -t 202410` 

 

### How can I compare available courses across semesters? 
The easiest way is to use the SEATFINDER-REPORT:
- `Rscript cedar.R -f seatfinder-report -d AMST --pt 2H -t 202310,202410`
  - This saves an ugly report to CEDAR_OUTPUT_DIR/seatfinder-reports. 

For the most flexibilty, you can run two reports and manually compare: 
`- Rscript cedar.R -f enrl -d AMST --pt 2H -t 202310` 
`- Rscript cedar.R -f enrl -d AMST --pt 2H -t 202410` 


### How can I get unit enrollment totals across a college? 
`Rscript cedar.R -f enrl --college AS --group_cols DEPT`

 

### How can I see total waitlist numbers for courses? 
Use the ENRL function with filtering (here, for lower-division A&S courses):
`Rscript cedar.R -f enrl -t 202510 --uel --arrange waiting --college AS -l lower -a course` 
