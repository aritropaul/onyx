.PHONY: crdt server all clean

crdt:
	cd onyx-crdt && ./scripts/build-xcframework.sh

server:
	cargo build --release -p onyx-server

all: crdt server

clean:
	cargo clean
	rm -rf onyx-crdt/OnyxCRDTFFI.xcframework
	rm -rf onyx-crdt/generated

test:
	cargo test --workspace

server-run:
	cargo run --release -p onyx-server

docker-up:
	cd onyx-server && docker compose up --build
