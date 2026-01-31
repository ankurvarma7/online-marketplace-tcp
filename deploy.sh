#!/bin/bash
set -e

PROJECT_ID="online-marketplace-486000"
ZONE="us-central1-a"
REPO_URL="https://github.com/ankurvarma7/online-marketplace.git"

echo "=== Building binaries locally ==="
cd "$(dirname "$0")"
cargo build --release

echo ""
echo "=== Deploying to VMs ==="

# Function to deploy a service
deploy_service() {
    local VM_NAME=$1
    local SERVICE_NAME=$2
    local BINARY_PATH=$3
    local ENV_VARS=$4
    local PORT=$5
    
    echo ""
    echo "--- Deploying $SERVICE_NAME to $VM_NAME ---"
    
    # Copy binary
    echo "Copying binary..."
    gcloud compute scp --zone=$ZONE --project=$PROJECT_ID \
        "$BINARY_PATH" "${VM_NAME}:~/${SERVICE_NAME}" --compress
    
    # Create systemd service
    echo "Setting up systemd service..."
    gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT_ID -- bash <<EOF
set -e
chmod +x ~/${SERVICE_NAME}

# Create systemd service
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<SERVICE
[Unit]
Description=${SERVICE_NAME} Service
After=network.target

[Service]
Type=simple
User=\$USER
WorkingDirectory=/home/\$USER
${ENV_VARS}
ExecStart=/home/\$USER/${SERVICE_NAME}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}.service
sudo systemctl restart ${SERVICE_NAME}.service
sleep 2
sudo systemctl status --no-pager ${SERVICE_NAME}.service || true
EOF
    
    echo "$SERVICE_NAME deployed successfully"
}

# Deploy database services
deploy_service "customer-db" "customer_db" \
    "./target/release/customer_db" \
    "Environment=\"RUST_LOG=info\"" \
    "8080"

deploy_service "product-db" "product_db" \
    "./target/release/product_db" \
    "Environment=\"RUST_LOG=info\"" \
    "8081"

# Deploy seller server
deploy_service "seller-server" "seller_server" \
    "./target/release/seller_server" \
    "Environment=\"RUST_LOG=info\"\nEnvironment=\"CUSTOMER_DB_ADDR=10.0.0.2:8080\"\nEnvironment=\"PRODUCT_DB_ADDR=10.0.0.3:8081\"" \
    "8082"

# Deploy buyer server
deploy_service "buyer-server" "buyer_server" \
    "./target/release/buyer_server" \
    "Environment=\"RUST_LOG=info\"\nEnvironment=\"CUSTOMER_DB_ADDR=10.0.0.2:8080\"\nEnvironment=\"PRODUCT_DB_ADDR=10.0.0.3:8081\"" \
    "8083"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Service URLs:"
echo "  Seller Server: http://10.0.0.4:8082"
echo "  Buyer Server:  http://10.0.0.5:8083"
echo ""
echo "To check service status:"
echo "  gcloud compute ssh <vm-name> --zone=$ZONE --project=$PROJECT_ID -- 'sudo systemctl status <service-name>'"
echo ""
echo "=== Setting up clients and evaluator ==="

# Copy client binaries
echo "Copying seller client..."
gcloud compute scp --zone=$ZONE --project=$PROJECT_ID \
    "./target/release/seller_client" "seller-client:~/seller_client" --compress

echo "Copying buyer client..."
gcloud compute scp --zone=$ZONE --project=$PROJECT_ID \
    "./target/release/buyer_client" "buyer-client:~/buyer_client" --compress

echo "Copying evaluator..."
gcloud compute scp --zone=$ZONE --project=$PROJECT_ID \
    "./target/release/evaluator" "evaluator:~/evaluator" --compress

# Setup seller client
echo ""
echo "--- Setting up seller client ---"
gcloud compute ssh seller-client --zone=$ZONE --project=$PROJECT_ID -- bash <<'EOF'
chmod +x ~/seller_client
cat > ~/test_seller.sh <<'SCRIPT'
#!/bin/bash
export SELLER_SERVER_ADDR=10.0.0.4:8082
cd ~

echo "=== Testing Seller Client ==="
echo "1. Creating seller account..."
./seller_client create-account --name "TestSeller" --password "password123"
echo ""

echo "2. Logging in..."
SESSION_OUTPUT=$(./seller_client login --name "TestSeller" --password "password123")
echo "$SESSION_OUTPUT"
SESSION_ID=$(echo "$SESSION_OUTPUT" | grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}' | head -1)
echo "Session ID: $SESSION_ID"
echo ""

if [ -n "$SESSION_ID" ]; then
    echo "3. Registering an item..."
    ./seller_client register-item \
      --session-id "$SESSION_ID" \
      --name "Test Laptop" \
      --category 1 \
      --keywords "electronics,computer,laptop" \
      --condition "new" \
      --price 999.99 \
      --quantity 5
    echo ""

    echo "4. Displaying items..."
    ./seller_client display-items --session-id "$SESSION_ID"
fi
SCRIPT
chmod +x ~/test_seller.sh
EOF

# Setup buyer client
echo ""
echo "--- Setting up buyer client ---"
gcloud compute ssh buyer-client --zone=$ZONE --project=$PROJECT_ID -- bash <<'EOF'
chmod +x ~/buyer_client
cat > ~/test_buyer.sh <<'SCRIPT'
#!/bin/bash
export BUYER_SERVER_ADDR=10.0.0.5:8083
cd ~

echo "=== Testing Buyer Client ==="
echo "1. Creating buyer account..."
./buyer_client create-account --name "TestBuyer" --password "password123"
echo ""

echo "2. Logging in..."
SESSION_OUTPUT=$(./buyer_client login --name "TestBuyer" --password "password123")
echo "$SESSION_OUTPUT"
SESSION_ID=$(echo "$SESSION_OUTPUT" | grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}' | head -1)
echo "Session ID: $SESSION_ID"
echo ""

if [ -n "$SESSION_ID" ]; then
    echo "3. Searching items..."
    ./buyer_client search \
      --session-id "$SESSION_ID" \
      --keywords "electronics"
fi
SCRIPT
chmod +x ~/test_buyer.sh
EOF

# Setup evaluator
echo ""
echo "--- Setting up evaluator ---"
gcloud compute ssh evaluator --zone=$ZONE --project=$PROJECT_ID -- bash <<'EOF'
chmod +x ~/evaluator
cat > ~/run_evaluation.sh <<'SCRIPT'
#!/bin/bash
export SELLER_SERVER_ADDR=10.0.0.4:8082
export BUYER_SERVER_ADDR=10.0.0.5:8083
export RUST_LOG=info
cd ~

echo "=== Running Performance Evaluation ==="
echo "Starting at: $(date)"
echo ""

./evaluator 2>&1 | tee ~/evaluation_results_$(date +%Y%m%d_%H%M%S).log

echo ""
echo "Evaluation completed at: $(date)"
SCRIPT
chmod +x ~/run_evaluation.sh
EOF

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To run tests:"
echo "  Seller: gcloud compute ssh seller-client --zone=$ZONE --project=$PROJECT_ID -- './test_seller.sh'"
echo "  Buyer:  gcloud compute ssh buyer-client --zone=$ZONE --project=$PROJECT_ID -- './test_buyer.sh'"
echo ""
echo "To run evaluation:"
echo "  gcloud compute ssh evaluator --zone=$ZONE --project=$PROJECT_ID -- './run_evaluation.sh'"
