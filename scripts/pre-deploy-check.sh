#!/bin/bash
# Pre-Deployment Validation
#
# This script does NOT delete metadata. Every component in this repo is
# deployable as-is. If a check fails here, the fix is to retrieve the missing
# dependency from the source org -- not to exclude the metadata that references
# it.
#
# The only metadata excluded from deployment lives in .forceignore, and each
# entry there is justified by a hard org limitation (e.g. Network metadata
# cannot be retrieved by the CLI at all).

set -uo pipefail

DEFAULT_DIR="force-app/main/default"
SOURCE_DIR="${1:-$DEFAULT_DIR}"

echo "========================================="
echo "Pre-Deployment Validation"
echo "Source dir: ${SOURCE_DIR}"
echo "========================================="

FAILED=0

fail() {
    echo "  [FAIL] $1"
    FAILED=1
}

pass() {
    echo "  [OK]   $1"
}

# ---------------------------------------------------------------------------
# 1. Referenced objects, tabs, and quick actions must exist in the repo.
#    A "no X named Y found" error almost always means a partial retrieve.
# ---------------------------------------------------------------------------
check_references() {
    echo
    echo "Checking that referenced components exist locally..."

    # CustomTabs referenced by CustomApplications
    if [ -d "${SOURCE_DIR}/applications" ]; then
        local tabs
        tabs=$(grep -ho '<tab>[^<]*</tab>' "${SOURCE_DIR}/applications"/*.app-meta.xml 2>/dev/null \
            | sed 's|<tab>||; s|</tab>||' | sort -u)

        for tab in $tabs; do
            if [ ! -f "${SOURCE_DIR}/tabs/${tab}.tab-meta.xml" ]; then
                fail "CustomApplication references tab '${tab}' but ${SOURCE_DIR}/tabs/${tab}.tab-meta.xml is missing."
                echo "         Fix: sf project retrieve start --metadata CustomTab:${tab} --target-org <source-org>"
            fi
        done
        [ -n "$tabs" ] && pass "Application tab references resolved"
    fi

    # CustomFields referenced by Profiles
    if [ -d "${SOURCE_DIR}/profiles" ]; then
        local flds
        flds=$(grep -ho '<field>[A-Za-z0-9_]*__c</field>' "${SOURCE_DIR}/profiles"/*.profile-meta.xml 2>/dev/null \
            | sed 's|<field>||; s|</field>||' | sort -u)

        for fld in $flds; do
            local obj="${fld%%.*}"
            if [ ! -d "${SOURCE_DIR}/objects/${obj}" ]; then
                fail "Profile references field '${fld}' but object '${obj}' is not in the repo."
                echo "         Fix: sf project retrieve start --metadata CustomObject:${obj} --target-org <source-org>"
            fi
        done
        [ -n "$flds" ] && pass "Profile field references resolved"
    fi

    # EmailTemplates referenced by WorkflowAlerts
    if [ -d "${SOURCE_DIR}/workflows" ]; then
        local tmpls
        tmpls=$(grep -ho '<template>[^<]*</template>' "${SOURCE_DIR}/workflows"/*.workflow-meta.xml 2>/dev/null \
            | sed 's|<template>||; s|</template>||' | sort -u)

        for t in $tmpls; do
            local name="${t##*/}"
            if [ ! -f "${SOURCE_DIR}/email/${t}.email-meta.xml" ]; then
                fail "WorkflowAlert references template '${t}' but the email template is not in the repo."
                echo "         Fix: sf project retrieve start --metadata EmailTemplate:${name} --target-org <source-org>"
            fi
        done
        [ -n "$tmpls" ] && pass "Workflow email template references resolved"
    fi

    # QuickActions referenced by Layouts
    if [ -d "${SOURCE_DIR}/layouts" ]; then
        local qas
        qas=$(grep -ho '<actionName>[A-Za-z0-9_]*__c\.[A-Za-z0-9_]*</actionName>' "${SOURCE_DIR}/layouts"/*.layout-meta.xml 2>/dev/null \
            | sed 's|<actionName>||; s|</actionName>||' | sort -u)

        for qa in $qas; do
            if [ ! -f "${SOURCE_DIR}/quickActions/${qa}.quickAction-meta.xml" ]; then
                fail "Layout references QuickAction '${qa}' but it is not in the repo."
                echo "         Fix: sf project retrieve start --metadata QuickAction:${qa} --target-org <source-org>"
            fi
        done
        [ -n "$qas" ] && pass "Layout quick action references resolved"
    fi
}

# ---------------------------------------------------------------------------
# 2. LWC cross-bundle imports must resolve to a bundle in the repo.
#    "No MODULE named markup://c:X found" is a missing bundle, not a bad file.
# ---------------------------------------------------------------------------
check_lwc_imports() {
    echo
    echo "Checking Lightning Web Component imports..."

    if [ ! -d "${SOURCE_DIR}/lwc" ]; then
        pass "No LWC directory"
        return
    fi

    local missing=""

    # Cross-check: a bundle is only a problem if another bundle declares a
    # dependency on it and that bundle's directory is absent.
    for bundle in "${SOURCE_DIR}"/lwc/*/; do
        [ -d "$bundle" ] || continue
        local bname
        bname=$(basename "$bundle")
        # Only real component references: c/foo in import statements and
        # <c:foo> in templates. Filter out path segments like lightning/x.
        local deps
        deps=$(grep -rhoE "from 'c/[A-Za-z0-9_]+'|<c:[A-Za-z0-9_]+" "$bundle" 2>/dev/null \
            | grep -oE "c:[A-Za-z0-9_]+|c/[A-Za-z0-9_]+" \
            | sed -E 's|^c[:/]||' | sort -u)
        for d in $deps; do
            [ "$d" = "$bname" ] && continue
            if [ ! -d "${SOURCE_DIR}/lwc/${d}" ]; then
                missing="${missing}
         - '${bname}' references '${d}' which is not in the repo."
            fi
        done
    done

    if [ -n "$missing" ]; then
        fail "Dangling LWC references found:${missing}"
        echo "         Fix: sf project retrieve start --metadata LightningComponentBundle:<name> --target-org <source-org>"
    else
        pass "LWC references resolved"
    fi
}

# ---------------------------------------------------------------------------
# 3. Approval processes must only reference users that resolve.
#    Deploy hard-fails on a missing user, so this must be corrected in the
#    metadata itself by pointing at a user that exists in the target org.
# ---------------------------------------------------------------------------
check_approval_users() {
    echo
    echo "Checking approval process approvers..."

    if [ ! -d "${SOURCE_DIR}/approvalProcesses" ]; then
        pass "No approval processes"
        return
    fi

    # Collect usernames referenced as approvers/submitters.
    local users
    users=$(grep -rhoE "<(name|submitter)>[^<]+</(name|submitter)>" "${SOURCE_DIR}/approvalProcesses" 2>/dev/null \
        | sed -E 's|<name>||; s|</name>||; s|<submitter>||; s|</submitter>||' | grep '@' | sort -u)

    if [ -z "$users" ]; then
        pass "No hard-coded approvers"
        return
    fi

    echo "  Approval processes hard-code these users:"
    for u in $users; do
        echo "         - ${u}"
    done
    echo "  These must exist as active users in the TARGET org or the deploy fails."
    echo "  If one is missing, update the .approvalProcess-meta.xml to a user that exists."
    pass "Approver list reported for manual verification against the target org"
}

# ---------------------------------------------------------------------------
# 4. Block known secret-bearing metadata before it reaches the remote.
#    GitHub push protection rejects the whole push when a secret is committed,
#    and a retrieve can silently reintroduce one. Catch it here instead.
# ---------------------------------------------------------------------------
check_secrets() {
    echo
    echo "Checking for committed secrets..."

    local found=0

    # Custom Metadata records holding OAuth / API credentials.
    if [ -d "${SOURCE_DIR}/customMetadata" ]; then
        local f
        for f in "${SOURCE_DIR}"/customMetadata/*.md-meta.xml; do
            [ -f "$f" ] || continue
            # Evaluate each <values> block on its own: a credential field is
            # leaking only if the value in ITS OWN block is non-empty.
            # Use a non-greedy-safe match: split on the closing tag first, so a
            # block can't span across sibling <values> elements.
            local block
            block=$(tr '\n' ' ' < "$f" \
                | sed 's|</values>|</values>\n|g' \
                | grep -oE '<values>[^!]*?</values>' 2>/dev/null)
            for b in $block; do
                if echo "$b" | grep -qE '<field>[A-Za-z0-9_]*(ClientSecret|Secret|ApiKey|Password|AccessToken|PrivateKey)[A-Za-z0-9_]*</field>'; then
                    # A value is safe only if empty or explicitly nil.
                    if ! echo "$b" | grep -qE '<value[^>]*>[[:space:]]*</value>|nil="true"'; then
                        fail "Possible secret in $(basename "$f") -- a credential field has a non-empty value."
                        echo "         Blank the value and add the file to .forceignore, then rotate the credential."
                        found=1
                    fi
                fi
            done
        done
    fi

    # .env style files anywhere in the tree.
    local envs
    envs=$(find . -name '.env*' -not -path './node_modules/*' 2>/dev/null)
    if [ -n "$envs" ]; then
        fail "Environment file(s) present: $(echo "$envs" | tr '\n' ' ')"
        echo "         Add them to .gitignore and .forceignore."
        found=1
    fi

    if [ "$found" -eq 0 ]; then
        pass "No committed secrets detected in deployable metadata"
    fi
}

# ---------------------------------------------------------------------------
# 5. Report what .forceignore is holding back, so exclusions stay visible.
# ---------------------------------------------------------------------------
check_ignore_rules() {
    echo
    echo "Deployment exclusions declared in .forceignore:"
    if [ -f .forceignore ]; then
        grep -v '^\s*#' .forceignore | grep -v '^\s*$' | sed 's|^|  - |'
    else
        echo "  (none)"
    fi
    echo "  Each entry should be backed by an org limitation, not a workaround."
}

# ---------------------------------------------------------------------------

check_references
check_lwc_imports
check_approval_users
check_secrets
check_ignore_rules

echo
echo "========================================="
if [ "$FAILED" -eq 1 ]; then
    echo "Pre-Deployment Validation FAILED"
    echo "  Resolve the items above by retrieving the missing metadata from the"
    echo "  source org. Do not add them to .forceignore."
    echo "========================================="
    exit 1
fi
echo "Pre-Deployment Validation PASSED"
echo "========================================="
