.PHONY: test test-swift test-plugin gate

test-swift:
	swift test

test-plugin:
	zsh -f Tests/plugin/run.zsh

test: test-swift test-plugin

gate: test
