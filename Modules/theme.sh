#!/usr/bin/env bash
# modules/theme.sh - Theme and font configuration

setup_themes() {
    log "Setting up Dracula theme and Nerd Fonts..."

    # Create themes directory
    mkdir -p /mnt/usr/share/themes
    mkdir -p /mnt/usr/share/fonts/nerd-fonts
    mkdir -p /mnt/etc/skel/.config/{alacritty,kitty,bat,gtk-3.0,gtk-4.0}
    mkdir -p /mnt/etc/skel/.local/share/themes

    install_nerd_fonts
    setup_dracula_theme
    configure_terminal_themes
    configure_editor_themes
    configure_shell_themes
}

install_nerd_fonts() {
    log "Installing Nerd Fonts..."
    
    # List of fonts to install
    local fonts=(
        "JetBrainsMono"
        "FiraCode"
        "Hack"
        "RobotoMono"
        "SourceCodePro"
    )
    
    # Create temporary directory for downloads
    mkdir -p /mnt/tmp/nerd-fonts
    cd /mnt/tmp/nerd-fonts || error "Failed to create temp directory"
    
    for font in "${fonts[@]}"; do
        log "Downloading ${font} Nerd Font..."
        wget "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.zip" \
            || error "Failed to download ${font}"
        
        unzip -o "${font}.zip" -d "/mnt/usr/share/fonts/nerd-fonts/${font}" \
            || error "Failed to extract ${font}"
    done
    
    # Update font cache
    chroot /mnt /bin/bash -c "fc-cache -fv"
    
    # Cleanup
    rm -rf /mnt/tmp/nerd-fonts
}

setup_dracula_theme() {
    log "Setting up Dracula theme..."
    
    # Clone Dracula themes
    cd /mnt/tmp || error "Failed to enter temp directory"
    
    # GTK Theme
    git clone https://github.com/dracula/gtk.git dracula-gtk
    mkdir -p /mnt/usr/share/themes/Dracula
    cp -r dracula-gtk/* /mnt/usr/share/themes/Dracula/
    
    # Configure GTK settings
    cat > /mnt/etc/skel/.config/gtk-3.0/settings.ini << EOF
[Settings]
gtk-theme-name=Dracula
gtk-icon-theme-name=Dracula
gtk-font-name=JetBrainsMono Nerd Font 10
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=0
gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=1
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
EOF

    # Copy settings for GTK4
    cp /mnt/etc/skel/.config/gtk-3.0/settings.ini /mnt/etc/skel/.config/gtk-4.0/
}

configure_terminal_themes() {
    log "Configuring terminal themes..."
    
    # Alacritty configuration
    cat > /mnt/etc/skel/.config/alacritty/alacritty.yml << 'EOF'
font:
  normal:
    family: JetBrainsMono Nerd Font
    style: Regular
  bold:
    family: JetBrainsMono Nerd Font
    style: Bold
  italic:
    family: JetBrainsMono Nerd Font
    style: Italic
  bold_italic:
    family: JetBrainsMono Nerd Font
    style: Bold Italic
  size: 11.0

colors:
  primary:
    background: '0x282a36'
    foreground: '0xf8f8f2'
  cursor:
    text: CellBackground
    cursor: CellForeground
  vi_mode_cursor:
    text: CellBackground
    cursor: CellForeground
  search:
    matches:
      foreground: '0x44475a'
      background: '0x50fa7b'
    focused_match:
      foreground: '0x44475a'
      background: '0xffb86c'
  footer_bar:
    background: '0x282a36'
    foreground: '0xf8f8f2'
  hints:
    start:
      foreground: '0x282a36'
      background: '0xf1fa8c'
    end:
      foreground: '0xf1fa8c'
      background: '0x282a36'
  selection:
    text: CellForeground
    background: '0x44475a'
  normal:
    black:   '0x21222c'
    red:     '0xff5555'
    green:   '0x50fa7b'
    yellow:  '0xf1fa8c'
    blue:    '0xbd93f9'
    magenta: '0xff79c6'
    cyan:    '0x8be9fd'
    white:   '0xf8f8f2'
  bright:
    black:   '0x6272a4'
    red:     '0xff6e6e'
    green:   '0x69ff94'
    yellow:  '0xffffa5'
    blue:    '0xd6acff'
    magenta: '0xff92df'
    cyan:    '0xa4ffff'
    white:   '0xffffff'
EOF

    # Kitty configuration
    cat > /mnt/etc/skel/.config/kitty/kitty.conf << 'EOF'
font_family JetBrainsMono Nerd Font
bold_font JetBrainsMono Nerd Font Bold
italic_font JetBrainsMono Nerd Font Italic
bold_italic_font JetBrainsMono Nerd Font Bold Italic
font_size 11.0

# Dracula Theme
foreground            #f8f8f2
background            #282a36
selection_foreground  #ffffff
selection_background  #44475a

url_color #8be9fd

# black
color0  #21222c
color8  #6272a4

# red
color1  #ff5555
color9  #ff6e6e

# green
color2  #50fa7b
color10 #69ff94

# yellow
color3  #f1fa8c
color11 #ffffa5

# blue
color4  #bd93f9
color12 #d6acff

# magenta
color5  #ff79c6
color13 #ff92df

# cyan
color6  #8be9fd
color14 #a4ffff

# white
color7  #f8f8f2
color15 #ffffff

# Cursor colors
cursor            #f8f8f2
cursor_text_color background

# Tab bar colors
active_tab_foreground   #282a36
active_tab_background   #f8f8f2
inactive_tab_foreground #282a36
inactive_tab_background #6272a4
EOF
}

configure_editor_themes() {
    log "Configuring editor themes..."
    
    # Neovim theme configuration
    mkdir -p /mnt/etc/skel/.config/nvim/colors
    
    # Update Neovim configuration to use Dracula
    cat >> /mnt/etc/skel/.config/nvim/init.vim << 'EOF'
" Dracula Theme Configuration
Plug 'dracula/vim', { 'as': 'dracula' }
colorscheme dracula

" Configure specific highlights
highlight Normal ctermbg=NONE guibg=NONE
highlight SignColumn ctermbg=NONE guibg=NONE
highlight LineNr ctermbg=NONE guibg=NONE

" Customize status line
let g:airline_theme='dracula'
EOF

    # Configure bat theme
    mkdir -p /mnt/etc/skel/.config/bat
    cat > /mnt/etc/skel/.config/bat/config << EOF
--theme="Dracula"
--style="numbers,changes,header"
EOF
}

configure_shell_themes() {
    log "Configuring shell themes..."
    
    # Update Starship configuration for Dracula theme
    cat > /mnt/etc/skel/.config/starship.toml << 'EOF'
# Dracula Color Palette
[palettes.dracula]
black = "#21222c"
red = "#ff5555"
green = "#50fa7b"
yellow = "#f1fa8c"
blue = "#bd93f9"
pink = "#ff79c6"
purple = "#bd93f9"
cyan = "#8be9fd"
white = "#f8f8f2"
bright_black = "#6272a4"
bright_red = "#ff6e6e"
bright_green = "#69ff94"
bright_yellow = "#ffffa5"
bright_blue = "#d6acff"
bright_pink = "#ff92df"
bright_purple = "#d6acff"
bright_cyan = "#a4ffff"
bright_white = "#ffffff"
background = "#282a36"
foreground = "#f8f8f2"

[username]
style_user = "green bold"
style_root = "red bold"
format = "[$user]($style)"
show_always = true

[hostname]
ssh_only = false
format = "@[$hostname](bold purple) "
disabled = false

[directory]
style = "blue"
read_only = " "
truncation_length = 4
truncate_to_repo = false

[git_branch]
symbol = " "
style = "pink"

[git_state]
format = '[\($state( $progress_current of $progress_total)\)]($style) '
style = "bright_black"

[git_status]
style = "cyan"

[cmd_duration]
style = "yellow"

[character]
success_symbol = "[❯](purple)"
error_symbol = "[❯](red)"
vicmd_symbol = "[❮](green)"
EOF

    # Update ZSH syntax highlighting colors
    cat >> /mnt/etc/zsh/zshrc << 'EOF'
# Dracula theme for ZSH syntax highlighting
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[comment]='fg=#6272A4'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#50FA7B'
ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=#50FA7B'
ZSH_HIGHLIGHT_STYLES[global-alias]='fg=#50FA7B'
ZSH_HIGHLIGHT_STYLES[function]='fg=#50FA7B'
ZSH_HIGHLIGHT_STYLES[command]='fg=#50FA7B'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#50FA7B,italic'
ZSH_HIGHLIGHT_STYLES[autodirectory]='fg=#FFB86C,italic'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#FFB86C'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#FFB86C'
ZSH_HIGHLIGHT_STYLES[back-quoted-argument]='fg=#BD93F9'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#8BE9FD'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#8BE9FD'
ZSH_HIGHLIGHT_STYLES[hashed-command]='fg=#8BE9FD'
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#FF79C6'
ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]='fg=#F8F8F2'
ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter-unquoted]='fg=#F8F8F2'
ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]='fg=#F8F8F2'
ZSH_HIGHLIGHT_STYLES[back-quoted-argument-delimiter]='fg=#FF79C6'
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=#FF79C6'
ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]='fg=#FF79C6'
EOF
}
