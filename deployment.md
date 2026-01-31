# Create VPC network
gcloud compute networks create marketplace-network --subnet-mode=custom

# Create subnet
gcloud compute networks subnets create marketplace-subnet \
    --network=marketplace-network \
    --range=10.0.0.0/24 \
    --region=us-central1

# Create firewall rules
gcloud compute firewall-rules create marketplace-internal \
    --network=marketplace-network \
    --allow=tcp:8080,tcp:8081,tcp:8082,tcp:8083 \
    --source-ranges=10.0.0.0/24 \
    --description="Allow internal communication between components"

gcloud compute firewall-rules create marketplace-ssh \
    --network=marketplace-network \
    --allow=tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --description="Allow SSH access"

gcloud compute firewall-rules create marketplace-external \
    --network=marketplace-network \
    --allow=tcp:8082-8083 \
    --source-ranges=0.0.0.0/0 \
    --description="Allow external access to seller/buyer servers"


#!/bin/bash
# startup.sh - Run on each instance during boot

# Update and install dependencies
apt-get update
apt-get install -y \
    build-essential \
    curl \
    git \
    pkg-config \
    libssl-dev \
    ca-certificates

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env

# Clone the repository
cd /home/$USER
git clone https://github.com/your-username/online-marketplace.git
cd online-marketplace
cargo build --release

echo "Startup script completed at $(date)" >> /var/log/startup.log


# Define instance names and their roles
INSTANCES=(
    "customer-db:8080:10.0.0.2"
    "product-db:8081:10.0.0.3"
    "seller-server:8082:10.0.0.4"
    "buyer-server:8083:10.0.0.5"
    "seller-client:none:10.0.0.6"
    "buyer-client:none:10.0.0.7"
    "evaluator:none:10.0.0.8"
)

# Create each instance
for instance_info in "${INSTANCES[@]}"; do
    IFS=':' read -r name port internal_ip <<< "$instance_info"
    
    echo "Creating instance: $name"
    
    gcloud compute instances create $name \
        --zone=us-central1-a \
        --machine-type=e2-micro \
        --image-family=debian-11 \
        --image-project=debian-cloud \
        --boot-disk-size=10GB \
        --boot-disk-type=pd-standard \
        --network-interface=network=marketplace-network,subnet=marketplace-subnet,private-network-ip=$internal_ip \
        --tags=http-server,https-server \
        --metadata-from-file=startup-script=startup.sh \
        --scopes=cloud-platform
done

# SSH to the instance
gcloud compute ssh customer-db --zone=us-central1-a

# On the instance, create a systemd service
sudo nano /etc/systemd/system/customer-db.service

[Unit]
Description=Customer Database Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/home/$USER/online-marketplace/customer_db
Environment="RUST_LOG=info"
ExecStart=/home/$USER/.cargo/bin/cargo run --release
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target


sudo systemctl daemon-reload
sudo systemctl enable customer-db.service
sudo systemctl start customer-db.service
sudo systemctl status customer-db.service

# SSH to the instance
gcloud compute ssh product-db --zone=us-central1-a

# Create systemd service
sudo nano /etc/systemd/system/product-db.service

[Unit]
Description=Product Database Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/home/$USER/online-marketplace/product_db
Environment="RUST_LOG=info"
ExecStart=/home/$USER/.cargo/bin/cargo run --release
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target

sudo systemctl daemon-reload
sudo systemctl enable product-db.service
sudo systemctl start product-db.service

# SSH to the instance
gcloud compute ssh seller-server --zone=us-central1-a

# Create environment configuration
cat > /home/$USER/online-marketplace/seller_server/.env << EOF
CUSTOMER_DB_ADDR=10.0.0.2:8080
PRODUCT_DB_ADDR=10.0.0.3:8081
RUST_LOG=info
EOF

# Create systemd service
sudo nano /etc/systemd/system/seller-server.service

[Unit]
Description=Buyer Server Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/home/$USER/online-marketplace/buyer_server
EnvironmentFile=/home/$USER/online-marketplace/buyer_server/.env
ExecStart=/home/$USER/.cargo/bin/cargo run --release
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target

sudo systemctl daemon-reload
sudo systemctl enable buyer-server.service
sudo systemctl start buyer-server.service

# SSH to the instance
gcloud compute ssh seller-client --zone=us-central1-a

# Create environment configuration
cat > /home/$USER/online-marketplace/seller_client/.env << EOF
SELLER_SERVER_ADDR=10.0.0.4:8082
EOF

# Create test script
cat > /home/$USER/test_seller.sh << 'EOF'
#!/bin/bash
cd /home/$USER/online-marketplace/seller_client

echo "=== Testing Seller Client ==="
echo "1. Creating seller account..."
cargo run --release -- create-account --name "TestSeller" --password "password123"
echo ""

echo "2. Logging in..."
SESSION_ID=$(cargo run --release -- login --name "TestSeller" --password "password123" | grep "Session ID" | awk '{print $3}')
echo "Session ID: $SESSION_ID"
echo ""

echo "3. Registering an item..."
cargo run --release -- register-item \
  --session-id "$SESSION_ID" \
  --name "Test Laptop" \
  --category 1 \
  --keywords "electronics,computer,laptop" \
  --condition "new" \
  --price 999.99 \
  --quantity 5
echo ""

echo "4. Displaying items..."
cargo run --release -- display-items --session-id "$SESSION_ID"
EOF

chmod +x /home/$USER/test_seller.sh

# SSH to the instance
gcloud compute ssh buyer-client --zone=us-central1-a

# Create environment configuration
cat > /home/$USER/online-marketplace/buyer_client/.env << EOF
BUYER_SERVER_ADDR=10.0.0.5:8083
EOF

# Create test script
cat > /home/$USER/test_buyer.sh << 'EOF'
#!/bin/bash
cd /home/$USER/online-marketplace/buyer_client

echo "=== Testing Buyer Client ==="
echo "1. Creating buyer account..."
cargo run --release -- create-account --name "TestBuyer" --password "password123"
echo ""

echo "2. Logging in..."
SESSION_ID=$(cargo run --release -- login --name "TestBuyer" --password "password123" | grep "Session ID" | awk '{print $3}')
echo "Session ID: $SESSION_ID"
echo ""

echo "3. Searching items..."
cargo run --release -- search \
  --session-id "$SESSION_ID" \
  --keywords "electronics"
echo ""

echo "4. Getting seller rating..."
# First get a seller ID from the search results
cargo run --release -- get-seller-rating \
  --session-id "$SESSION_ID" \
  --seller-id "00000000-0000-0000-0000-000000000000"  # Replace with actual seller ID
EOF

chmod +x /home/$USER/test_buyer.sh


# SSH to the instance
gcloud compute ssh evaluator --zone=us-central1-a

# Create environment configuration
cat > /home/$USER/online-marketplace/evaluator/.env << EOF
SELLER_SERVER_ADDR=10.0.0.4:8082
BUYER_SERVER_ADDR=10.0.0.5:8083
RUST_LOG=info
EOF

# Create evaluation script
cat > /home/$USER/run_evaluation.sh << 'EOF'
#!/bin/bash
cd /home/$USER/online-marketplace/evaluator

echo "=== Running Performance Evaluation ==="
echo "Starting at: $(date)"
echo ""

# Run the evaluation
cargo run --release 2>&1 | tee /home/$USER/evaluation_results_$(date +%Y%m%d_%H%M%S).log

echo ""
echo "Evaluation completed at: $(date)"
echo "Results saved to: /home/$USER/evaluation_results_*.log"
EOF

chmod +x /home/$USER/run_evaluation.sh