* Put line buffering in (removed blanket output buffering to get feedback when
  tailing infrequent/small files)

* Add option to print decoded strings/numbers (instead of raw)

* Add option (or default?) to also print "junk" whenever a parsing error occurs
  (for tailing logfiles that intersperse JSON with non-JSON data)
