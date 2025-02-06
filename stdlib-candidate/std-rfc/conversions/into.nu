# Convert a Nushell value to a list
# 
# Primary useful for range-to-list,
# but other types are accepted as well.
# 
# Example:
#
# 1..10 | into list
@example "Convert a range to a list" {
  1..10 | into list
} --result [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
export def "into list" []: any -> list {
  let input = $in
  let type = ($input | describe --detailed | get type)
  match $type {
    range => {$input | each {||}}
    list => $input
    table => $input
    _ => [ $input ]
  }
}
