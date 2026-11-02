---
id: sequelizer-25a
title: 'Upstream the shfmt fix that keeps comments in empty zsh statement lists: issue first or PR'
status: captured
type: decision
created_at: 2026-11-02T20:17:43.828952+00:00
updated_at: 2026-11-02T20:17:43.828952+00:00
tags:
  - shfmt
  - upstream
  - gator
  - zsh
---

Not ruled. Ryan said on 2026-11-02: "make a seed about all of this and we'll come back to it later this week".

## How this started

Sequelizer 0.5.0 was released on 2026-11-02 without a gator-doctor run first. Ryan said: "we should have run gator doctor before release". The doctor run after the release found two serious items and six minor items, and all of them are fixed on main (commits 75fc904, 837d819, 08ab67e, e43ac30).

One of the minor fixes copied gator's shfmt-zsh treefmt block (`shfmt -ln zsh -w`). `just fmt` then deleted two comment lines from `.devcontainer/.p10k.zsh`, a file that `p10k configure` writes. The two comment lines were the whole body of an `elif` branch:

```
    elif [[ -n $VCS_STATUS_REMOTE_BRANCH ]]; then
      # Tip: Uncomment the next line to display '=' if up to date with the remote.
      # res+=" ${clean}="
    fi
```

The file was restored, and treefmt.toml now excludes it (commit 08ab67e). `zsh -n` in `lint` still checks it. Ryan ruled: "do the exclude for now".

The gator session filed gator-dc4 for the standard's response. It reproduced the bug on shfmt 3.14.1. It found that only this file is affected among the 17 tracked .zsh files in the fleet.

## No shfmt version avoids the bug (measured)

Log: `claude_stuff/shfmt-versions-20261102-111848.log`.

- shfmt 3.10.0 to 3.12.0 have no zsh support: `unknown shell language variant: "zsh"`.
- shfmt 3.13.0 to 3.14.1 delete the comments and exit 0.
- Upstream master had 179 commits after v3.14.1, and none of them fixes this.

## The fix (local, not sent upstream)

The fix is in a clone at `~/projects/oss/sh`, on branch `zsh-empty-list-comments`, based on master 14254e11. It has two commits, in the form that upstream's AGENTS.md requires:

- 32488ede adds test cases that assert the current wrong output.
- 52b70a6a fixes the bug and changes the tests to expect the comments.

The cause is in `followStmts` in `syntax/parser.go`. For an empty list in zsh or mksh, it returned `nil, nil`, which discarded the comments that `stmtList` had collected. The fix returns `nil, last`. A second one-line change in `syntax/printer.go` stops an empty subshell that holds comments from printing a trailing space after `(`.

Constructs that lost comments before the fix: if, elif and else branches, while and for bodies, `{ }` blocks, subshells and function bodies. 9 of 10 test comments were lost in zsh and in mksh. Only the case item kept its comment.

Checks (logs in `claude_stuff/shfmt-*-20261102-*.log`):

- `go test ./...`, the race detector, GOARCH=386, gofmt and go vet pass.
- A 3-minute FuzzParsePrint run tested 11 million inputs and found no failures. That run skipped one older crash pattern, described below.
- A churn check compared shfmt before and after the fix. Output was identical for 1,617 bash, 1,585 mksh and 2,011 zsh files. Only 2 zsh files changed: two copies of `VCS_INFO_get_data_hg` from zsh's own function library. They keep `# leave curbm empty and [hg-active-bookmark] undefined.`, which released shfmt deletes.
- Real zsh accepts every test input. Real mksh R59c rejects any empty if body, so the if tests claim zsh only.

## What is still open

1. **An issue or a PR upstream.** The shfmt README says: "Unless you're an active user or contributor to the project, drive-by AI patches are not helpful. File detailed issues instead." Ryan has no commits in mvdan/sh. The recommendation is to open an issue that offers the PR. The draft is at `claude_stuff/shfmt-issue-draft.md`.
2. **A fork and a push.** To open a PR, fork mvdan/sh to aguynamedryan and push the branch. Nothing is pushed yet.
3. **A second upstream bug found by the fuzzer.** The input below panics with a nil pointer dereference in the mksh parser with KeepComments(true). Unmodified master panics the same way, so it is unrelated to the fix. The crash files are in `claude_stuff/shfmt-fuzz-crashers/`.

```
"`<<"
```

4. **Tell gator** that a tested fix exists. gator-dc4 lists an upstream report as one option.
5. **Remove the exclude** for `.devcontainer/.p10k.zsh` from treefmt.toml after a shfmt release has the fix.

Older shfmt behavior seen during the work, which is not part of the fix: an empty `(` subshell followed by a newline prints with a trailing space. When a bash if body ends with a comment, `IfClause.Last` is an empty slice instead of nil. Neither one changes what users see.
