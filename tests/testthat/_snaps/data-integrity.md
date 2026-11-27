# the refresh log shows each table's verdict and every term, failures first

    Code
      cat(format_student_id_integrity(ids_result()), sep = "\n")
    Output
      Student IDs against ids_spine: 4 IDs in 2 terms.
      ids_orphan             no overlap  2 terms: 0 full, 0 partial, 2 with no match, 0 not judged; 0.0% of its IDs match
      ids_split              split       2 terms: 1 full, 0 partial, 1 with no match, 0 not judged; 50.0% of its IDs match
      ids_ahead              consistent  2 terms: 0 full, 1 partial, 0 with no match, 1 not judged; 25.0% of its IDs match
      ids_clean              consistent  2 terms: 2 full, 0 partial, 0 with no match, 0 not judged; 100.0% of its IDs match
      ids_partial            consistent  2 terms: 0 full, 2 partial, 0 with no match, 0 not judged; 50.0% of its IDs match
      By term (a term the class lists do not hold, with no match, is not judged):
             table   term ids matched   pct   status
        ids_orphan 202410   2       0   0.0     none
        ids_orphan 202480   2       0   0.0     none
         ids_split 202410   2       0   0.0     none
         ids_ahead 202410   2       1  50.0  partial
       ids_partial 202410   2       1  50.0  partial
       ids_partial 202480   2       1  50.0  partial
         ids_ahead 202510   2       0   0.0 unjudged
         ids_clean 202410   4       4 100.0     full
         ids_clean 202480   4       4 100.0     full
         ids_split 202480   2       2 100.0     full

