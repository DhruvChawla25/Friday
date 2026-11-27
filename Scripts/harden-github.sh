#!/usr/bin/env bash
# Applies Friday's GitHub safety settings. Run by the owner only.
# Safe to run more than once.
set -euo pipefail
R=repos/DhruvChawla25/Friday

echo "1/6 Ruleset: outside pull requests need the owner's approval"
# Owner (admin role, id 5) may skip this ruleset only when merging a PR, never
# for direct pushes. "Protect main" still applies to everyone (CI, no force push).
existing=$(gh api "$R/rulesets" --jq '.[] | select(.name=="Owner approval for outside PRs") | .id')
method=POST; path="$R/rulesets"
[ -n "$existing" ] && method=PUT && path="$R/rulesets/$existing"
gh api -X "$method" "$path" --input - --jq '"   ruleset \(.id) \(.enforcement)"' <<'EOF'
{"name":"Owner approval for outside PRs","target":"branch","enforcement":"active",
 "bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}],
 "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
 "rules":[{"type":"pull_request","parameters":{
   "required_approving_review_count":1,"require_code_owner_review":true,
   "require_last_push_approval":true,"dismiss_stale_reviews_on_push":true,
   "required_review_thread_resolution":true,"allowed_merge_methods":["squash","rebase"]}}]}
EOF

echo "2/6 CI from forks waits for your approval (every outside contributor)"
gh api -X PUT "$R/actions/permissions/fork-pr-contributor-approval" -f approval_policy=all_external_contributors

echo "3/6 Only GitHub-owned actions may run"
gh api -X PUT "$R/actions/permissions" -F enabled=true -f allowed_actions=selected
gh api -X PUT "$R/actions/permissions/selected-actions" -F github_owned_allowed=true -F verified_allowed=false

echo "4/6 Private vulnerability reporting"
gh api -X PUT "$R/private-vulnerability-reporting"

echo "5/6 Dependabot security fixes + extra secret scanning"
gh api -X PUT "$R/automated-security-fixes"
gh api -X PATCH "$R" --input - --jq '"   " + (.security_and_analysis | to_entries | map("\(.key)=\(.value.status)") | join(", "))' <<'EOF'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},
 "secret_scanning_push_protection":{"status":"enabled"},
 "secret_scanning_non_provider_patterns":{"status":"enabled"},
 "secret_scanning_validity_checks":{"status":"enabled"}}}
EOF

echo "6/6 Turn off the wiki (unused, one less thing to moderate)"
gh api -X PATCH "$R" -F has_wiki=false --jq '"   wiki=\(.has_wiki)"'

echo "Done. Rulesets now active:"
gh api "$R/rulesets" --jq '.[] | "   - \(.name) (\(.enforcement))"'
