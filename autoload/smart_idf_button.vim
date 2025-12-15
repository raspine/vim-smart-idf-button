" vim-smart-idf-button autoload functions
" All the core ESP-IDF functionality

" Plugin state variables
let s:pending_flash_project_dir = ""
let s:last_build_was_manual = 0

" Helper function to detect available USB serial ports
function! s:detect_usb_port()
    " Check common USB serial device patterns
    " First try ttyUSB* (most common with UART bridges)
    let l:usb_ports = glob('/dev/ttyUSB*', 0, 1)
    if !empty(l:usb_ports)
        return l:usb_ports[0]
    endif
    
    " Then try ttyACM* (boards with native USB like Arduino)
    let l:acm_ports = glob('/dev/ttyACM*', 0, 1)
    if !empty(l:acm_ports)
        return l:acm_ports[0]
    endif
    
    " No USB port found
    return ''
endfunction

" Helper function to build port argument string
function! s:get_port_arg()
    " If user has manually configured a port, use it
    if exists('g:smart_idf_button_port') && g:smart_idf_button_port != ''
        return ' -p ' . g:smart_idf_button_port
    endif
    
    " Otherwise, try to auto-detect USB ports
    let l:detected_port = s:detect_usb_port()
    if l:detected_port != ''
        return ' -p ' . l:detected_port
    endif
    
    " If no port found, return empty string (idf.py will do its own scanning)
    return ''
endfunction

" Main API functions that can be called from outside

" Build function - equivalent to your cmake_build_target for IDF projects
function! smart_idf_button#build()
    let [l:sdkconfig_current, l:sdkconfig_dirs] = s:find_idf_projects()
    
    " Mark that this was a manual build
    let s:last_build_was_manual = 1
    
    if l:sdkconfig_current
        " Current directory has sdkconfig - build directly
        execute 'AsyncRun idf.py' . s:get_port_arg() . ' build'
    elseif len(l:sdkconfig_dirs) > 0
        " Multiple sdkconfig files found, present selection menu
        let l:selected_dir = s:select_idf_project(l:sdkconfig_dirs)
        
        if l:selected_dir != ""
            " Run build in the selected directory
            execute 'AsyncRun idf.py -C ' . l:selected_dir . s:get_port_arg() . ' build'
        else
            echo "Invalid selection or cancelled."
        endif
    else
        echo "No ESP-IDF projects found"
        return 0
    endif
    return 1
endfunction

" Launch function - smart build+flash+monitor or just monitor
function! smart_idf_button#launch()
    " Always stop any running monitor first
    call smart_idf_button#stop_monitor()
    
    let [l:sdkconfig_current, l:sdkconfig_dirs] = s:find_idf_projects()
    
    if l:sdkconfig_current
        " Current directory has sdkconfig - check if build is needed
        if s:needs_build(".") || s:last_build_was_manual
            " Build first in quickfix, then flash and monitor in terminal OR flash+monitor after manual build
            let s:pending_flash_project_dir = "."
            " Reset the manual build flag since we're handling it
            let s:last_build_was_manual = 0
            if s:needs_build(".")
                execute 'AsyncRun idf.py build'
                " Set a callback to run flash+monitor after build completes
                autocmd User AsyncRunStop call s:post_build_flash_monitor()
            else
                " No build needed, but manual build was done - go straight to flash+monitor
                execute 'AsyncRun -mode=term -pos=bottom -rows=20 -focus=0 idf.py' . s:get_port_arg() . ' flash monitor'
                " Clear the stored directory
                let s:pending_flash_project_dir = ""
            endif
        else
            " No build needed, just monitor in terminal
            execute 'AsyncRun -mode=term -pos=bottom -rows=20 -focus=0 idf.py' . s:get_port_arg() . ' monitor'
        endif
    elseif len(l:sdkconfig_dirs) > 0
        " Multiple sdkconfig files found, present selection menu
        let l:selected_dir = s:select_idf_project(l:sdkconfig_dirs)
        
        if l:selected_dir != ""
            " Check if build is needed for the selected directory
            if s:needs_build(l:selected_dir) || s:last_build_was_manual
                " Build first in quickfix, then flash and monitor in terminal OR flash+monitor after manual build
                let s:pending_flash_project_dir = l:selected_dir
                " Reset the manual build flag since we're handling it
                let s:last_build_was_manual = 0
                if s:needs_build(l:selected_dir)
                    execute 'AsyncRun idf.py -C ' . l:selected_dir . ' build'
                    " Set a callback to run flash+monitor after build completes
                    autocmd User AsyncRunStop call s:post_build_flash_monitor()
                else
                    " No build needed, but manual build was done - go straight to flash+monitor
                    execute 'AsyncRun -mode=term -pos=bottom -rows=20 -focus=0 idf.py -C ' . l:selected_dir . s:get_port_arg() . ' flash monitor'
                    " Clear the stored directory
                    let s:pending_flash_project_dir = ""
                endif
            else
                " No build needed, just monitor in terminal
                execute 'AsyncRun -mode=term -pos=bottom -rows=20 -focus=0 idf.py -C ' . l:selected_dir . s:get_port_arg() . ' monitor'
            endif
        else
            echo "Invalid selection or cancelled."
            return 0
        endif
    else
        echo "No ESP-IDF projects found"
        return 0
    endif
    return 1
endfunction

" Monitor function - just start monitoring without build/flash
function! smart_idf_button#monitor()
    let [l:sdkconfig_current, l:sdkconfig_dirs] = s:find_idf_projects()
    
    if l:sdkconfig_current
        execute 'AsyncRun -mode=term -pos=bottom -rows=20 -focus=0 idf.py' . s:get_port_arg() . ' monitor'
    elseif len(l:sdkconfig_dirs) > 0
        let l:selected_dir = s:select_idf_project(l:sdkconfig_dirs)
        
        if l:selected_dir != ""
            execute 'AsyncRun -mode=term -pos=bottom -rows=20 -focus=0 idf.py -C ' . l:selected_dir . s:get_port_arg() . ' monitor'
        else
            echo "Invalid selection or cancelled."
            return 0
        endif
    else
        echo "No ESP-IDF projects found"
        return 0
    endif
    return 1
endfunction

" Stop monitor function
function! smart_idf_button#stop_monitor()
    " Find any terminal buffer that looks like it might be running monitor
    let l:term_bufnr = -1
    for bufnr in range(1, bufnr('$'))
        if bufexists(bufnr) && getbufvar(bufnr, '&buftype') == 'terminal'
            " Check if this buffer name contains monitor-related terms
            let l:bufname = bufname(bufnr)
            if l:bufname =~ 'monitor\|idf\.py\|AsyncRun' || getbufvar(bufnr, '&filetype') == 'terminal'
                let l:term_bufnr = bufnr
                break
            endif
        endif
    endfor
    
    " If we didn't find a specific terminal, try to find any terminal buffer
    if l:term_bufnr == -1
        for bufnr in range(1, bufnr('$'))
            if bufexists(bufnr) && getbufvar(bufnr, '&buftype') == 'terminal'
                let l:term_bufnr = bufnr
                break
            endif
        endfor
    endif
    
    if l:term_bufnr != -1
        " Send Ctrl+] to the terminal to stop monitoring
        call term_sendkeys(l:term_bufnr, "\<C-]>")
        echo "Sent stop signal to terminal (buffer " . l:term_bufnr . ")"
        return 1
    else
        " Don't show message if no terminal found (silent operation)
        return 0
    endif
endfunction

" Check if current directory or subdirectories contain ESP-IDF projects
function! smart_idf_button#has_idf_projects()
    let [l:sdkconfig_current, l:sdkconfig_dirs] = s:find_idf_projects()
    return l:sdkconfig_current || len(l:sdkconfig_dirs) > 0
endfunction

" Get list of IDF project directories
function! smart_idf_button#get_idf_projects()
    return s:find_idf_projects()
endfunction

" Check if build is needed for a specific project
function! smart_idf_button#needs_build(project_dir)
    return s:needs_build(a:project_dir)
endfunction

" Internal helper functions

" Helper function to find ESP-IDF projects
function! s:find_idf_projects()
    let l:sdkconfig_current = filereadable("./sdkconfig")
    let l:sdkconfig_dirs = []
    
    " Find all sdkconfig files in subdirectories
    let l:find_cmd = "find . -name sdkconfig -type f | sed 's#/sdkconfig##' | sort"
    let l:dirs = systemlist(l:find_cmd)
    
    " Process found directories
    for dir in l:dirs
        " Skip current directory as we'll handle it separately
        if dir != "."
            call add(l:sdkconfig_dirs, dir)
        endif
    endfor
    
    return [l:sdkconfig_current, l:sdkconfig_dirs]
endfunction

" Helper function to select an ESP-IDF project when multiple are found
function! s:select_idf_project(dirs)
    let l:choice_list = ["Select ESP-IDF project directory:"]
    let l:i = 1
    for dir in a:dirs
        call add(l:choice_list, l:i . ". " . dir)
        let l:i += 1
    endfor
    
    " Display menu and get selection
    let l:selection = inputlist(l:choice_list)
    
    " Check if selection is valid
    if l:selection > 0 && l:selection <= len(a:dirs)
        return a:dirs[l:selection-1]
    endif
    
    return ""
endfunction

" Helper function to check if build is needed
function! s:needs_build(project_dir)
    let l:build_dir = a:project_dir . "/build"
    let l:binary_file = l:build_dir . "/*.bin"
    
    " Check if build directory exists and has binary files
    if !isdirectory(l:build_dir)
        return 1
    endif
    
    " Find the most recent binary file
    let l:bin_files = glob(l:binary_file, 0, 1)
    if empty(l:bin_files)
        return 1
    endif
    
    " Get the newest binary file timestamp
    let l:newest_bin = 0
    for bin_file in l:bin_files
        let l:bin_time = getftime(bin_file)
        if l:bin_time > l:newest_bin
            let l:newest_bin = l:bin_time
        endif
    endfor
    
    " Check if any source files are newer than the binary
    let l:source_patterns = [a:project_dir . "/**/*.c", a:project_dir . "/**/*.cpp", a:project_dir . "/**/*.h", a:project_dir . "/**/*.hpp", a:project_dir . "/CMakeLists.txt", a:project_dir . "/sdkconfig"]
    
    " Get component directories from CMakeLists.txt
    let l:component_dirs = s:get_component_dirs(a:project_dir)
    let l:components_patterns = []
    
    " Add patterns for each component directory found
    for comp_dir in l:component_dirs
        call add(l:components_patterns, comp_dir . "/**/*.c")
        call add(l:components_patterns, comp_dir . "/**/*.cpp")
        call add(l:components_patterns, comp_dir . "/**/*.h")
        call add(l:components_patterns, comp_dir . "/**/*.hpp")
        call add(l:components_patterns, comp_dir . "/**/CMakeLists.txt")
    endfor
    
    " Check project files
    for pattern in l:source_patterns
        let l:files = glob(pattern, 0, 1)
        for file in l:files
            if getftime(file) > l:newest_bin
                return 1
            endif
        endfor
    endfor
    
    " Check components files
    for pattern in l:components_patterns
        let l:files = glob(pattern, 0, 1)
        for file in l:files
            if getftime(file) > l:newest_bin
                return 1
            endif
        endfor
    endfor
    
    return 0
endfunction

" Helper function to extract component directories from CMakeLists.txt
function! s:get_component_dirs(project_dir)
    let l:cmake_file = a:project_dir . "/CMakeLists.txt"
    let l:component_dirs = []
    
    " Check if CMakeLists.txt exists
    if !filereadable(l:cmake_file)
        return l:component_dirs
    endif
    
    " Read the CMakeLists.txt file
    let l:lines = readfile(l:cmake_file)
    
    for line in l:lines
        " Look for EXTRA_COMPONENT_DIRS setting
        " Handle various formats like:
        " set(EXTRA_COMPONENT_DIRS "path")
        " set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/../../components")
        " set(EXTRA_COMPONENT_DIRS ../components)
        if line =~ '^\s*set\s*(\s*EXTRA_COMPONENT_DIRS\s'
            " Extract the path from the set command - handle both complete and incomplete lines
            let l:match = matchstr(line, 'set\s*(\s*EXTRA_COMPONENT_DIRS\s\+\zs[^)]\+\ze\s*)\?')
            " If that doesn't work, try a more lenient approach
            if l:match == ""
                let l:match = matchstr(line, 'EXTRA_COMPONENT_DIRS\s\+\zs.\{-}\ze\s*)\?$')
            endif
            if l:match != ""
                " Remove quotes if present - handle incomplete quotes better
                let l:path = l:match
                " Remove leading quotes and whitespace
                let l:path = substitute(l:path, '^["[:space:]]*', '', '')
                " Remove trailing quotes and whitespace  
                let l:path = substitute(l:path, '["[:space:]]*$', '', '')
                
                " Handle CMAKE variables
                let l:path = substitute(l:path, '\${CMAKE_CURRENT_SOURCE_DIR}', a:project_dir, 'g')
                let l:path = substitute(l:path, '\$CMAKE_CURRENT_SOURCE_DIR', a:project_dir, 'g')
                
                " If the path is relative, make it absolute by resolving it directly
                if l:path !~ '^/'
                    " Use fnamemodify to resolve the path relative to current working directory
                    let l:path = fnamemodify(l:path, ':p')
                else
                    " Already absolute, just normalize it
                    let l:path = fnamemodify(l:path, ':p')
                endif
                
                " Remove trailing slash
                let l:path = substitute(l:path, '/$', '', '')
                
                " Check if directory exists before adding
                if isdirectory(l:path)
                    call add(l:component_dirs, l:path)
                endif
            endif
        endif
        
        " Also look for list(APPEND EXTRA_COMPONENT_DIRS ...) format
        if line =~ '^\s*list\s*(\s*APPEND\s\+EXTRA_COMPONENT_DIRS\s'
            let l:match = matchstr(line, 'list\s*(\s*APPEND\s\+EXTRA_COMPONENT_DIRS\s\+\zs[^)]\+\ze\s*)\?')
            " If that doesn't work, try a more lenient approach
            if l:match == ""
                let l:match = matchstr(line, 'EXTRA_COMPONENT_DIRS\s\+\zs.\{-}\ze\s*)\?$')
            endif
            if l:match != ""
                " Remove quotes if present
                let l:path = substitute(l:match, '^["\s]*\|["\s]*$', '', 'g')
                
                " Handle CMAKE variables
                let l:path = substitute(l:path, '\${CMAKE_CURRENT_SOURCE_DIR}', a:project_dir, 'g')
                let l:path = substitute(l:path, '\$CMAKE_CURRENT_SOURCE_DIR', a:project_dir, 'g')
                
                " Convert relative paths to absolute
                if l:path !~ '^/'
                    let l:path = a:project_dir . '/' . l:path
                endif
                
                " Normalize the path (resolve ..)
                let l:path = fnamemodify(l:path, ':p')
                " Remove trailing slash
                let l:path = substitute(l:path, '/$', '', '')
                
                " Check if directory exists before adding
                if isdirectory(l:path)
                    call add(l:component_dirs, l:path)
                endif
            endif
        endif
    endfor
    
    return l:component_dirs
endfunction

" Helper function to run flash and monitor after build completes
function! s:post_build_flash_monitor()
    " Remove the autocmd to avoid multiple triggers
    autocmd! User AsyncRunStop
    
    " Check if the build was successful by examining the exit code
    if exists('g:asyncrun_code') && g:asyncrun_code != 0
        echo "Build failed with exit code " . g:asyncrun_code . ". Skipping flash and monitor."
        " Clear the stored directory
        let s:pending_flash_project_dir = ""
        return
    endif
    
    " Run flash and monitor in terminal using the stored project directory
    if s:pending_flash_project_dir == "."
        execute 'AsyncRun -mode=term -pos=bottom -rows=20 -focus=0 idf.py' . s:get_port_arg() . ' flash monitor'
    else
        execute 'AsyncRun -mode=term -pos=bottom -rows=20 -focus=0 idf.py -C ' . s:pending_flash_project_dir . s:get_port_arg() . ' flash monitor'
    endif
    
    " Clear the stored directory
    let s:pending_flash_project_dir = ""
endfunction
