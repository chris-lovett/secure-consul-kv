#!/bin/bash
# cleanup.sh
# Removes test data and optionally team configurations
#
# Usage: ./cleanup.sh [OPTIONS]
# Options:
#   --test-data-only    Remove only test KV entries (default)
#   --team <TEAM_ID>    Remove specific team configuration
#   --all               Remove all team configurations (DANGEROUS)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
CLEANUP_MODE="test-data"
TEAM_ID=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test-data-only)
            CLEANUP_MODE="test-data"
            shift
            ;;
        --team)
            CLEANUP_MODE="team"
            TEAM_ID="$2"
            shift 2
            ;;
        --all)
            CLEANUP_MODE="all"
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--test-data-only|--team <TEAM_ID>|--all]"
            exit 1
            ;;
    esac
done

# Check prerequisites
if ! command -v consul &> /dev/null; then
    echo -e "${RED}Error: consul CLI not found${NC}"
    exit 1
fi

if [ -z "$CONSUL_HTTP_ADDR" ]; then
    echo -e "${RED}Error: CONSUL_HTTP_ADDR environment variable not set${NC}"
    exit 1
fi

if [ -z "$CONSUL_HTTP_TOKEN" ]; then
    echo -e "${RED}Error: CONSUL_HTTP_TOKEN environment variable not set${NC}"
    exit 1
fi

# Function to clean test data from a namespace
clean_test_data() {
    local namespace="$1"
    echo -e "${YELLOW}Cleaning test data from namespace: $namespace${NC}"
    
    # Delete test keys
    consul kv delete -recurse -namespace="$namespace" "${namespace}/test/" 2>/dev/null || true
    
    echo -e "${GREEN}✓ Test data cleaned from $namespace${NC}"
}

# Function to delete a team configuration
delete_team() {
    local team_id="$1"
    
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}WARNING: Deleting team configuration${NC}"
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Team: $team_id${NC}"
    echo -e "${RED}This will delete:${NC}"
    echo -e "${RED}  - All KV data in namespace $team_id${NC}"
    echo -e "${RED}  - ACL tokens for $team_id${NC}"
    echo -e "${RED}  - ACL policies for $team_id${NC}"
    echo -e "${RED}  - Namespace $team_id${NC}"
    echo ""
    read -p "Are you sure? Type 'DELETE' to confirm: " confirm
    
    if [ "$confirm" != "DELETE" ]; then
        echo -e "${YELLOW}Aborted${NC}"
        return
    fi
    
    echo ""
    echo -e "${YELLOW}Deleting team $team_id...${NC}"
    
    # 1. Delete all KV data
    echo -e "${YELLOW}  Deleting KV data...${NC}"
    consul kv delete -recurse -namespace="$team_id" "${team_id}/" 2>/dev/null || true
    echo -e "${GREEN}  ✓ KV data deleted${NC}"
    
    # 2. List and delete tokens
    echo -e "${YELLOW}  Finding tokens...${NC}"
    TOKENS=$(consul acl token list -namespace="$team_id" -format=json | jq -r '.[].AccessorID')
    for token_id in $TOKENS; do
        TOKEN_DESC=$(consul acl token read -id "$token_id" -format=json | jq -r '.Description')
        if [[ "$TOKEN_DESC" == *"$team_id"* ]]; then
            echo -e "${YELLOW}    Deleting token: $token_id${NC}"
            consul acl token delete -id "$token_id" 2>/dev/null || true
        fi
    done
    echo -e "${GREEN}  ✓ Tokens deleted${NC}"
    
    # 3. Delete policies
    echo -e "${YELLOW}  Deleting policies...${NC}"
    POLICY_NAME="${team_id,,}-kv-policy"
    consul acl policy delete -name "$POLICY_NAME" -namespace="$team_id" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Policies deleted${NC}"
    
    # 4. Delete namespace
    echo -e "${YELLOW}  Deleting namespace...${NC}"
    consul namespace delete -name "$team_id" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Namespace deleted${NC}"
    
    # 5. Delete token file
    if [ -f "tokens/${team_id}-token.txt" ]; then
        rm -f "tokens/${team_id}-token.txt"
        echo -e "${GREEN}  ✓ Token file deleted${NC}"
    fi
    
    echo -e "${GREEN}✓ Team $team_id completely removed${NC}"
    echo ""
}

# Main cleanup logic
case $CLEANUP_MODE in
    test-data)
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}Cleaning Test Data${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        
        # Get all namespaces
        NAMESPACES=$(consul namespace list -format=json | jq -r '.[].Name')
        
        for ns in $NAMESPACES; do
            if [[ "$ns" == AIT-* ]]; then
                clean_test_data "$ns"
            fi
        done
        
        echo ""
        echo -e "${GREEN}✓ All test data cleaned${NC}"
        ;;
        
    team)
        if [ -z "$TEAM_ID" ]; then
            echo -e "${RED}Error: Team ID required with --team option${NC}"
            exit 1
        fi
        
        delete_team "$TEAM_ID"
        ;;
        
    all)
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}WARNING: Deleting ALL team configurations${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        
        # Get all AIT namespaces
        NAMESPACES=$(consul namespace list -format=json | jq -r '.[].Name' | grep "^AIT-")
        
        if [ -z "$NAMESPACES" ]; then
            echo -e "${YELLOW}No AIT-* namespaces found${NC}"
            exit 0
        fi
        
        echo -e "${RED}The following teams will be deleted:${NC}"
        for ns in $NAMESPACES; do
            echo -e "${RED}  - $ns${NC}"
        done
        echo ""
        read -p "Are you ABSOLUTELY sure? Type 'DELETE ALL' to confirm: " confirm
        
        if [ "$confirm" != "DELETE ALL" ]; then
            echo -e "${YELLOW}Aborted${NC}"
            exit 0
        fi
        
        echo ""
        for ns in $NAMESPACES; do
            # Delete without confirmation since we already confirmed
            echo -e "${YELLOW}Deleting team $ns...${NC}"
            
            # Delete KV data
            consul kv delete -recurse -namespace="$ns" "${ns}/" 2>/dev/null || true
            
            # Delete tokens
            TOKENS=$(consul acl token list -namespace="$ns" -format=json | jq -r '.[].AccessorID')
            for token_id in $TOKENS; do
                consul acl token delete -id "$token_id" 2>/dev/null || true
            done
            
            # Delete policies
            POLICY_NAME="${ns,,}-kv-policy"
            consul acl policy delete -name "$POLICY_NAME" -namespace="$ns" 2>/dev/null || true
            
            # Delete namespace
            consul namespace delete -name "$ns" 2>/dev/null || true
            
            # Delete token file
            rm -f "tokens/${ns}-token.txt" 2>/dev/null || true
            
            echo -e "${GREEN}✓ Team $ns deleted${NC}"
        done
        
        echo ""
        echo -e "${GREEN}✓ All teams deleted${NC}"
        ;;
esac

echo ""
echo -e "${GREEN}Cleanup complete!${NC}"

# Made with Bob
