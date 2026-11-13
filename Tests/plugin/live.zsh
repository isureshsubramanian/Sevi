#!/usr/bin/env zsh
# Drives a real interactive shell in a pseudo-terminal to check the parts of
# the plugin that only exist there: helper start, session files and the opt-in
# live refresh. The real opener is replaced, so nothing is launched.
# Run from anywhere with: zsh -f Tests/plugin/live.zsh

zmodload zsh/zpty zsh/zselect zsh/datetime

here=${0:A:h}
plugin=${here:h:h}/sevi.plugin.zsh
work=$(mktemp -d)
state=$work/state
integer failed=0

check() {  # name expected actual
  if [[ $2 == "$3" ]]; then
    print -r -- "ok   $1"
  else
    print -r -- "FAIL $1: expected '$2', got '$3'"
    (( failed++ ))
  fi
}

publish() {  # mic out
  local -a clock=( $epochtime )
  print -r -- "1 $(( clock[1] * 1000 + clock[2] / 1000000 )) $1 $1 $2 $2 ok ok" > $state/levels.tmp
  /bin/mv $state/levels.tmp $state/levels
}

# Collects what the shell prints for $1 tenths of a second into `screen`.
typeset screen=''
watch() {
  local chunk
  repeat $1; do
    while zpty -r -t shell chunk 2>/dev/null; do screen+=$chunk; done
    zselect -t 10
  done
}

mkdir $state
zpty -b shell env TERM=xterm-256color SEVI_LIVE=1 zsh -f -i
zpty -w shell "PS1='P> '; _sevi_dir=$state; typeset -ga _sevi_open=(/usr/bin/touch $work/opened); source $plugin"
watch 10

sessions=( $state/sessions/*(N:t) )
check registers-one-session 1 ${#sessions}
[[ -e $work/opened ]]
check starts-helper-on-load 0 $?
[[ $screen == *'mic -- · out --'* ]]
check shows-stale-before-helper-writes 0 $?
[[ $screen != *'['[0-9]']'* ]]
check no-job-notices 0 $?

# Live refresh: the reading changes with no key pressed.
screen=''
publish -41.2 -13.8
watch 25
[[ $screen == *'mic -41 ▂ · out -14 ▆'* ]]
check live-redraws-idle-prompt 0 $?

# While a command is being typed the line is left alone.
zpty -w -n shell 'print typed'
watch 5
screen=''
publish -30.0 -30.0
watch 25
[[ $screen != *'mic -30'* ]]
check live-leaves-typing-alone 0 $?

# Enter runs the command and the next prompt carries the new reading.
publish -30.0 -30.0
zpty -w -n shell $'\n'
watch 10
[[ $screen == *'typed'* && $screen == *'mic -30 ▄ · out -30 ▄'* ]]
check next-prompt-is-fresh 0 $?

zpty -w shell 'exit'
watch 10
sessions=( $state/sessions/*(N:t) )
check exit-removes-session 0 ${#sessions}
zpty -d shell 2>/dev/null

# An idle timer that is already in use is not taken over.
screen=''
zpty -b shell env TERM=xterm-256color SEVI_LIVE=1 zsh -f -i
zpty -w shell "TMOUT=600; _sevi_dir=$state; typeset -ga _sevi_open=(/usr/bin/true); source $plugin; print tmout=\$TMOUT"
watch 10
[[ $screen == *'tmout=600'* && $screen == *'live refresh is off'* ]]
check live-respects-existing-tmout 0 $?
zpty -w shell 'exit'
watch 5
zpty -d shell 2>/dev/null

/bin/rm -rf $work
if (( failed )); then
  print -r -- "$failed failed"
  exit 1
fi
print -r -- 'all passed'
