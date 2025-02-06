use ../conversions/into.nu *

# Return a list of indices
# for the provided ranges or indices.
# Primarily used as a helper for
# "select ranges" et. al.
@example "Usage" { row-indices 0 2..5 7..8 } --result [0, 2, 3, 4, 5, 7, 8]
export def main [ ...ranges ] {
  $ranges
  | reduce -f [] {|range,indices|
    $indices ++ ($range | into list)
  }
}
