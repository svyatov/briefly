# Rulesets

Branch and tag protection lives on GitHub, not in this repository, so a clone shows nothing about
what guards `main` or the release tags. These three files are the bodies that were applied, kept here
so the settings are reviewable in a diff and reproducible if they are ever lost.

Editing a file here changes nothing on its own. Apply it, then read it back:

```sh
gh api -X PUT repos/svyatov/briefly/rulesets/RULESET_ID --input .github/rulesets/main.json
gh api repos/svyatov/briefly/rulesets/RULESET_ID
```

`POST` to `repos/svyatov/briefly/rulesets` creates a new one, so it stacks a second ruleset beside
the first and both then apply. Use `PUT` with the id from `gh api repos/svyatov/briefly/rulesets`
for anything that already exists.

## main.json

A pull request is the only path onto `main`, and it merges only when `CI`, `Analyze (ruby)` and
`Analyze (actions)` have passed. Force pushes and deletion are blocked, history stays linear, and
`bypass_actors` is empty, which means the rules bind the maintainer too.

`required_approving_review_count` is 0 on purpose. One person holds every merge path here, and
nobody can approve their own pull request, so requiring a review would make every change unmergeable
and the usual escape, adding an admin bypass entry, would undo the rest of the ruleset along with it.
Raise it to 1 the day a second person gets write access.

## tags-immutable.json and tags-creation.json

Two files rather than one, because a bypass list is granted per ruleset rather than per rule. The
immutable half blocks `update` and `deletion` on `refs/tags/v*` and exempts nobody, so a released tag
cannot be repointed or removed by anyone. The creation half restricts who may cut a release, and its
bypass list is the point rather than a hole in it: with an empty list nobody could tag a release at
all. Merging the two would hand whoever can cut a release the power to move an old one.
