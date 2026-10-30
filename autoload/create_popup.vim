" Description:
"       Set buffer variables from popup.
"       called by pop vim terminal.
"
" Args:
"       bufnum  : integer
"
"       arglist[0]  : target buffer number or variable
"
"       arglist[1..] : dict with keys and values


function Tapi_SetBufVars(bufnum, arglist)
    let dest = remove(a:arglist, 0)
    let bufno = dest ->str2nr()
    if bufno != 0
        for item in a:arglist
            let raw_key = keys(item)[0]
            let val = item[raw_key]
            " Strip leading colons to avoid E461: Illegal variable name
            let key = substitute(raw_key, '^:\+', '', '')
            call setbufvar(bufno, key, val)
        endfor
    else
        if dest == "Scode"
            call SetScode(a:arglist)
        elseif dest == "Host"
            call SetHostScope(a:arglist)
        elseif dest == "Uri"
            call SetUriScope(a:arglist)
        endif
    endif
endfunc

" Description:
"       Create popup window to edit buffer variables
"
" Args:
"       value   : dict / list
"       bufnum  : integer
"
" Steps:
"       1. Build Filename, bufnum.popup
"       2. Convert dict to string
"       3. Start vim in terminal mode hidden.
"       4. Send 'i' to enter insert mode and send string
"       5. Create popup window for the terminal.

func create_popup#Create(value, bufnum)
    let vim_cmd = "vim --cmd \"let g:zxc_winame='popup'\" " .. a:bufnum .. ".popup"
    let val_type = type(a:value)
    if val_type == 4
        let str = s:DictToString(a:value)
    elseif val_type == 3
        let str = a:value ->join("\n")
    endif
    let buf = term_start(vim_cmd, #{hidden: 1, term_finish: 'close'})
    call term_sendkeys(buf, 'i')
    call term_sendkeys(buf, str)
    call term_sendkeys(buf, "\<esc>gg")
    let winid = popup_create(buf, g:popup_options)
endfunc

" convert dict to string
func s:DictToString(dict)
    let str = ""
    for key in keys(a:dict)
        let val = a:dict[key]
        let str .= key . " = " . val . "\n"
    endfor
    return str ->trim()
endfunc
