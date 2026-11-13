# sevi.plugin.zsh: shows the latest sound levels at the right edge of the prompt.
#
#   mic -41 ▂ · out -14 ▆
#
# This file only reads the state file that the sevi helper writes. It never
# captures audio. Load it after your theme (after Oh My Zsh is sourced), so its
# hook runs after the theme has set RPROMPT.
#
# State file, one line (contract version 1):
#   1 <unix ms> <mic dBFS> <mic peak> <out dBFS> <out peak> <mic state> <out state>
#
# Shared invariants with the helper. Change either only together with the
# other side:
#   - Path (Sources/SeviCore/StatePaths.swift): the per-user temporary folder
#     macOS assigns (DARWIN_USER_TEMP_DIR, one trailing slash removed), then
#     /sevi-$UID/levels. $TMPDIR, then /tmp, are used only if the system gives
#     no answer: a shell may override $TMPDIR, and the app never sees that.
#   - Line format (Sources/SeviCore/LevelsSnapshot.swift): the pattern in
#     _sevi_segment accepts exactly what the helper formats.

zmodload zsh/datetime
autoload -Uz add-zsh-hook

typeset -g _sevi_state_file
# Runs once when the plugin loads; nothing is forked per prompt.
() {
  emulate -L zsh
  local dir
  dir=$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null) || dir=''
  [[ -n $dir ]] || dir=${TMPDIR:-/tmp}
  _sevi_state_file="${dir%/}/sevi-${UID}/levels"
}
# What the hook appended to RPROMPT last time, so it can take it off again.
typeset -g _sevi_appended=''

# Sets REPLY to the first line of file $1, or to nothing if it cannot be read.
_sevi_read() {
  emulate -L zsh
  REPLY=''
  [[ -f $1 && -r $1 ]] || return 0
  { IFS= read -r REPLY < $1 } 2>/dev/null
  return 0
}

# Sets REPLY to one channel's text. $1 label, $2 state, $3 level in dBFS.
# Callers pass only fields that _sevi_segment has already validated.
_sevi_channel() {
  emulate -L zsh
  if [[ $2 != ok ]]; then
    REPLY="$1 off"
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
  REPLY="$1 $shown ${glyphs[index]}"
}

# Sets REPLY to the prompt segment for state line $1 at time $2 (Unix ms).
#
# The line is untrusted: it is matched whole against a strict pattern and only
# the matched numbers and fixed state words are used. Anything else (wrong
# version, extra or missing fields, prompt escapes, command substitutions)
# renders as a stale reading. The line is never evaluated.
_sevi_segment() {
  emulate -L zsh
  local line=$1
  local -i now=$2
  local -a match mbegin mend
  local MATCH MBEGIN MEND
  local num='-?[0-9]{1,3}\.[0-9]'
  REPLY='mic -- · out --'

  (( ${#line} <= 96 )) || return 0
  [[ $line =~ "^1 ([0-9]{1,15}) ($num) ($num) ($num) ($num) (ok|denied|nodevice) (ok|denied|unsupported)\$" ]] || return 0

  # Older than two seconds, or dated in the future by more than that, is stale.
  local -i age=$(( now - match[1] ))
  (( age > 2000 || age < -2000 )) && return 0

  local mic
  _sevi_channel mic $match[6] $match[2]
  mic=$REPLY
  _sevi_channel out $match[7] $match[4]
  REPLY="$mic · $REPLY"
}

# precmd hook: replaces the previous segment at the end of RPROMPT with a fresh
# one and leaves whatever the theme put there in place.
_sevi_precmd() {
  emulate -L zsh
  local -a clock=( $epochtime )
  _sevi_read $_sevi_state_file
  _sevi_segment "$REPLY" $(( clock[1] * 1000 + clock[2] / 1000000 ))
  [[ -n $_sevi_appended ]] && RPROMPT=${RPROMPT%$_sevi_appended}
  _sevi_appended="${RPROMPT:+ · }$REPLY"
  RPROMPT+=$_sevi_appended
}

add-zsh-hook precmd _sevi_precmd
