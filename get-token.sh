#!/bin/bash

curl -k -X POST https://keycloak.kind.cluster/realms/master/protocol/openid-connect/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password' \
  -d 'client_id=mcp-inspector' \
  -d "username=$1" \
  -d "password=$1" \
  -d 'scope=openid' | jq -r '.access_token'
