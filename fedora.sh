#!/bin/sh

[ $(id -u) -eq 0 ] && echo -e "WARNING YOU ARE RUNNING AS ROOT\nonly do this if you want to apply the configuration to the root user"

### SOME INFORMATION ABOUT THE SCRIPT ###

# this script will install software to my (rob9315's) liking.
# some [software] will also be configured and themes applied
# this script doesn't take care of driver installation.
# for nvidia drivers, go to gnome-software, click the three
# dots and select software repositories. enable the nvidia one
# maybe even the steam one

### DEFAULTS ###

LAYOUT=${LAYOUT-"[('xkb', 'us+altgr-intl')]"}
XKB_OPTIONS=${XKB_OPTIONS-"['lv3:ralt_switch', 'compose:caps']"}
FAVORITE_APPS=${FAVORITE_APPS-"['firefox.desktop', 'org.gnome.Nautilus.desktop', 'com.discordapp.Discord.desktop', 'code.desktop']"}
VSCODE_CONFIG=${VSCODE_CONFIG-'{"security.workspace.trust.enabled":false,"telemetry.enableTelemetry":false,"telemetry.enableCrashReporter":false,"workbench.startupEditor":"none","git.autofetch":true}'}
RC_FILES="$HOME/.bashrc"

# if regex matches desktop entries, they are renamed to .desktop.old
DESKTOP_ENTRY_REGEX=${DESKTOP_ENTRY_REGEX-"\/wine-"}

## jq-parseable!!
ENABLED_EXTENSIONS=${ENABLED_EXTENSIONS-'["appindicatorsupport@rgcjonas.gmail.com", "user-theme@gnome-shell-extensions.gcampax.github.com"]'}
DISABLED_EXTENSIONS=${DISABLED_EXTENSIONS-'["background-logo@fedorahosted.org"]'}

### HELPER FUNCTIONS ###

cmd() {
  NAME="$1"
  COMMAND="$2"
  BINDING="$3"
  GSETTINGS_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-$NAME/"

  cmd_prop() {
    GSETTINGS_PATH="$1"
    OPTION="$2"
    VALUE="$3"
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | sed 's/'"'"'/"/g' | sed 's/^@as \[\]$/\[\]/g' | jq ". + [\"$GSETTINGS_PATH\"]" | jq unique | jq -rc)"
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$GSETTINGS_PATH" "$OPTION" "$VALUE"
  }

  cmd_prop "$GSETTINGS_PATH" name "$NAME"
  cmd_prop "$GSETTINGS_PATH" command "$COMMAND"
  cmd_prop "$GSETTINGS_PATH" binding "$BINDING"
}

jq_mod_file() {
  FILEPATH="$1"
  shift
  opts="$@"
  tmp=$(mktemp)
  mkdir -p $(dirname $FILEPATH)
  [ -f "$FILEPATH" ] || echo "{}" >"$FILEPATH"
  jq "$opts" "$FILEPATH" >"$tmp" && cat "$tmp" >"$FILEPATH" && rm "$tmp"
}

sudo_func() {
  sudo su -c "$(declare -p); $(declare -f); $1"
}

escape_regex() {
  printf '%s\n' "$1" | sed -e 's/[]\/$*.^[]/\\&/g'
}

add_to_rc() {
  STRING="$(escape_regex "$1")"
  FILE="$2"
  [ -f "$FILE" ] || touch "$FILE"
  grep -q "$STRING" "$FILE" \
    || echo "$STRING" >>"$FILE"
}

add_to_rcs() {
  STRING=$1
  for rc in "$RC_FILES"; do
    [ -f "$rc" ] || {
      echo "$rc doesn't exist, creating the file"
      touch "$rc"
    }
    add_to_rc "$STRING" "$rc"
  done
}

filtered_dot_old() {
  FILE_EXTENSION="$1"
  BLACKLIST_REGEX="$2"
  shift
  shift
  FILE_PATHS=$@
  find $FILE_PATHS -maxdepth 1 -mindepth 1 \
    | grep "$FILE_EXTENSION\$" | grep "$BLACKLIST_REGEX" \
    | xargs -I "{a}" mv '{a}' '{a}.old'
  find $FILE_PATHS -maxdepth 1 -mindepth 1 \
    | grep "$FILE_EXTENSION.old\$" | grep -v "$BLACKLIST_REGEX" \
    | sed 's/\.old$//' | xargs -I '{a}' mv '{a}.old' '{a}'
}

dnf_remove_multiple() {
  PROGRAMS="$@"
  for PROGRAM in $PROGRAMS; do
    dnf list installed | grep -q "$PROGRAM" && dnf remove -y "$PROGRAM"
  done
}

### SCRIPTS ###

software() {

  ### ADD PUBKEYS ###

  # microsoft public key
  rpm -q gpg-pubkey --qf '%{SUMMARY}\n' | grep "gpgsecurity@microsoft.com" \
    && echo "microsoft public already added" \
    || {
      echo "adding microsoft public key to rpm gpg keys"
      rpm --import https://packages.microsoft.com/keys/microsoft.asc
    }

  ### ADD REPOS ###

  # vscode
  [ -f /etc/yum.repos.d/vscode.repo ] \
    && echo "vscode repo already installed" \
    || {
      echo "adding vscode repo to yum repos config"
      sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
    }

  ### UPDATE PROGRAMS ###

  dnf upgrade -y

  ### INSTALL PROGRAMS ###

  dnf install -y --skip-broken \
    dialog jq \
    git gcc nodejs \
    papirus-icon-theme yaru-theme \
    gnome-tweaks gnome-extensions-app gnome-shell-extension-appindicator \
    xkill dmenu htop vim neovim \
    code \
    fedora-repos-rawhide

  # get latest version of xyz from rawhide
  dnf --disablerepo=* --enablerepo=rawhide -y upgrade \
    yaru-theme

  # potentially fix flatpak repo problem
  mkdir -p /var/lib/flatpak/repo/objects/
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo \
    || {
      # if that didn't work, completely delete the flatpak repo and reinstall from scratch
      rm -rf /var/lib/flatpak/repo/
      flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    }

  flatpak info com.discordapp.Discord &>/dev/null \
    && echo "discord already installed" \
    || {
      echo "installing discord"
      flatpak install flathub com.discordapp.Discord -y
    }
  add_to_rcs 'alias discord="flatpak run com.discordapp.Discord"'

  ### REMOVE BLOAT ###

  dnf_remove_multiple "gnome-shell-extension-background-logo"

  ### REMOVE .DESKTOP FILES ###

  filtered_dot_old "\.desktop" "$DESKTOP_ENTRY_REGEX" "/usr/share/applications" "/usr/local/share/applications"

}

non_privileged() {

  ### DEVELOPMENT SOFTWARE (USER INSTALLATION) ###

  which rustup &>/dev/null \
    && echo "rustup already installed" \
    || {
      echo "installing rustup"
      curl https://sh.rustup.rs -sSf | sh -s -- --default-toolchain nightly -y
      source "$HOME/.cargo/env"
    }

  which deno &>/dev/null \
    && echo "deno already installed" \
    || {
      echo "installing deno"
      curl -fsSL https://deno.land/x/install/install.sh | sh
      [ -f ~/.deno/env ] || echo -e "#!/bin/sh\nexport PATH=~/.deno/bin:\$PATH" >~/.deno/env
      add_to_rcs '. "$HOME/.deno/env"'
      source "$HOME/.deno/env"
    }

  ### GNOME SETTINGS ###

  # theme settings
  gsettings set org.gnome.desktop.interface gtk-theme "Yaru-dark"
  gsettings set org.gnome.desktop.interface icon-theme "Papirus"
  gsettings set org.gnome.desktop.interface cursor-theme "Yaru"
  gsettings set org.gnome.desktop.sound theme-name "Yaru"
  gsettings set org.gnome.shell.extensions.user-theme name "Yaru"

  # extension settings
  gsettings set org.gnome.shell enabled-extensions "$(gsettings get org.gnome.shell enabled-extensions | sed 's/'"'"'/"/g' | sed 's/^@as \[\]$/\[\]/g' | jq ". + $ENABLED_EXTENSIONS" | jq unique | jq -rc)"
  gsettings set org.gnome.shell disabled-extensions "$(gsettings get org.gnome.shell disabled-extensions | sed 's/'"'"'/"/g' | sed 's/^@as \[\]$/\[\]/g' | jq ". + $DISABLED_EXTENSIONS" | jq unique | jq -rc)"
  gsettings set org.gnome.tweaks show-extensions-notice false

  # keyboard layout
  # HINT: find correct one using `ibus list-engine`
  gsettings set org.gnome.desktop.input-sources sources "$LAYOUT"
  gsettings set org.gnome.desktop.input-sources xkb-options "$XKB_OPTIONS"

  ## PINNED APPS ##

  gsettings set org.gnome.shell favorite-apps "$FAVORITE_APPS"

  ## KEYBINDINGS ##

  gsettings set org.gnome.desktop.wm.keybindings close '["<Alt>F4","<Alt><Shift>C"]'
  gsettings set org.gnome.desktop.wm.keybindings switch-windows '["<Alt>Tab"]'
  gsettings set org.gnome.desktop.wm.keybindings switch-windows-backward '["<Alt><Shift>Tab"]'
  gsettings set org.gnome.desktop.wm.keybindings switch-applications '["<Super>Tab"]'
  gsettings set org.gnome.desktop.wm.keybindings switch-applications-backward '["<Super><Shift>Tab"]'

  ## CUSTOM KEYBINDINGS ##

  cmd 'custom-terminal' 'gnome-terminal' '<Shift><Alt>Return'
  cmd 'dmenu' 'sh -c "test $XDG_SESSION_TYPE = x11 && dmenu_run"' '<Alt>semicolon'

  ## MISC ##

  # window button layout
  gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:close"

  #disable natural scroll
  gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll false
  gsettings set org.gnome.desktop.peripherals.mouse natural-scroll false

  # disable hot corner
  gsettings set org.gnome.desktop.interface enable-hot-corners false

  # battery percentage
  gsettings set org.gnome.desktop.interface show-battery-percentage true

  # switcher
  gsettings set org.gnome.shell.app-switcher current-workspace-only true

  ## GNOME APPS ##

  # gedit
  gsettings set org.gnome.gedit.preferences.editor highlight-current-line true
  gsettings set org.gnome.gedit.preferences.editor scheme "Yaru-dark"
  gsettings set org.gnome.gedit.preferences.editor tabs-size 4

  # nautilus
  gsettings set org.gnome.nautilus.icon-view default-zoom-level standard

  ### PROGRAM SETTINGS ###

  # code
  jq_mod_file $(echo "$HOME/.config/Code/User/settings.json") ". + $VSCODE_CONFIG"

  ### REMOVE .DESKTOP FILES ###

  filtered_dot_old "\.desktop" "$DESKTOP_ENTRY_REGEX" "$HOME/.local/share/applications"

}

read -sn 1 -p "Do you want to install software? (requires sudo access) " && echo
[ "$(echo "$REPLY" | tr '[A-Z]' '[a-z]')" = "y" ] && sudo_func software

read -sn 1 -p "Do you want to apply user configuration? " && echo
[ "$(echo "$REPLY" | tr '[A-Z]' '[a-z]')" = "y" ] && non_privileged
