if !check_session#Check() && exists("b:did_ftplugin")
    finish
endif

" Set local options as scratch buffer for popup vim.
func s:SetVar()
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    call s:SendVar()
    execute 'q!'
endfunc

" Description:
"       Send buffer variables to the original buffer.
"
" Steps:
"       1. The filename is of format, bufno.popup or variable_name.popup
"       Get bufno and push to the list 
"       2. For each line in the buffer,
"           a. split the line by '=' to get variable and value 
"           b. build dictionary with variable and value
"           c. Send cmd to original session window by calling Tapi_SetBufVars
"           with the list

func s:SendVar()
    let list = []
    let target = expand('%:r')
    call add(list, target)

    if str2nr(target) == 0
        for index in range(1, line('$'))
            call add(list, getline(index))
        endfor
        let list = list ->map('trim(v:val)') ->filter('!empty(v:val)')
    else
        for index in range(1, line('$'))
            let raw_line = getline(index)
            let eq_idx = stridx(raw_line, '=')
            if eq_idx < 1
                continue
            endif
            let raw_key = trim(raw_line[: eq_idx - 1])
            let val = trim(raw_line[eq_idx + 1 :])
            " Strip leading colons: Vim rejects names like b::authority
            let key = substitute(raw_key, '^:\+', '', '')
            if !empty(key)
                call add(list, {key: val})
            endif
        endfor
    endif

    exe "set t_ts=\<Esc>]51; t_fs=\x07"
    let &titlestring = '["call", "Tapi_SetBufVars", ' .. json_encode(list) .. ']'
    redraw
    set t_ts& t_fs&
endfunc

set title
autocmd BufWritePre *.popup call s:SetVar()
