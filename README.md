# vim-smart-idf-button

A Vim plugin for streamlined ESP-IDF development with smart build/flash/monitor
functions and seamless monitoring (the actual button(s) is decided by you).

## Features

- **Smart Build Detection**: Automatically detects if a rebuild is needed based on file timestamps
- **Multi-Project Support**: Handles multiple ESP-IDF projects in subdirectories
- **Seamless Monitoring**: Automatically stops existing monitors before starting new ones
- **Terminal Integration**: Uses Vim's built-in terminal for monitoring with proper focus management
- **Build Separation**: Builds run in quickfix window, flash and monitoring in terminal

## Requirements

- Vim 8.0+ with terminal support
- [vim-asyncrun](https://github.com/skywind3000/asyncrun.vim) plugin
- ESP-IDF toolchain properly installed and configured

## Installation

### Using vim-plug

```vim
Plug 'yourusername/vim-smart-idf-button'
```

### Manual Installation

Clone this repository into your Vim plugins directory:

```bash
cd ~/.vim/pack/plugins/start/
git clone https://github.com/yourusername/vim-smart-idf-button.git
```

## Usage

The plugin provides four main functions that you can map to your preferred keys:

### API Functions

```vim
" Build the current ESP-IDF project
call smart_idf_button#build()

" Smart launch: build+flash+monitor or just monitor based on file changes
call smart_idf_button#launch()

" Start monitoring without build/flash
call smart_idf_button#monitor()

" Stop any running monitor
call smart_idf_button#stop_monitor()
```

### Example Key Mappings

Add these to your `ftplugin/c.vim` or `ftplugin/cpp.vim` or `.vimrc`:

```vim
" F5: Build ESP-IDF project
nnoremap <F5> :call smart_idf_button#build()<CR>

" F6: Stop monitor
nnoremap <F6> :call smart_idf_button#stop_monitor()<CR>

" F7: Smart launch (build+flash+monitor or just monitor)
nnoremap <F7> :call smart_idf_button#launch()<CR>

" F8: Just monitor (without build/flash)
nnoremap <F8> :call smart_idf_button#monitor()<CR>
```

### Helper Functions

```vim
" Check if current directory contains ESP-IDF projects
if smart_idf_button#has_idf_projects()
    echo "ESP-IDF project detected!"
endif

" Get information about IDF projects
let [current_has_sdkconfig, project_dirs] = smart_idf_button#get_idf_projects()

" Check if build is needed for a specific project
if smart_idf_button#needs_build("./my_project")
    echo "Build needed!"
endif
```

## How It Works

### Smart Build Detection

The plugin checks if a build is needed by comparing timestamps between:
- Source files (`*.c`, `*.cpp`, `*.h`, `*.hpp`)
- Build configuration (`CMakeLists.txt`, `sdkconfig`)
- Generated binaries (`build/*.bin`)

If any source file is newer than the newest binary, a build is triggered.

### Multi-Project Support

The plugin automatically detects:
- `sdkconfig` in the current directory
- `sdkconfig` files in subdirectories

When multiple projects are found, it presents a selection menu.

### Workflow

**F7 (Smart Launch) behavior:**
1. Automatically stops any running monitor
2. Checks if build is needed (or if manual build was just done)
3. If build needed: Build in quickfix → Flash+Monitor in terminal
4. If no build needed: Monitor in terminal

**F6 (Stop Monitor) behavior:**
1. Finds terminal buffers running monitor
2. Sends Ctrl+] to stop monitoring
3. Provides feedback on success/failure

## Commands

The plugin also provides these commands:

- `:SmartIDFBuild` - Build the project
- `:SmartIDFLaunch` - Smart launch
- `:SmartIDFMonitor` - Start monitoring
- `:SmartIDFStopMonitor` - Stop monitoring

## Configuration

Currently no configuration options are needed. The plugin (should) work out of the box with standard ESP-IDF project structures.

## License

MIT License - see LICENSE file for details.

## Contributing

Pull requests and issues are welcome!
