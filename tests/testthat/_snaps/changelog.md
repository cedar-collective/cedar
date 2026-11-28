# a release lists its items by what each does for a reader, escaped

    Code
      cat(format_changelog_html(list(entry)), sep = "\n")
    Output
      <div class='changelog-entry'><div class='changelog-date'>2026-01-01</div><h4 class='changelog-title'>A &amp; B <span class='changelog-version'>v0.0.1</span></h4></div><ul><li><strong>New.</strong> A page for &lt;id&gt;.</li><li><strong>Clearer.</strong> Each count says who it counts.</li><li><strong>Under the hood.</strong> Tests run faster.</li></ul>

