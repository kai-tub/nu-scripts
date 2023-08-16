use std assert
use std log


# Given a regular expression, find the **unambiguous** capture groups
# in the input and return a single string that joins the capture groups
# with `separator`.
# If no matches are found, `null` is returned.
export def "regex join-matches from-str" [regex: string, separator: string = ""] {
  let inp = $in | into string
  # here I could add type checking
  let regex_span = (metadata $regex).span;
  let matches = $inp | parse --regex $regex
  if ($matches | length) > 1 {
    error make {
      msg: ('Only unambigious groups are allowed!
            Please update the regular expression to only match _once_
            for the given input:
            ' + $inp),
      label: {
        text: "ambiguous regex"
        start: $regex_span.start
        end: $regex_span.end
      }
    }
  }
  # there is only 1 line
  $matches | values | each {str join $separator} | match $in {
    "" => null,
    [$x] => $x, 
  }
}

# Given a regular expression, find the **unambiguous** capture groups
# in each row and return a single string per row that joins the capture groups
# with `separator`.
# For each row that does _not_ contain a match a null is returned.
# Use `compact` to drop them from the output.
export def "regex join-matches from-list" [regex: string, separator: string = ""] {
  let inp = $in | into string
  $inp | each --keep-empty {
    |x|
    try {
      $x | regex join-matches from-str $regex separator=$separator
    } catch {
      log warning $"Filtering out ambiguous regular expression match: re=($regex) inp=($x)"
      null
    }
  }
}

# Given a regular expression, find the **unambiguous** capture groups
# per string in the input (string or list<string>) and join the capture
# groups of each row with `separator`.
# `regex join-matches from-str` and `regex join-matches` from-list for more details!
export def "regex join-matches" [regex: string, separator: string = ""] {
  let inp = $in
  match ($inp | describe) {
    string => {$inp | regex join-matches from-str $regex $separator},
    _ => {$inp | regex join-matches from-list $regex $separator}
  } 
}

# Main logic of the bulk-rename function
# Simply apply `regex join-matches` to the input
# and create a `source` table with the original inputs
# and a `destination` column that contains the result of
# the join operation.
# If multiple sources are mapped to the same output, an error is raised.
def "bulk-rename main" [regex: string, separator: string = ""] {
  # table with in, result
  let input = $in
  let result = $input | regex join-matches $regex separator=$separator

  # cannot figure out how to dynamically create the 'full' compact version
  let res = $input | wrap "source" | merge (
    $result | wrap "destination"
  ) | compact "source" "destination"

  if ($res | is-empty) {
    log warning 'No matches found. Did you forget capture groups?'
    # could argue to use empty over null...
    return null
  }

  let dest_collisions = (
    $res
    | group-by destination
    | transpose destination matchtable
    | where {|x| ($x.matchtable | length) > 1 }
  )

  if ($dest_collisions | length) > 0 {
    error make {
      msg: (
        $'Multiple source files share the same destination!
        Stopping execution to avoid data loss!
        ($dest_collisions)'
      )
    }
  }

  $res
}

# Given an input `list<string>` apply a regular expression
# that matches _unambiguous_ capture groups and joins them
# via a provided separator.
export def "bulk-rename" [
  regex: string, # Regular expression *with* capture group(s).
  separator: string = "", # Separator that is used to join capture groups.
  --interactive, # Show source/destination map and wait for confirmation.
  --dry-run, # Only print source/destination and do not actually rename files.
] {
  # As my checks prevent overwriting the source, the classic ^mv
  # should work
  let mapping = $in | bulk-rename main $regex $separator

  if $dry_run {
    print "Did you remember to:"
    print $"- match the file (ansi i)extension(ansi reset) \(if needed\)"
    print $"- provide (ansi i)unique(ansi reset) regular expression matches"
    print $mapping
    return ($mapping | each {|r| $"^mv ($r.source) ($r.destination)" } | str join '\n')
  }

  if $interactive {
    print $mapping
    let selection = [yes no] | input list "Does the following result look good?"
    if selection == no {
      return null
    }
  }

  $mapping | each {|r| ^mv $r.source $r.destination }
}

#[test]
def test_str_regex_match_join [] {
  assert equal ("abc" | regex join-matches from-str `(\w+)`) "abc"
  # multiple matches for input!
  assert equal ("abc" | regex join-matches from-str `(\d+)`) null
  assert error {"abc" | regex join-matches from-str `(\w)`}
  # for whatever reason, it does not fail if an integer is given
  assert error {{i: "am record"} | regex join-matches from-str `(\w)`}
}

#[test]
def test_list_regex_match_join [] {  
  assert equal (["abc"] | regex join-matches from-list `(\w+)`) ["abc"]
  assert equal (["abc"] | regex join-matches from-list `(\w)`) [null]
  assert equal (["abc" "d" "e"] | regex join-matches from-list `(\w+)`) ["abc", "d", "e"]
}

#[test]
def test_rename_regex [] {
  # ["A S01"] | rename regex `(S\d\d)`
  assert equal ( ["Some series - S01"] | bulk-rename main `(S\d\d)` | get destination) ["S01"]
  assert equal (["S01" "S02"] | bulk-rename main '(S\d\d)') [[source destination]; [S01 S01] [S02 S02]]
}

#[test]
def test_rename_regex_empty [] {
  # forget to set matching group
  assert equal ( ["S01"] | bulk-rename main 'S\d\d') null
  assert equal ( [""] | bulk-rename main '(S\d\d)') null
}

#[test]
def test_rename_regex_multi_matches [] {
  assert error { ["S01" "S01"] | bulk-rename main '(S\d\d)' }
  assert error { ["S01 A" "S01 B"] | bulk-rename main '(S\d\d)' }
}
