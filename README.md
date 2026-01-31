# Online Marketplace - Programming Assignment 1

## Brief System Summary (8–10 lines)
1. The system is a distributed online marketplace with six components and TCP-only communication.
2. Buyer and seller frontend servers are stateless; all state lives in customer and product databases.
3. Sessions are UUID v4 tokens stored in the customer database with a 5‑minute inactivity timeout.
4. Each API call is a single request/response over a TCP connection using line‑delimited JSON.
5. Buyers and sellers can hold multiple concurrent sessions from different machines.
6. Item data, carts, feedback, and purchase history are stored in the product database.
7. Authentication uses plaintext credentials (as required for PA1).
8. The CLI clients expose all required APIs except MakePurchase.
9. Search is category/keyword based with relevance scoring and case‑insensitive substring matching.
10. Current state: all required PA1 APIs work; data is in‑memory only and resets on restart.

## System Design

### Architecture Overview
The system implements a distributed online marketplace with six independently deployable components communicating via TCP/IP sockets:

1. **Customer Database** - Manages sellers, buyers, and session data
2. **Product Database** - Manages items, shopping carts, and purchase history
3. **Seller Server** - Frontend server handling seller requests
4. **Buyer Server** - Frontend server handling buyer requests
5. **Seller Client** - CLI interface for sellers
6. **Buyer Client** - CLI interface for buyers

### Design Principles

**Stateless Frontend Servers**: Both buyer_server and seller_server are completely stateless. They do not store any persistent user data, session information, or shopping cart state. All state is delegated to the backend databases. This design allows:
- Seamless reconnections (TCP reconnects don't affect session state)
- Server restarts without data loss
- Horizontal scalability (multiple server instances can run)

**Distributed Architecture**: Each component runs as a separate process and can be deployed on different machines with different IP addresses/ports. Communication happens exclusively through TCP sockets.

**Session Management**: Sessions are identified by UUID v4 tokens, stored in the customer database, and expire after 5 minutes of inactivity. A background cleanup task automatically removes expired sessions.

**Concurrent Access**: All components use asynchronous I/O (tokio) and thread-safe data structures (DashMap) to handle multiple concurrent connections.

### Communication Protocol
- **Transport**: TCP/IP sockets
- **Serialization**: Line-delimited JSON
- **Message Flow**: Request-response pattern
- Each TCP connection handles one request/response cycle

## Implementation Status

### Fully Implemented
- All 6 core components
- All required APIs:
  - **Seller APIs**: CreateAccount, Login, Logout, GetSellerRating, RegisterItemForSale, ChangeItemPrice, UpdateUnitsForSale, DisplayItemsForSale
  - **Buyer APIs**: CreateAccount, Login, Logout, SearchItemsForSale, GetItem, AddItemToCart, RemoveItemFromCart, SaveCart, ClearCart, DisplayCart, ProvideFeedback, GetSellerRating, GetBuyerPurchases
- Session timeout (5 minutes) with automatic cleanup
- CLI interfaces for both clients using `clap` framework
- Stateless frontend servers
- Multi-user concurrent session support
- Simple authentication (plaintext, as specified)
- Performance evaluation setup (evaluator component)
- Environment variable configuration for flexible deployment

### Search Semantics
The search function implements a keyword-based scoring algorithm:
- Searches items by category (if specified) and/or keywords
- Each keyword match in the item's keywords list adds to the score
- Substring matches are also considered (e.g., "comp" matches "computer")
- Results are returned sorted by relevance score (highest first)
- Case-insensitive matching

## Assumptions

1. **Network Reliability**: TCP provides reliable delivery; no additional retry logic is implemented
2. **Authentication**: Passwords stored in plaintext (security will be addressed in future assignments)
3. **Item IDs**: Generated using UUID v4 to ensure uniqueness across distributed deployments
4. **Concurrency**: Multiple sellers/buyers can be logged in simultaneously; same user can have multiple active sessions from different clients
5. **Data Persistence**: All data is in-memory; restarts clear all data (persistent storage will be added later)
6. **Error Handling**: Basic error messages returned to clients; detailed logging to stdout
7. **Cart Persistence**: Shopping carts are cleared on logout unless explicitly saved using SaveCart API

## Building and Running

### Prerequisites
- Rust 1.70+ (install from https://rustup.rs/)
- Cargo (comes with Rust)

### Build
```bash
cargo build --release
```

### Run Components Locally

Open 4 separate terminals and run:

```bash
# Terminal 1: Customer Database
./target/release/customer_db

# Terminal 2: Product Database
./target/release/product_db

# Terminal 3: Seller Server
./target/release/seller_server

# Terminal 4: Buyer Server
./target/release/buyer_server
```

### Use CLI Clients

```bash
# Seller operations
./target/release/seller_client create-account --name "Alice" --password "secret123"
./target/release/seller_client login --name "Alice" --password "secret123"
# Returns session ID, use it for subsequent commands:
./target/release/seller_client register-item \
    --session-id "<session_id>" \
    --name "Laptop" \
    --category 1 \
    --keywords "electronics,computer" \
    --condition "new" \
    --price 999.99 \
    --quantity 10

# Buyer operations
./target/release/buyer_client create-account --name "Bob" --password "pass456"
./target/release/buyer_client login --name "Bob" --password "pass456"
# Returns session ID, use it:
./target/release/buyer_client search \
    --session-id "<session_id>" \
    --category 1 \
    --keywords "electronics"
```

For full CLI documentation:
```bash
./target/release/seller_client --help
./target/release/buyer_client --help
```

### Run Performance Evaluator

Ensure all 4 server components are running, then:
```bash
./target/release/evaluator
```

This will run automated performance tests with 1, 10, and 100 concurrent users.

## Deployment on GCP/CloudLab

See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed instructions on deploying across multiple VMs using environment variables.

Quick example:
```bash
# On database VMs
export CUSTOMER_DB_BIND_ADDR="0.0.0.0:8080"
export PRODUCT_DB_BIND_ADDR="0.0.0.0:8081"

# On frontend VMs
export SELLER_SERVER_BIND_ADDR="0.0.0.0:8082"
export CUSTOMER_DB_ADDR="<customer_db_vm_ip>:8080"
export PRODUCT_DB_ADDR="<product_db_vm_ip>:8081"
```

## Project Structure

```
online-marketplace/
├── Cargo.toml                 # Workspace configuration
├── common/                    # Shared data structures and message types
│   └── src/lib.rs
├── customer_db/               # Customer database component
│   └── src/main.rs
├── product_db/                # Product database component
│   └── src/main.rs
├── seller_server/             # Seller frontend server
│   └── src/main.rs
├── buyer_server/              # Buyer frontend server
│   └── src/main.rs
├── seller_client/             # Seller CLI client
│   └── src/main.rs
├── buyer_client/              # Buyer CLI client
│   └── src/main.rs
└── evaluator/                 # Performance testing tool
    └── src/main.rs
```

## Testing

Manual testing has been performed for:
- Account creation (buyers and sellers)
- Login/logout with session management
- Item registration and search
- Shopping cart operations
- Feedback system
- Concurrent multi-user access

Automated testing via the evaluator component measures:
- Response times
- Throughput
- Concurrent user scenarios

## Known Limitations

1. **No Persistence**: Data lost on restart (will add database persistence in PA2)
2. **No Security**: Plaintext passwords, no encryption (will add in PA3)
3. **No MakePurchase**: Not required for PA1
4. **In-Memory Storage**: Limited by available RAM
5. **No Load Balancing**: Single instance per component


## Use of AI
- Used AI to generate the Readme and report from the evaluation script.
- Used AI to generate the deployment script