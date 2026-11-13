#!/usr/bin/env zsh
# Renders state files through the plugin and compares the prompt segment.
# Run from anywhere with: zsh -f Tests/plugin/run.zsh

here=${0:A:h}
work=$(mktemp -d)
fixtures=$work/fixtures
mkdir $fixtures $work/cwd
# Hostile lines below try to create a file named "pwned"; if one ever ran, it
# would land here.
cd $work/cwd

source $here/../../sevi.plugin.zsh

integer failed=0
integer T=1794582555927
STALE='mic -- · out --'

check() {  # name expected actual
  if [[ $2 == "$3" ]]; then
    print -r -- "ok   $1"
  else
    print -r -- "FAIL $1: expected '$2', got '$3'"
    (( failed++ ))
  fi
}

t() {  # name line age-ms expected
  print -r -- $2 > $fixtures/$1
  _sevi_read $fixtures/$1
  _sevi_segment "$REPLY" $(( T + $3 ))
  check $1 $4 $REPLY
}

# Valid readings. "valid" is the same literal the Swift formatter test produces.
t valid           "1 $T -41.2 -28.5 -13.8 -9.0 ok ok"            73 'mic -41 ▂ · out -14 ▆'
t loud-and-quiet  "1 $T 0.0 0.0 -60.0 -60.0 ok ok"               0 'mic 0 █ · out -60 ▁'
t near-clipping   "1 $T -0.1 0.0 -7.4 0.0 ok ok"                 0 'mic 0 ▇ · out -7 ▇'
t silence         "1 $T -120.0 -120.0 -59.9 -50.0 ok ok"         0 'mic -120 ▁ · out -60 ▁'
t rounds-half     "1 $T -41.5 -28.5 -13.4 -9.0 ok ok"            0 'mic -42 ▂ · out -13 ▆'
t above-zero      "1 $T 3.0 3.0 -13.8 -9.0 ok ok"                0 'mic 0 █ · out -14 ▆'

# Degraded states.
t mic-denied      "1 $T -120.0 -120.0 -13.8 -9.0 denied ok"      0 'mic off · out -14 ▆'
t mic-nodevice    "1 $T -120.0 -120.0 -13.8 -9.0 nodevice ok"    0 'mic off · out -14 ▆'
t out-denied      "1 $T -41.2 -28.5 -120.0 -120.0 ok denied"     0 'mic -41 ▂ · out off'
t out-unsupported "1 $T -41.2 -28.5 -120.0 -120.0 ok unsupported" 0 'mic -41 ▂ · out off'

# Staleness: two seconds is still fresh, one millisecond more is not.
t age-2000        "1 $T -41.2 -28.5 -13.8 -9.0 ok ok"            2000 'mic -41 ▂ · out -14 ▆'
t age-2001        "1 $T -41.2 -28.5 -13.8 -9.0 ok ok"            2001 $STALE
t from-the-future "1 $T -41.2 -28.5 -13.8 -9.0 ok ok"            -2001 $STALE

# Wrong version and malformed lines.
t version-2       "2 $T -41.2 -28.5 -13.8 -9.0 ok ok"            0 $STALE
t blank           ""                                             0 $STALE
t too-few-fields  "1 $T -41.2 -28.5"                             0 $STALE
t extra-field     "1 $T -41.2 -28.5 -13.8 -9.0 ok ok ok"         0 $STALE
t no-decimal      "1 $T -41 -28 -13 -9 ok ok"                    0 $STALE
t bad-state       "1 $T -41.2 -28.5 -13.8 -9.0 ok maybe"         0 $STALE
t swapped-states  "1 $T -41.2 -28.5 -13.8 -9.0 unsupported nodevice" 0 $STALE
t leading-space   " 1 $T -41.2 -28.5 -13.8 -9.0 ok ok"           0 $STALE
t trailing-space  "1 $T -41.2 -28.5 -13.8 -9.0 ok ok "           0 $STALE
t double-space    "1 $T  -41.2 -28.5 -13.8 -9.0 ok ok"           0 $STALE
t huge-number     "1 $T -4111.2 -28.5 -13.8 -9.0 ok ok"          0 $STALE
t long-timestamp  "1 1794582555927179458255 -41.2 -28.5 -13.8 -9.0 ok ok" 0 $STALE
t very-long-line  "1 $T -41.2 -28.5 -13.8 -9.0 ok ok${(l:500:: :):-}" 0 $STALE

# Hostile content: none of it may be expanded, evaluated or shown.
t cmd-subst-state '1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok $(touch pwned)'     0 $STALE
t cmd-subst-level '1 1794582555927 $(touch pwned) -28.5 -13.8 -9.0 ok ok'        0 $STALE
t backticks       '1 1794582555927 `touch pwned` -28.5 -13.8 -9.0 ok ok'         0 $STALE
t arith-subscript '1 x[$(touch pwned)] -41.2 -28.5 -13.8 -9.0 ok ok'             0 $STALE
t arith-in-level  '1 1794582555927 a[$(touch pwned)].0 -28.5 -13.8 -9.0 ok ok'   0 $STALE
t prompt-escape   '1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok%F{red}%n%f'      0 $STALE
t prompt-subst    '1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ${(e):-$(touch pwned)}' 0 $STALE
t semicolon       '1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok; touch pwned'    0 $STALE

# Files that are not a normal one-line file.
: > $fixtures/empty
_sevi_read $fixtures/empty; _sevi_segment "$REPLY" $T
check empty-file $STALE $REPLY

_sevi_read $fixtures/does-not-exist; _sevi_segment "$REPLY" $T
check missing-file $STALE $REPLY

_sevi_read $fixtures; _sevi_segment "$REPLY" $T
check directory-not-file $STALE $REPLY

print -rn -- "1 $T -41.2 -28.5 -13.8 -9.0 ok ok" > $fixtures/no-newline
_sevi_read $fixtures/no-newline; _sevi_segment "$REPLY" $T
check no-trailing-newline 'mic -41 ▂ · out -14 ▆' $REPLY

print -r -- "1 $T -41.2 -28.5 -13.8 -9.0 ok ok"$'\n''$(touch pwned)' > $fixtures/second-line
_sevi_read $fixtures/second-line; _sevi_segment "$REPLY" $T
check second-line-ignored 'mic -41 ▂ · out -14 ▆' $REPLY

# The state path follows the per-user temporary folder, not a shell's TMPDIR.
expected_path="${$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)%/}/sevi-${UID}/levels"
check path-default $expected_path $_sevi_state_file
check path-ignores-tmpdir $expected_path \
  "$(TMPDIR=/somewhere/else zsh -fc 'source $1; print -r -- $_sevi_state_file' _ $here/../../sevi.plugin.zsh)"

# The precmd hook and RPROMPT. The reading here is long stale, so the segment is
# fixed whatever the clock says.
_sevi_state_file=$fixtures/valid

RPROMPT=''
_sevi_precmd
check hook-empty-rprompt $STALE $RPROMPT
_sevi_precmd
check hook-does-not-pile-up $STALE $RPROMPT

RPROMPT='14:32'; _sevi_appended=''
_sevi_precmd
check hook-keeps-theme "14:32 · $STALE" $RPROMPT
_sevi_precmd
check hook-keeps-theme-twice "14:32 · $STALE" $RPROMPT

RPROMPT='%*'
_sevi_precmd
check hook-after-theme-reset "%* · $STALE" $RPROMPT

# A fresh reading through the hook, using the real clock.
clock=( $epochtime )
print -r -- "1 $(( clock[1] * 1000 + clock[2] / 1000000 )) -41.2 -28.5 -13.8 -9.0 ok ok" > $fixtures/fresh
_sevi_state_file=$fixtures/fresh
RPROMPT=''; _sevi_appended=''
_sevi_precmd
check hook-fresh-reading 'mic -41 ▂ · out -14 ▆' $RPROMPT

check hook-is-registered 1 ${precmd_functions[(I)_sevi_precmd]}

# Colour is opt-in and repeats what the number and bar already say.
COLOUR_STALE='%F{244}mic -- · out --%f'
_sevi_segment "1 $T -41.2 -28.5 -13.8 -9.0 ok ok" $T 1
check colour-green-and-yellow '%F{244}mic%f -41 %F{green}▂%f · %F{244}out%f -14 %F{yellow}▆%f' $REPLY
_sevi_segment "1 $T -20.1 -20.1 -20.0 -20.0 ok ok" $T 1
check colour-yellow-starts-at-20 '%F{244}mic%f -20 %F{green}▅%f · %F{244}out%f -20 %F{yellow}▅%f' $REPLY
_sevi_segment "1 $T -6.1 -6.1 -6.0 -6.0 ok ok" $T 1
check colour-red-starts-at-6 '%F{244}mic%f -6 %F{yellow}▇%f · %F{244}out%f -6 %F{red}▇%f' $REPLY
_sevi_segment "1 $T -120.0 -120.0 -13.8 -9.0 denied ok" $T 1
check colour-off '%F{244}mic off%f · %F{244}out%f -14 %F{yellow}▆%f' $REPLY
_sevi_segment "1 $T -41.2 -28.5 -13.8 -9.0 ok ok" $(( T + 2001 )) 1
check colour-stale $COLOUR_STALE $REPLY
_sevi_segment '1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok%F{red}%n%f' $T 1
check colour-hostile-escape $COLOUR_STALE $REPLY

_sevi_state_file=$fixtures/valid
RPROMPT=''; _sevi_appended=''
SEVI_COLOR=1 _sevi_precmd
check hook-colour-on $COLOUR_STALE $RPROMPT
RPROMPT=''; _sevi_appended=''
SEVI_COLOR=1 NO_COLOR=1 _sevi_precmd
check hook-no-color-wins $STALE $RPROMPT
RPROMPT=''; _sevi_appended=''
SEVI_COLOR=yes _sevi_precmd
check hook-colour-needs-1 $STALE $RPROMPT
RPROMPT='14:32'; _sevi_appended=''
SEVI_COLOR=1 _sevi_precmd; SEVI_COLOR=1 _sevi_precmd
check hook-colour-does-not-pile-up "14:32 · $COLOUR_STALE" $RPROMPT

# Sessions: one file per shell, in a private folder, removed on exit.
_sevi_dir=$work/state
_sevi_state_file=$_sevi_dir/levels
_sevi_register_session
sessions=( $_sevi_dir/sessions/*(N:t) )
check session-registered 1 ${#sessions}
check session-named-after-pid $$ "$(print -r -- $_sevi_dir/sessions/*(N:t))"
check session-folder-private '700 700' "$(/usr/bin/stat -f %Lp $_sevi_dir) $(/usr/bin/stat -f %Lp $_sevi_dir/sessions)"
_sevi_register_session
check session-register-twice $$ "$(print -r -- $_sevi_dir/sessions/*(N:t))"
_sevi_unregister_session
check session-removed '' "$(print -r -- $_sevi_dir/sessions/*(N:t))"
_sevi_unregister_session
check session-remove-twice-is-quiet 0 $?

# Starting the helper. The real opener is replaced, so nothing is launched.
wait_for() {  # file
  repeat 30; do [[ -e $1 ]] && return 0; sleep 0.1; done
  return 1
}
_sevi_open=(/usr/bin/touch $work/opened)
_sevi_start_helper
wait_for $work/opened
check start-opens-when-stale 0 $?

/bin/rm -f $work/opened
clock=( $epochtime )
print -r -- "1 $(( clock[1] * 1000 + clock[2] / 1000000 )) -41.2 -28.5 -13.8 -9.0 ok ok" > $_sevi_state_file
_sevi_start_helper
sleep 0.5
[[ -e $work/opened ]]
check start-skips-when-already-listening 1 $?

# Sourcing in a script (not an interactive shell) must not register or start.
/bin/rm -f $_sevi_state_file
(
  _sevi_open=(/usr/bin/touch $work/opened-by-script)
  source $here/../../sevi.plugin.zsh
  sleep 0.5
)
[[ -e $work/opened-by-script ]]
check script-does-not-start-helper 1 $?
check script-does-not-register '' "$(print -r -- $_sevi_dir/sessions/*(N:t))"

leftovers=( $work/cwd/*(N) )
check nothing-executed 0 ${#leftovers}

rm -rf $work
if (( failed )); then
  print -r -- "$failed failed"
  exit 1
fi
print -r -- 'all passed'
