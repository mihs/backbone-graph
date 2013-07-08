.PHONY: build test

build:
	@find src -name '*.coffee' | xargs node_modules/coffee-script/bin/coffee -c -o lib

test: build
	node_modules/mocha/bin/mocha
