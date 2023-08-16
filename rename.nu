use std assert
use std log

# if same group matches multiple times, for each
# match another row in the corresponding capture column
# is created.
# If string then single-match-regex length = 1
# if list   then single-match-regex length = list-length

# Given a regular expression, find the **unambiguous** capture groups
# in the input and return a single string that joins the capture groups
# with `separator`.
# If no matches are found, `null` is returned.
# TODO: figure out how to describe how my input $in should look like!
export def "str regex-match-join" [inp: string, regex: string, separator: string = ""] {
  let regex_span = (metadata $regex).span;
  let matches = $inp | parse --regex $regex
  # if matches == length = 0 then 
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
  # there is only 1 line!
  # match doesn't really handle null yet.
  $matches | values | each {str join $separator} | match $in {
    "" => null,
    [$x] => $x, 
  }
}

export def "list str regex-match-join" [inp: list<string>, regex: string, separator: string = ""] {
  $inp | each --keep-empty {
    |x|
    try {
      str regex-match-join $x $regex separator=$separator
    } catch {
      log warning $"Filtering out ambiguous regular expression match: re=($regex) inp=($x)"
      null
    }
  }
}

# weird format fix:
# ls | get name | each {|| let x = $in; let y = ($x | str replace -a '(?<eschar>[\[\]\?\*])' '[$eschar]'); mv $y $"new_($x)"}
# Should it match the extension on its own?
# Would be ambiguous for the .tar.gz extensions...
# So no, it should NOT auto-match the extensions, as it creates too many
# ambiguous moments
# let extensions = $input
#   | each { |p| match ($p | path type) {
#       "file" => ($p | path parse | get extension),
#       _ => "",
#   }
# }

# TODO: Find a different name!
def "rename regex" [regex: string, separator: string = ""] {
  # table with in, result
  let input = $in
  let result = list str regex-match-join $input $regex separator=$separator

  # cannot figure out how to dynamically create the 'full' compact version
  let res = $input | wrap "source" | merge (
    $result | wrap "destination"
  ) | compact "source" "destination"

  # TODO: Add a test case for this!
  # early exit if no matches were found!
  if ($res | is-empty) {
    log warning 'No matches found. Did you forget capture groups?'
    # could argue to use empty over null...
    return null
  }

  # print $res

  let dest_collisions = (
    $res
    | group-by destination
    | transpose destination matchtable
    | where {|x| ($x.matchtable | length) > 1 }
  )

  if ($dest_collisions | length) > 0 {
    # print $dest_collisions
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

export def "renamer" [regex: string, separator: string = "", --interactive, --dry-run] {
  # TODO: Make this the own command!
  # Load variables and then actually move the data.
  # As my checks prevent overwriting the source, the classic ^mv
  # should work
  let mapping = $in | rename regex $regex $separator

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
  assert equal (str regex-match-join "abc" `(\w+)`) "abc"
  # multiple matches for input!
  assert equal (str regex-match-join "abc" `(\d+)`) null
  assert error {str regex-match-join "abc" `(\w)`}
  # for whatever reason, it does not fail if an integer is given
  assert error {str regex-match-join 1.3 `(\w)`}
}

#[test]
def test_list_regex_match_join [] {  
  assert equal (list str regex-match-join ["abc"] `(\w+)`) ["abc"]
  assert equal (list str regex-match-join ["abc"] `(\w)`) [null]
  assert equal (list str regex-match-join ["abc" "d" "e"] `(\w+)`) ["abc", "d", "e"]
}

#[test]
def test_rename_regex [] {
  # ["A S01"] | rename regex `(S\d\d)`
  assert equal ( ["Some series - S01"] | rename regex `(S\d\d)` | get destination) ["S01"]
  assert equal (["S01" "S02"] | rename regex '(S\d\d)') [[source destination]; [S01 S01] [S02 S02]]
}

#[test]
def test_rename_regex_empty [] {
  # forget to set matching group
  assert equal ( ["S01"] | rename regex 'S\d\d') null
  assert equal ( [""] | rename regex '(S\d\d)') null
}

#[test]
def test_rename_regex_multi_matches [] {
  assert error { ["S01" "S01"] | rename regex '(S\d\d)' }
  assert error { ["S01 A" "S01 B"] | rename regex '(S\d\d)' }
}
