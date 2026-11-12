#!/bin/sh

set -eu

repository_root=$(git rev-parse --show-toplevel)
stage_changes=false

if [ "${1:-}" = "--stage" ]; then
    stage_changes=true
elif [ "$#" -ne 0 ]; then
    echo "Usage: $0 [--stage]" >&2
    exit 2
fi

find "$repository_root" -name project.pbxproj -type f -not -path '*/.git/*' -print |
while IFS= read -r project_file; do
    temporary_file=$(mktemp "${TMPDIR:-/tmp}/signaltrail-pbxproj.XXXXXX")
    trap 'rm -f "$temporary_file"' EXIT HUP INT TERM

    awk '
        !/^[[:space:]]*(DEVELOPMENT_TEAM|DevelopmentTeam|PROVISIONING_PROFILE|PROVISIONING_PROFILE_SPECIFIER|CODE_SIGN_IDENTITY|EXPANDED_CODE_SIGN_IDENTITY)[[:space:]]*=/
    ' "$project_file" > "$temporary_file"

    if ! cmp -s "$project_file" "$temporary_file"; then
        mv "$temporary_file" "$project_file"
        echo "Removed local Xcode signing identifiers from ${project_file#"$repository_root"/}."
    else
        rm -f "$temporary_file"
    fi

    if [ "$stage_changes" = true ]; then
        git -C "$repository_root" add -- "$project_file"
    fi

    trap - EXIT HUP INT TERM
done
