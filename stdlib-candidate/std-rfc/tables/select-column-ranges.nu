use ./col-indices.nu *

# Select a range of columns by their indices
@example "Ran in the nushell repository" {
    ls -l | select column-ranges 0 10..12 | first 3
} --result [
    [ name, created, accessed, modified ];
    [ "CITATION.cff", 2024-07-22T10:23:12.491342329+03:00, 2024-07-22T10:23:12.491342329+03:00, 2024-07-22T10:23:12.491342329+03:00 ],
    [ "CODE_OF_CONDUCT.md", 2024-05-17T22:23:48.223428848+03:00, 2024-05-17T22:23:48.223428848+03:00, 2024-05-17T22:23:48.223428848+03:00 ],
    [ "CONTRIBUTING.md", 2024-07-22T10:23:12.494675698+03:00, 2024-07-22T10:23:12.494675698+03:00, 2024-07-22T10:23:12.494675698+03:00 ]
]
export def "select column-ranges" [
    ...ranges
] {
    let column_selector = ($in | col-indices ...$ranges)
    $in | select ...$column_selector
}
