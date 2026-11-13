.PHONY: test test-swift test-plugin gate

test-swift:
	swift test

test-plugin:
	zsh -f Tests/plugin/run.zsh
	zsh -f Tests/plugin/live.zsh

test: test-swift test-plugin

gate: test
