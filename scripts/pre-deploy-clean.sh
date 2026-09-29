#!/bin/bash
# Pre-Deployment Validation and Cleanup Script
# This script cleans metadata that commonly causes deployment failures

set -e

echo "========================================="
echo "Pre-Deployment Validation and Cleanup"
echo "========================================="

# Function to remove profiles with specific patterns
clean_profiles() {
    echo "Cleaning profile-related metadata..."

    # Remove profilePasswordPolicies
    if [ -d "force-app/main/default/profilePasswordPolicies" ]; then
        echo "  - Removing profilePasswordPolicies/"
        rm -rf force-app/main/default/profilePasswordPolicies
    fi

    # Remove profileSessionSettings
    if [ -d "force-app/main/default/profileSessionSettings" ]; then
        echo "  - Removing profileSessionSettings/"
        rm -rf force-app/main/default/profileSessionSettings
    fi
}

# Function to clean approval processes with invalid user references
clean_approval_processes() {
    echo "Cleaning approval processes..."

    if [ -d "force-app/main/default/approvalProcesses" ]; then
        # List of common test/dev user patterns that won't exist in target org
        INVALID_USER_PATTERNS=(
            "vikash.jkp@gmail.com"
            "nazirahmed.patel@utilitarianlabs.com"
            "@test.com"
            "@dev.com"
        )

        for pattern in "${INVALID_USER_PATTERNS[@]}"; do
            echo "  - Checking for user pattern: $pattern"
            if grep -r "$pattern" force-app/main/default/approvalProcesses/ 2>/dev/null; then
                echo "    WARNING: Found approval processes with invalid user: $pattern"
                echo "    Consider removing or updating these approval processes"
            fi
        done
    fi
}

# Function to clean Experience Cloud metadata
clean_experience_cloud() {
    echo "Cleaning Experience Cloud metadata..."

    # Remove networkBranding
    if [ -d "force-app/main/default/networkBranding" ]; then
        echo "  - Removing networkBranding/"
        rm -rf force-app/main/default/networkBranding
    fi

    # Remove audience
    if [ -d "force-app/main/default/audience" ]; then
        echo "  - Removing audience/"
        rm -rf force-app/main/default/audience
    fi
}

# Function to clean field restriction rules
clean_field_restrictions() {
    echo "Cleaning field restriction rules..."

    if [ -d "force-app/main/default/fieldRestrictionRules" ]; then
        echo "  - Removing fieldRestrictionRules/"
        rm -rf force-app/main/default/fieldRestrictionRules
    fi
}

# Function to validate LWC dependencies
validate_lwc() {
    echo "Validating LWC components..."

    # Check for partnerWebPortalMyTeam
    if [ -f "force-app/main/default/lwc/partnerWebPortalMyTeam/partnerWebPortalMyTeam.js" ]; then
        if grep -q "partnerWebPortalAddMember" force-app/main/default/lwc/partnerWebPortalMyTeam/partnerWebPortalMyTeam.js; then
            # Check if dependency exists
            if [ ! -d "force-app/main/default/lwc/partnerWebPortalAddMember" ]; then
                echo "  WARNING: partnerWebPortalMyTeam has missing dependency: partnerWebPortalAddMember"
                echo "  - Removing partnerWebPortalMyTeam/"
                rm -rf force-app/main/default/lwc/partnerWebPortalMyTeam
            fi
        fi
    fi
}

# Function to clean flowDefinitions
clean_flow_definitions() {
    echo "Cleaning flow definitions..."

    if [ -d "force-app/main/default/flowDefinitions" ]; then
        echo "  - Removing flowDefinitions/"
        rm -rf force-app/main/default/flowDefinitions
    fi
}

# Main execution
echo ""
clean_profiles
echo ""
clean_approval_processes
echo ""
clean_experience_cloud
echo ""
clean_field_restrictions
echo ""
validate_lwc
echo ""
clean_flow_definitions
echo ""
echo "========================================="
echo "Pre-Deployment Cleanup Complete"
echo "========================================="
