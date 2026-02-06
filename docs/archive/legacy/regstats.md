---
title: Regstats
layout: home
nav_order: 22
---

# Regstats 
This tool looks for anomalies in registration bumps or dimps, early drops, late drops, and waitlists to help predict future course needs.

Anomolies are detected by looking at whether a certain phenomenon (like registration) is outside the standard deviation. It also indicates the number of students impacted by the “anomaly”.

It also looks at “squeezes”, where the number of seats at the end of the term is significantly less than what we’d expect from regular attrition. 

You can use threshold filters to include or exclude more courses. This includes as using more or less than 1 standard deviation to detect irregularities and changing the minimum number of students affected.


## What do the regstats columns mean? 
- count: total enrollment for the course 
- pct_sd: percent of students outside the mean affected compared to standard deviation. Computed as (mean – count) / sd 
- impacted: a rough count of how many students outside the mean are in the bump/dip/etc. This is to filter out courses in which not many students are being affected.  



## Thresholds 
Regstat’s primary function is to identify courses of interest. To do so, it needs thresholds of what constitutes a significant deviation from the norm. Here are the thresholds set in config.R and can be adjusted as need be. 

### sd_buffer
% of standard deviation before flagging as concern. Default: 1 (meaning use exactly the calculated SD) 

### min_impacted
min difference b/w enrollment and mean (= number of students affected). Default: 6 

### min_pct_sd
percent of students outside the mean compared to standard deviation. Z = (mean – count) / sd. Default: 1.2 

### min_squeeze 
squeeze is the ratio of avail seats to drops after census. Default: .5 (determined by general inspection).  

### min_wait
minimum number of students on a wait list before course is flagged. Default: 20 

### section_proximity
how close to integer before rounding up/down for recommended sections? closer to .5 reduces -100s: Default: .3 (set closer to .5 for more rounding; set closer to 0 for no rounding. 




## Command Line
You can create the same regstats reports as with the online tool, but also sets of CSV files for groups of courses.

Use regstats to create a list of courses, specifying a term or two PRIOR to what you will forecast for (to forecast for summer, run regstats or 202510 (and/or 202480): 
- `Rscript cedar.R -f regstats –t 202480,202510` 
 

This creates a series of files in the output/csv folder: 

- bumps.csv: Courses with enrollment bumps  
- after_bumps.csv: the top 10 courses students take after "bump" courses; useful for deciding whether some might be offered in summer, for instance. 
- dips.csv: Enrollment dips and the courses students take afterward (we might not need as many) 
- drops.csv: Courses with an unusually high number of drops, since we might need more of those courses 
- waits.csv: Courses with long wait lists, where a minimum number of students is defined in config.R 
- all_flagged_courses: all courses gathered into a master list for convenience 

Then, use the forecast function and set the -c flag to all_flagged_courses.csv. For instance, to forecast for summer 2025: 
- `Rscript cedar.R -f forecast -c all_flagged_courses.csv -t 202560` 

AGAIN: just forecasting for summer won't tell us about NEW courses that might be needed (but regstats and forecast-report will give you ideas!) 


### How can I share CLI regstats output
As with all reporting tools, to generate an HTML or ASPX report, use --output [csv/html/aspx]. If you don’t specify a format, the default is html. Files are saved to output/regstats-reports 

Specify csv to create the series of CSV files for each category (dips/bumps/drops/etc) in the output/csv folder. Files are saved to output/csv 
- `Rscript cedar.R -f regstats -t 202510 --output aspx` 

 

### How can I automatically generate course reports for courses identified by regstats? 
If you want to generate course reports based on the courses identified by regstats, you can use –f course-report -c forecasts -t TERM or TERM_TYPE. This will generate course reports for all courses listed in the forecast_data table that have forecasts for the specified TERM. 
