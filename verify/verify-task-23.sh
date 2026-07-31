#!/bin/bash
# Verify Task 23: kubectl JSONPath and Custom Columns
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

CTX="k8s"
PASS_COUNT=0; FAIL_COUNT=0

echo -e "${BOLD}═══ Verifying Task 23: kubectl JSONPath and Custom Columns ══════${NC}"
use_context "$CTX"

# ── Query 1: Node InternalIPs ─────────────────────────────────────────────────

echo -e "\n  ${BOLD}Query 1 — Node InternalIPs → /tmp/task23-node-ips.txt${NC}"

if [ ! -f /tmp/task23-node-ips.txt ]; then
    check_fail "File /tmp/task23-node-ips.txt does not exist"
    echo -e "     ${YELLOW}Run the jsonpath query and redirect output to the file${NC}"
else
    FILE_CONTENT=$(tr -s '[:space:]' '\n' < /tmp/task23-node-ips.txt | grep -v '^$' | sort)

    # Get expected IPs from the live cluster
    EXPECTED=$(kubectl get nodes \
        -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' \
        2>/dev/null | grep -v '^$' | sort)

    if [ -z "$EXPECTED" ]; then
        check_fail "Could not retrieve node IPs from cluster"
    elif [ -z "$FILE_CONTENT" ]; then
        check_fail "File /tmp/task23-node-ips.txt is empty"
    else
        # Compare sorted content (tolerates different newline styles)
        MISSING=$(comm -23 <(echo "$EXPECTED") <(echo "$FILE_CONTENT") 2>/dev/null)
        if [ -z "$MISSING" ]; then
            NODE_COUNT=$(echo "$FILE_CONTENT" | wc -l)
            check_pass "File contains all ${NODE_COUNT} node InternalIP(s): $(echo "$FILE_CONTENT" | tr '\n' ' ')"
        else
            check_fail "File missing some node IPs. Expected: $(echo "$EXPECTED" | tr '\n' ' ')" \
                "Got: $(echo "$FILE_CONTENT" | tr '\n' ' ')"
        fi
    fi
fi

# ── Query 2: Pod names in kube-system ────────────────────────────────────────

echo -e "\n  ${BOLD}Query 2 — kube-system pod names → /tmp/task23-kube-system-pods.txt${NC}"

if [ ! -f /tmp/task23-kube-system-pods.txt ]; then
    check_fail "File /tmp/task23-kube-system-pods.txt does not exist"
else
    FILE_PODS=$(tr -s '[:space:]' '\n' < /tmp/task23-kube-system-pods.txt | grep -v '^$' | sort)
    EXPECTED_PODS=$(kubectl -n kube-system get pods \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null \
        | tr ' ' '\n' | grep -v '^$' | sort)

    if [ -z "$FILE_PODS" ]; then
        check_fail "File /tmp/task23-kube-system-pods.txt is empty"
    else
        MISSING_PODS=$(comm -23 <(echo "$EXPECTED_PODS") <(echo "$FILE_PODS") 2>/dev/null)
        POD_COUNT=$(echo "$FILE_PODS" | wc -l)
        if [ -z "$MISSING_PODS" ]; then
            check_pass "File contains all ${POD_COUNT} kube-system pod names"
        else
            check_fail "File is missing some kube-system pod names: ${MISSING_PODS}" \
                "Expected ${POD_COUNT} pods — re-run the jsonpath query"
        fi
    fi
fi

# ── Query 3: kube-apiserver image ────────────────────────────────────────────

echo -e "\n  ${BOLD}Query 3 — kube-apiserver image → /tmp/task23-apiserver-image.txt${NC}"

APISERVER_POD=""
for pod_name in \
    "kube-apiserver-k8s-control-plane" \
    "kube-apiserver-control-plane" \
    "kube-apiserver"; do
    if kubectl -n kube-system get pod "$pod_name" &>/dev/null; then
        APISERVER_POD="$pod_name"
        break
    fi
done

if [ ! -f /tmp/task23-apiserver-image.txt ]; then
    check_fail "File /tmp/task23-apiserver-image.txt does not exist"
else
    FILE_IMAGE=$(tr -d '[:space:]' < /tmp/task23-apiserver-image.txt)

    if [ -z "$APISERVER_POD" ]; then
        # Fallback: check if file has any registry.k8s.io image
        if echo "$FILE_IMAGE" | grep -q "kube-apiserver"; then
            check_pass "File contains a kube-apiserver image: $FILE_IMAGE"
        else
            check_fail "Could not verify — kube-apiserver pod not found and file content looks wrong: '${FILE_IMAGE}'"
        fi
    else
        EXPECTED_IMAGE=$(kubectl -n kube-system get pod "$APISERVER_POD" \
            -o jsonpath='{.spec.containers[0].image}' 2>/dev/null | tr -d '[:space:]')

        if [ -z "$FILE_IMAGE" ]; then
            check_fail "File /tmp/task23-apiserver-image.txt is empty"
        elif [ "$FILE_IMAGE" = "$EXPECTED_IMAGE" ]; then
            check_pass "File contains correct kube-apiserver image: $FILE_IMAGE"
        elif echo "$FILE_IMAGE" | grep -q "kube-apiserver"; then
            check_fail "File has a kube-apiserver image but it doesn't match exactly" \
                "Got: '$FILE_IMAGE'  Expected: '$EXPECTED_IMAGE'"
        else
            check_fail "File image does not look like a kube-apiserver image: '$FILE_IMAGE'" \
                "Expected: '$EXPECTED_IMAGE'"
        fi
    fi
fi

# ── Query 4: Custom columns table ────────────────────────────────────────────

echo -e "\n  ${BOLD}Query 4 — custom-columns table → /tmp/task23-pod-status.txt${NC}"

if [ ! -f /tmp/task23-pod-status.txt ]; then
    check_fail "File /tmp/task23-pod-status.txt does not exist"
else
    # Check file has the expected header line from custom-columns
    if grep -q "^NAME" /tmp/task23-pod-status.txt; then
        check_pass "File has NAME column header (custom-columns format confirmed)"
    else
        check_fail "File does not have 'NAME' header — did you use -o custom-columns? Got: $(head -1 /tmp/task23-pod-status.txt)"
    fi

    if grep -q "STATUS\|phase\|PHASE" /tmp/task23-pod-status.txt; then
        check_pass "File has STATUS column"
    else
        check_fail "File does not have 'STATUS' column — expected -o custom-columns='NAME:.metadata.name,STATUS:.status.phase'"
    fi

    # Check there is actual data (at least header + 1 pod row)
    LINE_COUNT=$(wc -l < /tmp/task23-pod-status.txt)
    if [ "${LINE_COUNT:-0}" -ge 2 ]; then
        check_pass "File has ${LINE_COUNT} lines (header + pod data)"
    else
        check_fail "File has only ${LINE_COUNT} line(s) — expected header + at least 1 pod row"
    fi
fi

# ── Final summary ──────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}━━━ Verification Result: Task 23 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Passed: ${GREEN}${PASS_COUNT}${NC}  |  Failed: ${RED}${FAIL_COUNT}${NC}"

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "\n  ${BOLD}${GREEN}✓  TASK 23 COMPLETE — All 4 JSONPath queries answered correctly${NC}"
else
    echo -e "\n  ${BOLD}${RED}✗  Some queries incomplete — fix and run check again${NC}"
    echo -e "  ${DIM}Tip: run each query manually and verify the output before redirecting to the file${NC}"
fi
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

[ "$FAIL_COUNT" -eq 0 ]
