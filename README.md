# Demo CND France 2026

This demo showcases how Kyverno policies enforce authentication and authorization for MCP Gateway tool calls.

## Prerequisites

- Kind cluster running with Kyverno Envoy Plugin
- Keycloak configured with users and groups
- Agent Gateway and KGateway deployed
- Policies applied: `no-unauthenticated-calls` and `create-from-url-authz`

## Setup

1. Ensure all components are running:
   ```bash
   kubectl get pods -n kyverno
   kubectl get pods -n keycloak
   ```

2. Get authentication tokens for different users:
   ```bash
   # Get token for a user in kube-dev group
   ./get-token.sh alice
   
   # Get token for a user in kube-admin group
   ./get-token.sh admin
   ```

---

## Example 1: Restrict all non-authorized calls

This example demonstrates the `no-unauthenticated-calls` policy that enforces authentication and group membership for all MCP Gateway requests.

### Policy Overview

The `no-unauthenticated-calls` policy:
- Validates JWT tokens from the Authorization header
- Verifies token signature using Keycloak JWKS endpoint
- Checks that the user belongs to allowed groups (`kube-dev` or `kube-admin`)
- Returns 401 Unauthorized for invalid or missing tokens

### Test Case 1.1: Unauthenticated Request (Should Fail)

```bash
# Make a request without authentication token
curl -X POST https://gateway.kind.cluster/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "method": "tools/call",
    "params": {
      "name": "k8s_list_resources",
      "arguments": {}
    }
  }'
```

**Expected Result:** 
- Status: `401 Unauthorized`
- Policy denies the request because no JWT token is present

### Test Case 1.2: Valid Token with Authorized Group (Should Succeed)

```bash
# Get token for alice (member of kube-dev group)
TOKEN=$(./get-token.sh alice)

# Make authenticated request
curl -X POST https://gateway.kind.cluster/mcp \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "method": "tools/call",
    "params": {
      "name": "k8s_list_resources",
      "arguments": {
        "namespace": "default"
      }
    }
  }'
```

**Expected Result:**
- Status: `200 OK`
- Policy allows the request because:
  - Valid JWT token is present
  - Token is properly signed and validated
  - User belongs to `kube-dev` group (allowed group)

### \[OPTIONAL\] Test Case 1.3: Invalid Token (Should Fail)

```bash
# Make a request with an invalid token
curl -X POST https://gateway.kind.cluster/mcp \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer invalid-token-here' \
  -d '{
    "method": "tools/call",
    "params": {
      "name": "k8s_list_resources",
      "arguments": {}
    }
  }'
```

**Expected Result:**
- Status: `401 Unauthorized`
- Policy denies the request because the JWT token is invalid or cannot be decoded

### \[OPTIONAL\] Test Case 1.4: Valid Token with Unauthorized Group (Should Fail)

```bash
# Get token for a user not in kube-dev or kube-admin groups
TOKEN=$(./get-token.sh unauthorized-user)

# Make authenticated request
curl -X POST https://gateway.kind.cluster/mcp \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "method": "tools/call",
    "params": {
      "name": "k8s_list_resources",
      "arguments": {}
    }
  }'
```

**Expected Result:**
- Status: `401 Unauthorized`
- Policy denies the request because user group is not in the allowed list

---

## Example 2: Restrict create from URL via SAR

This example demonstrates the `create-from-url-authz` policy that uses Kubernetes Subject Access Review (SAR) to verify if a user has permission to create resources from a URL.

### Policy Overview

The `create-from-url-authz` policy:
- Intercepts MCP tool calls for `k8s_create_resource_from_url`
- Extracts namespace and URL from the MCP request arguments
- Fetches and parses the Kubernetes manifest from the URL
- Extracts the resource kind from the manifest
- Creates a Subject Access Review (SAR) to check if the user can create that resource type in the specified namespace
- Returns 403 Forbidden if SAR denies the operation

### Test Case 2.1: Authorized Create Operation (Should Succeed)

```bash
# Get token for alice (has create permissions in dev namespace)
TOKEN=$(./get-token.sh alice)

# Create a deployment manifest URL (example)
MANIFEST_URL="https://raw.githubusercontent.com/example/deployment.yaml"

# Make authenticated request to create resource from URL
curl -X POST https://gateway.kind.cluster/mcp \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"k8s_create_resource_from_url\",
      \"arguments\": {
        \"namespace\": \"dev-team\",
        \"url\": \"$MANIFEST_URL\"
      }
    }
  }"
```

**Expected Result:**
- Status: `200 OK`
- Policy allows the request because:
  - User is authenticated (from Example 1)
  - SAR check confirms user has `create` permission for the resource type in `dev-team` namespace
  - Resource is created successfully

### Test Case 2.2: Unauthorized Create Operation (Should Fail)

```bash
# Get token for alice (does NOT have create permissions in production namespace)
TOKEN=$(./get-token.sh alice)

# Attempt to create resource in production namespace
MANIFEST_URL="https://raw.githubusercontent.com/example/deployment.yaml"

curl -X POST https://gateway.kind.cluster/mcp \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d "{
    \"method\": \"tools/call\",
    \"params\": {
      \"name\": \"k8s_create_resource_from_url\",
      \"arguments\": {
        \"namespace\": \"production\",
        \"url\": \"$MANIFEST_URL\"
      }
    }
  }"
```

**Expected Result:**
- Status: `403 Forbidden`
- Policy denies the request because:
  - SAR check fails - user does not have `create` permission for resources in `production` namespace
  - Resource creation is blocked

---

## Summary

These examples demonstrate:

1. **Authentication Enforcement**: All requests must include valid JWT tokens from Keycloak, and users must belong to authorized groups.

2. **Authorization Enforcement**: Even with valid authentication, users can only perform operations they're authorized for, verified through Kubernetes Subject Access Review.

3. **Least Privilege**: Users are restricted to their assigned namespaces and resource types based on Kubernetes RBAC.

4. **Per-User Accountability**: Each request is tied to the actual user identity from the JWT token, enabling proper audit trails.

5. **Policy-Based Guardrails**: Kyverno policies provide additional validation beyond basic RBAC, allowing for complex business rules.
