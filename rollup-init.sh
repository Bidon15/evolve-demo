#!/bin/sh
# rollup-init.sh - Initialize the complete rollup stack with ALL dependencies

set -e

echo "🚀 Initializing Rollup Stack (with ALL secrets)..."

# Install required tools first
echo "📦 Installing curl and jq..."
apk add --no-cache curl jq
echo "✅ Installation complete, verifying..."
which curl
which jq

# Function to wait for service
wait_for_service() {
    local service_name=$1
    local endpoint=$2
    local test_payload=$3
    
    echo "⏳ Waiting for $service_name..."
    timeout 120 sh -c "
    until curl -s $endpoint -X POST \
        -H 'Content-Type: application/json' \
        -d '$test_payload' | grep -q result; do
        echo 'Waiting for $service_name...'
        sleep 3
    done"
    echo "✅ $service_name is ready"
}

# 1. Wait for Reth to be ready
wait_for_service "Reth" "http://reth-node:8545" '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# 2. Get genesis hash from Reth
echo "🔗 Getting genesis hash from Reth..."
genesis_response=$(curl -s http://reth-node:8545 -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":1}')

genesis_hash=$(echo "$genesis_response" | jq -r '.result.hash')
echo "Genesis Hash: $genesis_hash"

# 3. Get JWT secret from shared volume (pre-generated)
echo "🔐 Getting JWT secret from shared volume..."
if [ -f /shared/reth-jwt-secret.txt ]; then
    jwt_secret=$(cat /shared/reth-jwt-secret.txt | tr -d '\n')
    echo "Found JWT secret: ${jwt_secret:0:20}..."
else
    echo "❌ JWT secret not found!"
    exit 1
fi

# 4. Wait for Celestia JWT token
echo "🔑 Waiting for Celestia JWT token..."
echo "📁 Checking shared directory..."
ls -la /shared/ || echo "Shared directory doesn't exist yet"

timeout 300 sh -c '
until [ -f /shared/celestia-jwt.token ]; do
    echo "Waiting for JWT token..."
    ls -la /shared/ 2>/dev/null || echo "Shared directory not ready"
    sleep 5
done'

celestia_jwt=$(cat /shared/celestia-jwt.token)
echo "✅ Celestia JWT token available"

# 5. Wait for Celestia to be ready
echo "🌟 Testing Celestia with JWT..."
timeout 60 sh -c "
until curl -s -X POST http://celestia-node:26658 \
    -H 'Authorization: Bearer $celestia_jwt' \
    -H 'Content-Type: application/json' \
    -d '{\"jsonrpc\":\"2.0\",\"method\":\"header.NetworkHead\",\"params\":[],\"id\":1}' \
    | grep -q result; do
    echo 'Waiting for Celestia RPC...'
    sleep 3
done"
echo "✅ Celestia is ready"

# 6. Create Rollkit environment file with ALL the secrets
echo "📝 Creating Rollkit configuration with all secrets..."
cat > /shared/rollkit.env << EOF
EVM_ENGINE_URL=http://reth-node:8551
EVM_ETH_URL=http://reth-node:8545
EVM_JWT_SECRET=$jwt_secret
EVM_GENESIS_HASH=$genesis_hash
EVM_BLOCK_TIME=1s
EVM_SIGNER_PASSPHRASE=secret
DA_ADDRESS=http://celestia-node:26658
DA_AUTH_TOKEN=$celestia_jwt
DA_NAMESPACE=00000000000000000000000000000000000000000000000000YanaVikhnich
EOF

echo ""
echo "🎉 Rollup Stack Initialization Complete!"
echo "========================================"
echo "✅ Reth Ready: ${EVM_ETH_URL}"
echo "✅ Celestia Ready: ${DA_ADDRESS}"
echo "✅ Genesis Hash: $genesis_hash"
echo "✅ Reth JWT Secret: ${jwt_secret:0:20}..."
echo "✅ Celestia JWT Token: ${celestia_jwt:0:20}..."
echo "✅ DA Namespace: ${DA_NAMESPACE}"
echo "✅ Rollkit Config: /shared/rollkit.env"
echo ""
echo "🔄 Ready to start Rollkit sequencer!"
