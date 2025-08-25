" vim-smart-idf-button - Smart ESP-IDF development helper
" Version: 1.0.0
" Author: Your Name
" License: MIT

if exists('g:loaded_smart_idf_button')
    finish
endif
let g:loaded_smart_idf_button = 1

" Save cpo
let s:save_cpo = &cpo
set cpo&vim

" Plugin commands
command! SmartIDFBuild call smart_idf_button#build()
command! SmartIDFLaunch call smart_idf_button#launch()
command! SmartIDFMonitor call smart_idf_button#monitor()
command! SmartIDFStopMonitor call smart_idf_button#stop_monitor()

" Restore cpo
let &cpo = s:save_cpo
unlet s:save_cpo
