use ./row-indices.nu *

# Selects one or more rows while keeping
# the original indices.
@example "Selects the first, fifth, and sixth rows from the table" {
  ls / | select ranges 0 4..5
}
@example "Select the 5th row" {
  ls / | select 5
}
@example "Select the 4th row." {
  ls / | select ranges 3
}
export def "select ranges" [ ...ranges ] {
  enumerate
  | flatten
  | select ...(row-indices ...$ranges)
}
