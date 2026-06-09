# Socket Transfer Benchmark

SwiftNetwork benchmark for measuring the performance of round-trip datagram transfers over the SocketDatagramProtocol, which uses real system UDP sockets on loopback.

## Usage of the Benchmark

To use this benchmark for performance measurements, make sure that you build it in release:
```
# Navigate into the SwiftNetwork directory and build everything in release:
% swift build -c release

# Navigate into the ./build/release directory and run the executable
./SocketTransfer
```
NOTE: Never run and measure this benchmark as a debug build the performance information will not be valid.

There are a few command line arguments that are accepted:
```
-iterations : The number of transfers to perform. Default: 100.
-size : The size of each datagram payload in bytes. Default: 1000.
-oneway : Run in one-way send mode (no echo). Measures pure write throughput.
```
