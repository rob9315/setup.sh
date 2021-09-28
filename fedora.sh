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
RC_FILES="$HOME/.bashrc"

### HELPER FUNCTIONS ###

cmd() {
  GSETTINGS_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$1/"
  NAME="$2"
  COMMAND="$3"
  BINDING="$4"

  cmd_prop() {
    GSETTINGS_PATH="$1"
    OPTION="$2"
    VALUE="$3"
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | sed 's/'"'"'/"/g' | sed 's/^@as \[\]$/\[\]/g' | jq ". + [\"$GSETTINGS_PATH\"]" | jq unique | jq -rc)"
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$GSETTINGS_PATH" $OPTION $VALUE
  }

  cmd_prop "$GSETTINGS_PATH" name "$NAME"
  cmd_prop "$GSETTINGS_PATH" command "$COMMAND"
  cmd_prop "$GSETTINGS_PATH" binding "$BINDING"
}

jq_mod_file() {
  FILEPATH=$1
  shift
  opts=$@
  tmp=$(mktemp)
  [ -f $FILEPATH ] || echo "{}" >$FILEPATH
  jq "$opts" $FILEPATH >$tmp && cat $tmp >$FILEPATH && rm $tmp
}

sudo_func() {
  func=$1
  sudo su -c "$(declare -f $func);$func"
}

escape_regex() {
  printf '%s\n' "${!1}" | sed -e 's/[]\/$*.^[]/\\&/g'
}

add_to_rc() {
  STRING=$1
  FILE=$2
  [ -f $FILE ] || touch $FILE
  grep -q "$(escape_regex STRING)" $FILE \
    || echo "$STRING" >>$FILE
}

add_to_rcs() {
  STRING=$1
  for rc in "$RC_FILES"; do
    [ -f "$rc" ] || touch "$rc"
    add_to_rc "$STRING" "$rc"
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

  # vscodes
  [ -f /etc/yum.repos.d/vscode.repo ] \
    && echo "vscode repo already installed" \
    || {
      echo "adding vscode repo to yum repos config"
      sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
    }

  ### UPDATE PROGRAMS ###
  dnf upgrade -y

  ### INSTALL PROGRAMS ###
  dnf install -y dialog \
    git gcc nodejs \
    papirus-icon-theme yaru-theme \
    gnome-tweaks gnome-extensions-app gnome-shell-extension-appindicator \
    xkill dmenu htop \
    code

  flatpak info com.discordapp.Discord &>/dev/null \
    && echo "discord already installed" \
    || {
      echo "installing discord"
      flatpak install com.discordapp.Discord -y
    }

  ### REMOVE BLOAT ###
  dnf list installed | grep -q gnome-shell-extension-background-logo \
    && {
      echo "uninstalling background-logo"
      dnf remove -y gnome-shell-extension-background-logo
    } \
    || echo "background-logo already uninstalled"
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
  gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com
  gnome-extensions disable background-logo@fedorahosted.org

  # keyboard layout
  # HINT: find correct one using `ibus list-engine`
  gsettings set org.gnome.desktop.input-sources sources "$LAYOUT"

  ## KEYBINDINGS ##

  gsettings set org.gnome.desktop.wm.keybindings close '["<Alt>F4","<Alt><Shift>C"]'
  gsettings set org.gnome.desktop.wm.keybindings switch-windows '["<Alt>Tab"]'
  gsettings set org.gnome.desktop.wm.keybindings switch-windows-backward '["<Alt><Shift>Tab"]'
  gsettings set org.gnome.desktop.wm.keybindings switch-applications '["<Super>Tab"]'
  gsettings set org.gnome.desktop.wm.keybindings switch-applications-backward '["<Super><Shift>Tab"]'

  ## CUSTOM KEYBINDINGS ##

  cmd Terminal 'custom-terminal' 'gnome-terminal' '<Shift><Alt>Return'
  cmd Dmenu 'dmenu' 'dmenu_run' '<Alt>semicolon'

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
  jq_mod_file $(pwd)'/.config/Code/User/settings.json' \
    '. + {"security.workspace.trust.enabled":false,"telemetry.enableTelemetry":false,"telemetry.enableCrashReporter":false,"workbench.startupEditor":"none"}'

  ### REMOVE POSSIBLE WINE DESKTOP FILES ###

}

read -sn 1 -p "Do you want to install software? (requires sudo access) " REPLY && echo
[ "$(echo $REPLY | tr '[A-Z]' '[a-z]')" = "y" ] && sudo_func software

read -sn 1 -p "Do you want to apply configuration? " REPLY && echo
[ "$(echo $REPLY | tr '[A-Z]' '[a-z]')" = "y" ] && non_privileged
