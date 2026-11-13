# sevi.plugin.zsh: shows the latest sound levels at the right edge of the prompt.
#
#   mic -41 ▂ · out -14 ▆
#
# This file never captures audio. It reads the state file that the Sevi helper
# writes, asks macOS to open the helper when a terminal starts, and tells the
# helper which terminals are open. Load it after your theme (after Oh My Zsh is
# sourced), so its hook runs after the theme has set RPROMPT.
#
# Settings, read from the environment:
#   SEVI_LIVE=1    redraw the reading once a second while the prompt is empty
#   SEVI_COLOR=1   show mic in red and out in green (ignored when NO_COLOR is set)
#
# State file, one line (contract version 1):
#   1 <unix ms> <mic dBFS> <mic peak> <out dBFS> <out peak> <mic state> <out state>
#
# Shared invariants with the helper. Change either only together with the
# other side:
#   - Path (Sources/SeviCore/StatePaths.swift): the per-user temporary folder
#     macOS assigns (DARWIN_USER_TEMP_DIR, one trailing slash removed), then
#     /sevi-$UID. $TMPDIR, then /tmp, are used only if the system gives no
#     answer: a shell may override $TMPDIR, and the app never sees that.
#   - Line format (Sources/SeviCore/LevelsSnapshot.swift): the pattern in
#     _sevi_segment accepts exactly what the helper formats.
#   - Sessions (Sources/SeviCore/SessionRegistry.swift): each interactive shell
#     keeps an empty file named after its process ID in <path>/sessions while
#     it is open. The helper stops listening 30 seconds after the last one goes.

zmodload zsh/datetime
zmodload -F zsh/files b:zf_mkdir b:zf_rm
autoload -Uz add-zsh-hook

# Runs once when the plugin loads; nothing is forked per prompt. A value set
# before loading is kept, which is how the tests point it at a scratch folder.
if (( ! ${+_sevi_dir} )); then
  typeset -g _sevi_dir
  () {
    emulate -L zsh
    local dir
    dir=$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null) || dir=''
    [[ -n $dir ]] || dir=${TMPDIR:-/tmp}
    _sevi_dir="${dir%/}/sevi-${UID}"
  }
fi
typeset -g _sevi_state_file=$_sevi_dir/levels

# How the helper is started: macOS opens the app, in the background, by its
# identifier. It must not be run as a child of this shell, or macOS would ask
# for the microphone in the terminal's name instead of Sevi's.
(( ${+_sevi_open} )) || typeset -ga _sevi_open=(/usr/bin/open -gj -b com.nerttiyana.sevi --args daemon)

# What the hook appended to RPROMPT last time, so it can take it off again.
typeset -g _sevi_appended=''
typeset -g _sevi_stale='mic -- · out --'

# Sets REPLY to the first line of file $1, or to nothing if it cannot be read.
_sevi_read() {
  emulate -L zsh
  REPLY=''
  [[ -f $1 && -r $1 ]] || return 0
  { IFS= read -r REPLY < $1 } 2>/dev/null
  return 0
}

# Sets REPLY to one channel's text. $1 label, $2 state, $3 level in dBFS,
# $4 non-empty for colour. Callers pass only fields that _sevi_segment has
# already validated.
_sevi_channel() {
  emulate -L zsh
  if [[ $2 != ok ]]; then
    REPLY="$1 off"
    [[ -n $4 ]] && REPLY="%F{244}$REPLY%f"
    return 0
  fi
  local -F level=$3
  (( level > 0 )) && level=0
  # Assigning a float to an integer truncates towards zero, so subtracting a
  # half first rounds a negative level to the nearest whole number.
  local -i shown=$(( level - 0.5 ))
  # -60..0 dBFS over eight glyphs; the full block is reached only at 0 (clipping).
  local -i index=$(( (level + 60) * 8 / 60 ))
  (( index < 1 )) && index=1
  (( index > 8 )) && index=8
  local -a glyphs=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
  if [[ -z $4 ]]; then
    REPLY="$1 $shown ${glyphs[index]}"
    return 0
  fi
  # Colour tells the two channels apart at a glance: mic red, out green. The
  # labels say the same thing, so colour is never the only signal.
  local colour=green
  [[ $1 == mic ]] && colour=red
  REPLY="%F{$colour}$1 $shown ${glyphs[index]}%f"
}

# Sets REPLY to the prompt segment for state line $1 at time $2 (Unix ms).
# $3 non-empty adds colour.
#
# The line is untrusted: it is matched whole against a strict pattern and only
# the matched numbers and fixed state words are used. Anything else (wrong
# version, extra or missing fields, prompt escapes, command substitutions)
# renders as a stale reading. The line is never evaluated. The only prompt
# escapes in the result are the colour codes written in this file.
_sevi_segment() {
  emulate -L zsh
  local line=$1
  local -i now=$2
  local -a match mbegin mend
  local MATCH MBEGIN MEND
  local num='-?[0-9]{1,3}\.[0-9]'
  REPLY=$_sevi_stale
  [[ -n $3 ]] && REPLY="%F{244}$_sevi_stale%f"

  (( ${#line} <= 96 )) || return 0
  [[ $line =~ "^1 ([0-9]{1,15}) ($num) ($num) ($num) ($num) (ok|denied|nodevice) (ok|denied|unsupported)\$" ]] || return 0

  # Older than two seconds, or dated in the future by more than that, is stale.
  local -i age=$(( now - match[1] ))
  (( age > 2000 || age < -2000 )) && return 0

  local mic
  _sevi_channel mic $match[6] $match[2] "$3"
  mic=$REPLY
  _sevi_channel out $match[7] $match[4] "$3"
  REPLY="$mic · $REPLY"
}

# Sets REPLY to the segment for the state file as it is right now.
# $1 non-empty adds colour.
_sevi_current() {
  emulate -L zsh
  local -a clock=( $epochtime )
  _sevi_read $_sevi_state_file
  _sevi_segment "$REPLY" $(( clock[1] * 1000 + clock[2] / 1000000 )) "$1"
}

# precmd hook: replaces the previous segment at the end of RPROMPT with a fresh
# one and leaves whatever the theme put there in place.
_sevi_precmd() {
  emulate -L zsh
  local colour=''
  [[ $SEVI_COLOR == 1 && -z $NO_COLOR ]] && colour=1
  _sevi_current $colour
  [[ -n $_sevi_appended ]] && RPROMPT=${RPROMPT%$_sevi_appended}
  _sevi_appended="${RPROMPT:+ · }$REPLY"
  RPROMPT+=$_sevi_appended
}

# Records this shell as an open session.
_sevi_register_session() {
  emulate -L zsh
  zf_mkdir -m 700 $_sevi_dir 2>/dev/null
  zf_mkdir -m 700 $_sevi_dir/sessions 2>/dev/null
  { : > $_sevi_dir/sessions/$$ } 2>/dev/null
  return 0
}

# zshexit hook: this shell no longer needs Sevi to listen.
_sevi_unregister_session() {
  emulate -L zsh
  zf_rm -f $_sevi_dir/sessions/$$ 2>/dev/null
  return 0
}

# Asks macOS to open the helper unless a fresh reading shows it is already
# listening. This runs only when a terminal starts, never per prompt, so that
# `sevi stop` stays stopped until a new terminal is opened.
_sevi_start_helper() {
  emulate -L zsh
  setopt no_monitor no_notify
  _sevi_current
  [[ $REPLY == $_sevi_stale ]] || return 0
  $_sevi_open &>/dev/null &!
}

# Live refresh, for SEVI_LIVE=1. Redraws only while the command line is empty
# and no completion menu is open, so typing and menus are never disturbed.
_sevi_live_widget() {
  emulate -L zsh
  [[ -z $BUFFER && $KEYMAP != menuselect ]] || return 0
  _sevi_precmd
  zle reset-prompt
}
zle -N _sevi_live_widget

add-zsh-hook precmd _sevi_precmd

if [[ -o interactive ]]; then
  # The session is registered before the helper is started, so the helper sees
  # it on its first look.
  _sevi_register_session
  add-zsh-hook zshexit _sevi_unregister_session
  _sevi_start_helper

  if [[ $SEVI_LIVE == 1 ]]; then
    # Live refresh uses the shell's idle timer (TMOUT and TRAPALRM). If either
    # is already in use, for example for auto-logout, it is left alone.
    if (( ${+functions[TRAPALRM]} )) || [[ -n $TMOUT && $TMOUT != 0 ]]; then
      print -u2 -r -- 'sevi: live refresh is off because TMOUT or TRAPALRM is already in use.'
    else
      TMOUT=1
      TRAPALRM() { zle && zle _sevi_live_widget }
    fi
  fi
fi
