# Notes

## bulk-rename

Format glob fix:
```bash
  ls | get name | each {|| let x = $in; let y = ($x | str replace -a '(?<eschar>[\[\]\?\*])' '[$eschar]'); mv $y $"new_($x)"}
```

Should it match the extension on its own?
Like so:

```bash
let extensions = $input
  | each { |p| match ($p | path type) {
      "file" => ($p | path parse | get extension),
      _ => "",
  }
}
```

No! Would be ambiguous for the .tar.gz extensions...
So no, it should NOT auto-match the extensions, as it creates too many
ambiguous moments

