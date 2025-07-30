use std/log
use std/assert

def is-extern-available [command: string] {
    which --all $command | any { $in.type == external }
}

def "assert extern-is-available" [...commands: string] {
    for cmd in $commands {
        assert (which --all $cmd | any { $in.type == external }) --error-label {
            text: $"`($cmd)` not found in PATH"
            span: (metadata $cmd).span
        }
    }
}

export-env {
    assert extern-is-available git gh
}

def open-pr [
    repo: directory
    remote: string
    pr: record<branch: string, title: string, body: string>
] {
    cd $repo
    ^gh repo set-default $remote

    log info "mock up pr"
    (
        ^gh pr create
        --head $pr.branch
        --base main
        --title $pr.title
        --body $pr.body
        --draft
    )
}

def clean [repo: path] {
    log info "removing the repo"
    rm -rf $repo
}

const example_version = $"0.((version).minor + 1).0"
const current_build_date = ((version).build_time | parse '{date} {_}').0.date

def "nu-complete version" [] { [$example_version] }
def "nu-complete date" [add?: duration = 0wk] {
    let date = (
        ^gh release list
        --repo "nushell/nushell"
        --exclude-drafts --exclude-pre-releases
        --limit 1
        --json "createdAt"
    )
    | from json
    | $in.0.createdAt
    | into datetime
    | $in + $add
    [{value: ($date | format date '%F') description: ($date | to text -n)}]
}
def "nu-complete date current" [] { nu-complete date 0wk }
def "nu-complete date next" [] { nu-complete date 6wk }

# open the release note PR interactively
@example "Create a PR for the next release" $"create-pr ($example_version) \(($current_build_date) + 6wk\)"
export def create-pr [
    version: string@"nu-complete version" # the version of the release
    date: datetime@"nu-complete date next" # the date of the upcoming release
] {
    let repo = ($nu.temp-path | path join (random uuid))
    let branch = $"release-notes-($version)"

    let blog_path = (
        $repo | path join "blog" $"($date | format date "%Y-%m-%d")-nushell_($version | str replace --all '.' '_').md"
    )

    let title = $"Release notes for `($version)`"
    let body = $"Please add your new features and breaking changes to the release notes
by opening PRs against the `release-notes-($version)` branch.

## TODO
- [ ] PRs that need to land before the release, e.g. [deprecations] or [removals]
- [ ] add the full changelog
- [ ] categorize each PR
- [ ] write all the sections and complete all the `TODO`s

[deprecations]: https://github.com/nushell/nushell/labels/deprecation
[removals]: https://github.com/nushell/nushell/pulls?q=is%3Apr+is%3Aopen+label%3Aremoval-after-deprecation"

    log info "creating release note from template"
    const template = path self template.md
    let release_note = open $template | str replace --all "{{VERSION}}" $version

    log info $"branch: ($branch)"
    log info $"blog: ($blog_path | path relative-to $repo | path basename)"
    log info $"title: ($title)"

    match (["yes" "no"] | input list --fuzzy "Inspect the release note document? ") {
        "yes" => {
            if $env.EDITOR? == null {
                error make --unspanned {
                    msg: $"(ansi red_bold)$env.EDITOR is not defined(ansi reset)"
                }
            }

            let temp_file = $nu.temp-path | path join $"(random uuid).md"
            [
                "<!-- WARNING: Changes made to this file are NOT included in the PR -->"
                ""
                $release_note
            ] | to text | save --force $temp_file
            ^$env.EDITOR $temp_file
            rm --recursive --force $temp_file
        },
        "no" | "" | _ => { }
    }

    match (["no" "yes"] | input list --fuzzy "Open release note PR? ") {
        "yes" => { },
        "no" | "" | _ => {
            log warning "aborting."
            return
        }
    }

    log info "setting up nushell.github.io repo"
    ^git clone https://github.com/nushell/nushell.github.io $repo --origin nushell --branch main --single-branch
    ^git -C $repo remote set-url nushell --push git@github.com:nushell/nushell.github.io.git

    log info "creating release branch"
    ^git -C $repo checkout -b $branch

    log info "writing release note"
    $release_note | save --force $blog_path

    log info "committing release note"
    ^git -C $repo add $blog_path
    ^git -C $repo commit -m $"($title)\n\n($body)"

    log info "pushing release note to nushell"
    ^git -C $repo push nushell $branch

    let out = (do -i { ^gh auth status } | complete)
    if $out.exit_code != 0 {
        clean $repo

        let pr_url = $"https://github.com/nushell/nushell.github.io/compare/($branch)?expand=1"
        error make --unspanned {
            msg: (
                [
                    $out.stderr
                    $"please open the PR manually from a browser (ansi blue_underline)($pr_url)(ansi reset)"
                ] | str join "\n"
            )
        }
    }

    log info "opening pull request"
    open-pr $repo nushell/nushell.github.io {
        branch: $"nushell:($branch)"
        title: $title
        body: $body
    }

    clean $repo
}

def md-link [text: string link: string] {
    $"[($text)]\(($link)\)"
}

# List all merged PRs since the last release
@example $"List all merged for ($example_version)" $"list-prs --milestone ($example_version)"
export def list-prs [
    repo: string = 'nushell/nushell' # the name of the repo, e.g. 'nushell/nushell'
    --since: datetime@"nu-complete date current" # list PRs on or after this date (defaults to 4 weeks ago if `--milestone` is not provided)
    --milestone: string@"nu-complete version" # only list PRs in a certain milestone
    --label: string # the PR label to filter by, e.g. 'good-first-issue'
] {
    mut query_parts = []

    if $since != null or $milestone == null {
        let date = $since | default ((date now) - 4wk) | format date '%Y-%m-%d'
        $query_parts ++= [$'merged:>($date)']
    }

    if $milestone != null {
        $query_parts ++= [$'milestone:"($milestone)"']
    }

    if $label != null {
        $query_parts ++= [$'label:($label)']
    }

    let query = $query_parts | str join ' '

    (
        ^gh --repo $repo pr list --state merged
        --limit (inf | into int)
        --json author,title,number,mergedAt,url
        --search $query
    )
    | from json
    | sort-by mergedAt --reverse
    | update author { get login }
}

# Format the output of `list-prs` as a markdown table
export def pr-table []: table<author: string, title: string, number: any> -> string {
    let input = sort-by author number
    let md_table = $input
    | update author { $'[($in)]' }
    | insert link {|pr| $'[#($pr.number)]' }
    | select author title link
    | to md --pretty

    let refs_author = $input.author | uniq | each {|e| $'[($e)]: https://github.com/($e)' }
    let refs_pr = $input.number | sort | each {|e| $'[#($e)]: https://github.com/nushell/nushell/pull/($e)' }

    $md_table
    | append ""
    | append $refs_author
    | append $refs_pr
    | to text
    | metadata set --content-type "text/markdown"
}

const toc = '[[toc](#table-of-contents)]'

# Generate and write the table of contents to a release notes file
export def write-toc [file: path] {
    let known_h1s = [
        "# Highlights and themes of this release"
        "# Changes"
        "# Notes for plugin developers"
        "# Hall of fame"
        "# Full changelog"
    ]

    let lines = open $file | lines | each { str trim -r }

    let content_start = 2 + (
        $lines
        | enumerate
        | where item == '# Table of contents'
        | first
        | get index
    )

    let data = (
        $lines
        | slice $content_start..
        | wrap line
        | insert level {
            get line | split chars | take while { $in == '#' } | length
        }
        | insert nocomment {
            # We assume that comments only have one `#`
            if ($in.level != 1) {
                return true
            }
            let line = $in.line

            # Try to use the whitelist first
            if ($known_h1s | any {|| $line =~ $in }) {
                return true
            }

            # We don't know so let's ask
            let user = (
                [Ignore Accept] | input list $"Is this a code comment or a markdown h1 heading:(char nl)(ansi blue)($line)(ansi reset)(char nl)Choose if we include it in the TOC!"
            )
            match $user {
                "Accept" => { true },
                "Ignore" => { false }
            }
        }
    )

    let table_of_contents = (
        $data
        | where level in 1..=3 and nocomment == true
        | each {|header|
            let indent = '- ' | fill -w ($header.level * 2) -a right

            let text = $header.line | str trim -l -c '#' | str trim -l
            let text = if $text ends-with $toc {
                $text | str substring ..<(-1 * ($toc | str length)) | str trim -r
            } else {
                $text
            }

            let link = (
                $text
                | str downcase
                | str kebab-case
            )

            $"($indent)[_($text)_]\(#($link)-toc\)"
        }
    )

    let content = $data | each {
        if $in.level in 1..=3 and not ($in.line ends-with $toc) and $in.nocomment {
            $'($in.line) ($toc)'
        } else {
            $in.line
        }
    }

    [
        ...($lines | slice ..<$content_start)
        ...$table_of_contents
        ...$content
    ]
    | save -r -f $file
}
