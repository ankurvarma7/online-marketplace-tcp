#!/bin/bash
set -e

PROJECT_ID="online-marketplace-486000"
ZONE="us-central1-a"

echo "Creating VMs..."

# Create customer-db
echo "Creating customer-db..."
gcloud compute instances create customer-db \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --network-interface=network=marketplace-network,subnet=marketplace-subnet,private-network-ip=10.0.0.2 \
    --tags=http-server \
    --project=$PROJECT_ID

# Create product-db
echo "Creating product-db..."
gcloud compute instances create product-db \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --network-interface=network=marketplace-network,subnet=marketplace-subnet,private-network-ip=10.0.0.3 \
    --tags=http-server \
    --project=$PROJECT_ID

# Create seller-server
echo "Creating seller-server..."
gcloud compute instances create seller-server \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --network-interface=network=marketplace-network,subnet=marketplace-subnet,private-network-ip=10.0.0.4 \
    --tags=http-server \
    --project=$PROJECT_ID

# Create buyer-server
echo "Creating buyer-server..."
gcloud compute instances create buyer-server \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --network-interface=network=marketplace-network,subnet=marketplace-subnet,private-network-ip=10.0.0.5 \
    --tags=http-server \
    --project=$PROJECT_ID

# Create seller-client
echo "Creating seller-client..."
gcloud compute instances create seller-client \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --network-interface=network=marketplace-network,subnet=marketplace-subnet,private-network-ip=10.0.0.6 \
    --project=$PROJECT_ID

# Create buyer-client
echo "Creating buyer-client..."
gcloud compute instances create buyer-client \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --network-interface=network=marketplace-network,subnet=marketplace-subnet,private-network-ip=10.0.0.7 \
    --project=$PROJECT_ID

# Create evaluator
echo "Creating evaluator..."
gcloud compute instances create evaluator \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --boot-disk-size=10GB \
    --network-interface=network=marketplace-network,subnet=marketplace-subnet,private-network-ip=10.0.0.8 \
    --project=$PROJECT_ID

echo ""
echo "All VMs created successfully!"
echo ""
echo "Waiting 30 seconds for VMs to boot..."
sleep 30

echo ""
echo "VM Status:"
gcloud compute instances list \
    --filter="name~'customer-db|product-db|seller-server|buyer-server|seller-client|buyer-client|evaluator'" \
    --format="table(name,status,networkInterfaces[0].networkIP)" \
    --project=$PROJECT_ID
