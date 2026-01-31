#!/bin/bash
set -e

PROJECT_ID="online-marketplace-486000"
ZONE="us-central1-a"
REPO_URL="https://github.com/ankurvarma7/online-marketplace.git"

echo "=== Deploying Online Marketplace to VMs ==="
echo ""

# Function to setup and deploy a service
deploy_to_vm() {
    local VM_NAME=$1
    local SERVICE_NAME=$2
    local PORT=$3
    local ENV_VARS=$4
    
    echo "--- Deploying $SERVICE_NAME to $VM_NAME ---"
    
    gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT_ID -- bash <<EOF
set -e

# Install dependencies if not present
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust and dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential git pkg-config libssl-dev curl
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

# Source Rust environment
source \$HOME/.cargo/env

# Clone or update repository
if [ ! -d "\$HOME/online-marketplace" ]; then
    echo "Cloning repository..."
    git clone $REPO_URL \$HOME/online-marketplace
else
    echo "Updating repository..."
    cd \$HOME/online-marketplace
    git fetch --all
    git reset --hard origin/main
fi

# Build the service
echo "Building $SERVICE_NAME..."
cd \$HOME/online-marketplace
cargo build --release --bin $SERVICE_NAME

# Create systemd service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<SERVICE
[Unit]
Description=${SERVICE_NAME} Service
After=network.target

[Service]
Type=simple
User=\$USER
WorkingDirectory=\$HOME/online-marketplace
$ENV_VARS
ExecStart=\$HOME/online-marketplace/target/release/${SERVICE_NAME}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}.service
sudo systemctl restart ${SERVICE_NAME}.service

# Wait a moment and check status
sleep 3
sudo systemctl status --no-pager ${SERVICE_NAME}.service || true

echo "$SERVICE_NAME deployment complete on $VM_NAME"
EOF
    
    echo ""
}

# Deploy customer database
deploy_to_vm "customer-db" "customer_db" "8080" "Environment=\"RUST_LOG=info\""

# Deploy product database
deploy_to_vm "product-db" "product_db" "8081" "Environment=\"RUST_LOG=info\""

# Wait for databases to be ready
echo "Waiting for databases to initialize..."
sleep 5

# Deploy seller server
deploy_to_vm "seller-server" "seller_server" "8082" \
"Environment=\"RUST_LOG=info\"
Environment=\"CUSTOMER_DB_ADDR=10.0.0.2:8080\"
Environment=\"PRODUCT_DB_ADDR=10.0.0.3:8081\""

# Deploy buyer server
deploy_to_vm "buyer-server" "buyer_server" "8083" \
"Environment=\"RUST_LOG=info\"
Environment=\"CUSTOMER_DB_ADDR=10.0.0.2:8080\"
Environment=\"PRODUCT_DB_ADDR=10.0.0.3:8081\""

echo ""
echo "=== Deploying Client Applications ==="
echo ""

# Deploy seller client
echo "--- Setting up seller-client ---"
gcloud compute ssh seller-client --zone=$ZONE --project=$PROJECT_ID -- bash <<'EOF'
set -e

# Install dependencies
if ! command -v cargo &> /dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential git pkg-config libssl-dev curl
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

source $HOME/.cargo/env

# Clone repo
if [ ! -d "$HOME/online-marketplace" ]; then
    git clone https://github.com/ankurvarma7/online-marketplace.git $HOME/online-marketplace
else
    cd $HOME/online-marketplace && git fetch --all && git reset --hard origin/main
fi

# Build
cd $HOME/online-marketplace
cargo build --release --bin seller_client

# Create test script
cat > $HOME/test_seller.sh <<'SCRIPT'
#!/bin/bash
export SELLER_SERVER_ADDR=10.0.0.4:8082
cd ~/online-marketplace

echo "=== Testing Seller Client ==="
echo "1. Creating seller account..."
./target/release/seller_client create-account --name "TestSeller" --password "password123"
echo ""

echo "2. Logging in..."
SESSION_OUTPUT=$(./target/release/seller_client login --name "TestSeller" --password "password123")
echo "$SESSION_OUTPUT"
SESSION_ID=$(echo "$SESSION_OUTPUT" | grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}' | head -1)
echo "Session ID: $SESSION_ID"
echo ""

if [ -n "$SESSION_ID" ]; then
    echo "3. Registering an item..."
    ./target/release/seller_client register-item \
      --session-id "$SESSION_ID" \
      --name "Test Laptop" \
      --category 1 \
      --keywords "electronics,computer,laptop" \
      --condition "new" \
      --price 999.99 \
      --quantity 5
    echo ""

    echo "4. Displaying items..."
    ./target/release/seller_client display-items --session-id "$SESSION_ID"
fi
SCRIPT

chmod +x $HOME/test_seller.sh
echo "Seller client ready"
EOF

echo ""

# Deploy buyer client
echo "--- Setting up buyer-client ---"
gcloud compute ssh buyer-client --zone=$ZONE --project=$PROJECT_ID -- bash <<'EOF'
set -e

# Install dependencies
if ! command -v cargo &> /dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential git pkg-config libssl-dev curl
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

source $HOME/.cargo/env

# Clone repo
if [ ! -d "$HOME/online-marketplace" ]; then
    git clone https://github.com/ankurvarma7/online-marketplace.git $HOME/online-marketplace
else
    cd $HOME/online-marketplace && git fetch --all && git reset --hard origin/main
fi

# Build
cd $HOME/online-marketplace
cargo build --release --bin buyer_client

# Create test script
cat > $HOME/test_buyer.sh <<'SCRIPT'
#!/bin/bash
export BUYER_SERVER_ADDR=10.0.0.5:8083
cd ~/online-marketplace

echo "=== Testing Buyer Client ==="
echo "1. Creating buyer account..."
./target/release/buyer_client create-account --name "TestBuyer" --password "password123"
echo ""

echo "2. Logging in..."
SESSION_OUTPUT=$(./target/release/buyer_client login --name "TestBuyer" --password "password123")
echo "$SESSION_OUTPUT"
SESSION_ID=$(echo "$SESSION_OUTPUT" | grep -o '[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}' | head -1)
echo "Session ID: $SESSION_ID"
echo ""

if [ -n "$SESSION_ID" ]; then
    echo "3. Searching items..."
    ./target/release/buyer_client search \
      --session-id "$SESSION_ID" \
      --keywords "electronics"
fi
SCRIPT

chmod +x $HOME/test_buyer.sh
echo "Buyer client ready"
EOF

echo ""

# Deploy evaluator
echo "--- Setting up evaluator ---"
gcloud compute ssh evaluator --zone=$ZONE --project=$PROJECT_ID -- bash <<'EOF'
set -e

# Install dependencies
if ! command -v cargo &> /dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential git pkg-config libssl-dev curl
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

source $HOME/.cargo/env

# Clone repo
if [ ! -d "$HOME/online-marketplace" ]; then
    git clone https://github.com/ankurvarma7/online-marketplace.git $HOME/online-marketplace
else
    cd $HOME/online-marketplace && git fetch --all && git reset --hard origin/main
fi

# Build
cd $HOME/online-marketplace
cargo build --release --bin evaluator

# Create evaluation script
cat > $HOME/run_evaluation.sh <<'SCRIPT'
#!/bin/bash
export SELLER_SERVER_ADDR=10.0.0.4:8082
export BUYER_SERVER_ADDR=10.0.0.5:8083
export RUST_LOG=info
cd ~/online-marketplace

echo "=== Running Performance Evaluation ==="
echo "Starting at: $(date)"
echo ""

./target/release/evaluator 2>&1 | tee ~/evaluation_results_$(date +%Y%m%d_%H%M%S).log

echo ""
echo "Evaluation completed at: $(date)"
SCRIPT

chmod +x $HOME/run_evaluation.sh
echo "Evaluator ready"
EOF

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Service Status:"
echo "  Customer DB:   gcloud compute ssh customer-db --zone=$ZONE --project=$PROJECT_ID -- 'sudo systemctl status customer_db'"
echo "  Product DB:    gcloud compute ssh product-db --zone=$ZONE --project=$PROJECT_ID -- 'sudo systemctl status product_db'"
echo "  Seller Server: gcloud compute ssh seller-server --zone=$ZONE --project=$PROJECT_ID -- 'sudo systemctl status seller_server'"
echo "  Buyer Server:  gcloud compute ssh buyer-server --zone=$ZONE --project=$PROJECT_ID -- 'sudo systemctl status buyer_server'"
echo ""
echo "To test clients:"
echo "  Seller: gcloud compute ssh seller-client --zone=$ZONE --project=$PROJECT_ID -- './test_seller.sh'"
echo "  Buyer:  gcloud compute ssh buyer-client --zone=$ZONE --project=$PROJECT_ID -- './test_buyer.sh'"
echo ""
echo "To run evaluation:"
echo "  gcloud compute ssh evaluator --zone=$ZONE --project=$PROJECT_ID -- './run_evaluation.sh'"
