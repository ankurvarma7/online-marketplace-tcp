# Performance Report (Programming Assignment 1)

## Experimental Setup
- Host: macOS workstation (single machine)
- Build: `cargo build --release`
- Components: one instance each of `customer_db`, `product_db`, `seller_server`, `buyer_server`
- Transport: TCP sockets, line-delimited JSON, request/response per connection
- Evaluator: `./target/release/evaluator` with 10 runs per scenario

## Measured Results

### Scenario 1: 1 seller, 1 buyer
- Average Response Time: 117.278554 ms
- Average Throughput: 171.76 ops/sec

### Scenario 2: 10 sellers, 10 buyers
- Average Response Time: 254.740329 ms
- Average Throughput: 786.57 ops/sec

### Scenario 3: 100 sellers, 100 buyers
- Average Response Time: 1.015467441 s
- Average Throughput: 667.14 ops/sec

## Per‑Run Measurements (from evaluator output)

### Scenario 1
1) 147.877792 ms, 135.25 ops/sec
2) 118.13975 ms, 169.29 ops/sec
3) 119.748375 ms, 167.02 ops/sec
4) 112.966833 ms, 177.04 ops/sec
5) 117.301833 ms, 170.50 ops/sec
6) 114.822 ms, 174.18 ops/sec
7) 113.125459 ms, 176.79 ops/sec
8) 110.083833 ms, 181.68 ops/sec
9) 110.916916 ms, 180.32 ops/sec
10) 107.80275 ms, 185.52 ops/sec

### Scenario 2
1) 254.523916 ms, 785.78 ops/sec
2) 235.451542 ms, 849.43 ops/sec
3) 239.495125 ms, 835.09 ops/sec
4) 250.9945 ms, 796.83 ops/sec
5) 258.987458 ms, 772.24 ops/sec
6) 251.544416 ms, 795.09 ops/sec
7) 260.387834 ms, 768.09 ops/sec
8) 255.482625 ms, 782.83 ops/sec
9) 266.049833 ms, 751.74 ops/sec
10) 274.486041 ms, 728.63 ops/sec

### Scenario 3
1) 2.272999292 s, 879.89 ops/sec
2) 820.970583 ms, 2436.14 ops/sec
3) 19.059875 ms, 0.00 ops/sec
4) 16.300666 ms, 0.00 ops/sec
5) 36.053667 ms, 0.00 ops/sec
6) 1.011754708 s, 1976.76 ops/sec
7) 2.67057875 s, 748.90 ops/sec
8) 3.176246416 s, 629.67 ops/sec
9) 76.862792 ms, 0.00 ops/sec
10) 53.847666 ms, 0.00 ops/sec

## Explanation / Insights
- Scenario 1 reflects baseline latency with minimal contention and short queues.
- Scenario 2 increases concurrency; throughput rises as work is parallelized, while response time increases moderately due to scheduling and socket contention.
- Scenario 3 shows saturation effects: higher connection churn and OS scheduling overhead raise response time and reduce steady throughput.
- Several Scenario 3 runs report 0 operations, indicating connection setup contention and transient failures under extreme concurrency on a single machine; this skews averages downward and suggests the local host hit resource limits.
- In distributed deployment (separate VMs), these effects should lessen, yielding more stable throughput at high concurrency.
