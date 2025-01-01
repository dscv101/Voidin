```bash
#!/usr/bin/env bash
# modules/development.sh - Development environment setup

setup_development_environment() {
    log "Setting up development environment..."

    # Install development packages
    log "Installing development packages..."
    chroot /mnt xbps-install -Sy \
        base-devel \
        git \
        python3 \
        python3-pip \
        python3-devel \
        python3-virtualenv \
        python3-pytest \
        python3-mypy \
        python3-black \
        python3-pylint \
        python3-ipython \
        python3-jupyter \
        rust \
        rust-analyzer \
        cargo \
        rust-src \
        rust-doc \
        go \
        nodejs \
        npm \
        postgresql14 \
        postgresql14-contrib \
        postgresql14-devel \
        postgresql14-plpython \
        vim \
        neovim \
        tmux \
        ripgrep \
        fd \
        fzf \
        jq \
        yq \
        shellcheck \
        shfmt \
        ctags \
        cmake \
        clang \
        lldb \
        gdb \
        || error "Failed to install development packages"

    setup_postgres
    setup_python_env
    setup_rust_env
    setup_node_env
    setup_direnv
    setup_vim
    create_dev_dirs
}

setup_postgres() {
    log "Configuring PostgreSQL..."
    
    # Create PostgreSQL configuration directory
    mkdir -p /mnt/etc/postgresql/14/conf.d

    # PostgreSQL main configuration
    cat > /mnt/etc/postgresql/14/conf.d/01-optimizations.conf << 'EOF'
# Connection Settings
max_connections = 100
superuser_reserved_connections = 3

# Memory Configuration
shared_buffers = '4GB'
huge_pages = on
effective_cache_size = '12GB'
maintenance_work_mem = '1GB'
work_mem = '64MB'
temp_buffers = '32MB'
temp_file_limit = '5GB'

# Background Writer
bgwriter_delay = 200ms
bgwriter_lru_maxpages = 100
bgwriter_lru_multiplier = 2.0
bgwriter_flush_after = 512kb

# Async Behavior
max_worker_processes = 16
max_parallel_workers_per_gather = 4
max_parallel_workers = 16
max_parallel_maintenance_workers = 4
parallel_leader_participation = on

# Storage Configuration
wal_sync_method = fdatasync
wal_buffers = '16MB'
min_wal_size = '1GB'
max_wal_size = '4GB'
checkpoint_completion_target = 0.9
checkpoint_timeout = '15min'
wal_compression = on

# Query Tuning
jit = on
max_stack_depth = '6MB'
EOF

    # Initialize PostgreSQL database
    chroot /mnt /bin/bash -c "
        postgresql-setup --initdb
        systemctl enable postgresql
    "
}

setup_python_env() {
    log "Setting up Python development environment..."
    
    chroot /mnt /bin/bash -c "
        # Install Python tools
        python3 -m pip install --upgrade pip
        python3 -m pip install pipx
        pipx ensurepath
        
        # Install development tools
        pipx install poetry
        pipx install black
        pipx install mypy
        pipx install pylint
        pipx install pytest
        pipx install ipython
        
        # Configure poetry
        poetry config virtualenvs.in-project true
    "

    # Create Python configuration
    cat > /mnt/etc/profile.d/python-env.sh << 'EOF'
# Python optimization
export PYTHONOPTIMIZE=2
export PYTHONHASHSEED=random
export PYTHONDONTWRITEBYTECODE=1
export NUMBA_NUM_THREADS=16
export PYTHONWARNINGS="default"

# NumPy/SciPy optimization
export NPY_NUM_BUILD_JOBS=16
export OPENBLAS_NUM_THREADS=16
export MKL_NUM_THREADS=16
EOF
}

setup_rust_env() {
    log "Setting up Rust development environment..."
    
    chroot /mnt /bin/bash -c "
        # Initialize rustup
        rustup default stable
        rustup component add rust-analyzer rust-src clippy
        
        # Install additional tools
        cargo install cargo-watch
        cargo install cargo-edit
        cargo install cargo-expand
        cargo install cargo-audit
    "

    # Create Rust configuration
    cat > /mnt/etc/profile.d/rust-env.sh << 'EOF'
# Rust optimizations
export RUSTFLAGS="-C target-cpu=znver3 -C opt-level=3 -C link-arg=-fuse-ld=mold -C target-feature=+aes,+sse2,+sse3,+ssse3,+sse4.1,+sse4.2,+avx,+avx2,+fma"
export CARGO_HOME="$HOME/.cargo"
export RUSTUP_HOME="$HOME/.rustup"
export PATH="$CARGO_HOME/bin:$PATH"

# Rust parallel compilation
export CARGO_BUILD_JOBS=16

# Rust caching
export CARGO_INCREMENTAL=1
export CARGO_CACHE_RUSTC_INFO=1

# Development tools
export RUST_BACKTRACE=1
export RUST_LOG=info
EOF
}

setup_node_env() {
    log "Setting up Node.js development environment..."
    
    chroot /mnt /bin/bash -c "
        # Install global packages
        npm install -g typescript
        npm install -g ts-node
        npm install -g eslint
        npm install -g prettier
        npm install -g nodemon
    "

    # Create Node.js configuration
    cat > /mnt/etc/profile.d/node-env.sh << 'EOF'
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
export NODE_OPTIONS="--max-old-space-size=8192"
EOF
}

setup_direnv() {
    log "Setting up direnv..."
    
    # Create direnv configuration directory
    mkdir -p /mnt/etc/skel/.config/direnv

    # Create direnv configuration
    cat > /mnt/etc/skel/.config/direnv/direnv.toml << 'EOF'
[global]
load_dotenv = true
strict_env = true
warn_timeout = "500ms"

[whitelist]
prefix = [
    "/home",
    "/projects"
]

[sources]
file = true
env = true
EOF

    # Create direnv hooks
    cat > /mnt/etc/skel/.config/direnv/lib/layout_extra.sh << 'EOF'
layout_python() {
    if [[ ! -d .venv ]]; then
        python -m venv .venv
    fi
    source .venv/bin/activate
}

layout_node() {
    PATH_add node_modules/.bin
    if [[ -f package.json ]]; then
        export NODE_PATH="$PWD/node_modules"
    fi
}

layout_go() {
    PATH_add bin
    export GOPATH="$PWD/vendor:$PWD"
    PATH_add vendor/bin
}

layout_rust() {
    PATH_add target/debug
    PATH_add target/release
}
EOF
}

setup_vim() {
    log "Setting up Vim/Neovim configuration..."
    
    # Create Neovim configuration
    mkdir -p /mnt/etc/skel/.config/nvim
    cat > /mnt/etc/skel/.config/nvim/init.vim << 'EOF'
" Basic Settings
set nocompatible
set number
set relativenumber
set expandtab
set shiftwidth=4
set tabstop=4
set autoindent
set smartindent
set mouse=a
set clipboard+=unnamedplus
set ignorecase
set smartcase
set incsearch
set hlsearch
set hidden
set nobackup
set nowritebackup
set cmdheight=2
set updatetime=300
set shortmess+=c
set signcolumn=yes

" Key Mappings
let mapleader = " "
nnoremap <leader>ff <cmd>Telescope find_files<cr>
nnoremap <leader>fg <cmd>Telescope live_grep<cr>
nnoremap <leader>fb <cmd>Telescope buffers<cr>
nnoremap <leader>fh <cmd>Telescope help_tags<cr>

" Auto-install vim-plug
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" Plugins
call plug#begin()
Plug 'neovim/nvim-lspconfig'
Plug 'hrsh7th/nvim-cmp'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'hrsh7th/cmp-buffer'
Plug 'hrsh7th/cmp-path'
Plug 'L3MON4D3/LuaSnip'
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'folke/tokyonight.nvim'
call plug#end()

" Color scheme
colorscheme tokyonight

" Language Server Configuration
lua << EOF
require'lspconfig'.rust_analyzer.setup{}
require'lspconfig'.pyright.setup{}
require'lspconfig'.tsserver.setup{}
EOF
EOF
}

create_dev_dirs() {
    log "Creating development directories..."
    
    chroot /mnt /bin/bash -c "
        mkdir -p /etc/skel/Projects/{python,rust,go,node,docs}
        mkdir -p /etc/skel/.config/{git,ssh,docker}
        
        # Create example project templates
        mkdir -p /etc/skel/Projects/templates/{python,rust,node}
    "
}
```