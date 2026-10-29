# CEDAR-PLATFORM: what "near full" and "full" mean, as seat fill rates
#
# Seat fill is enrollment at one named lifecycle point (first day, census)
# divided by scheduled seats. Two levels carry the words everywhere CEDAR uses
# them, so a page never calls a course full at two different levels:
#
#   near full  at least 90%: demand is pressing on the seats. Regstats'
#              chronic constraint, the projection floor, the projections
#              Day-1 fill column and Degree Explorer's seat pressure.
#   full       at least 98% on the first day of classes: the seats are taken.
#              Not 100%: capacity pools every section, and a course with a few
#              seats open across many section times is full to the students
#              choosing one (CHEM 1215 Spring 2026: 682 of 690, 98.8%). At 98%
#              a 50-seat course with one empty seat is full.
#
# Reader-facing definition: docs/_data/definitions.yml, seat-fill.
CEDAR_NEAR_FULL_FILL <- 0.90
CEDAR_FULL_FILL <- 0.98
