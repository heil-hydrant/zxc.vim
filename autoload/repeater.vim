if exists('g:did_session')
    finish
endif
let g:did_session = 1
let g:channel = socket#Connect("repeater")

func s:Send()
    if &ft == 'req'
        call repeater_helper#request#Send()
    elseif &ft == 'wreq'
        call repeater_helper#websocket#Send()
    else
        call logger#Log("unknown ft| " .. &ft)
    endif
endfunc

" Argument:
"       {   "file": r-id/req,
"           "server_info": {
"               "scheme": b:scheme,
"               "host": b:host,
"               "sni": b:sni (only for https and optional) },
"           "is_h2": v:true (optional),
"           "h2_info": {
"               "authority": b:authority,
"               "scheme": b:h2_scheme } (optional) }
"
"
" Steps:
"   1. Get the value of "file" key from message and check extension
"   2. Call appropriate function

func HandleMsg(msg)
    let ext = fnamemodify(a:msg['file'], ':e')
    if ext == 'req'
        call repeater_helper#request#Repeat(a:msg)
    elseif ext == 'wreq'
        call repeater_helper#websocket#Repeat(a:msg)
    else
        call logger#Log("unknown ext| " .. ext)
    endif
endfunc

func s:ApplyServerInfo(info)
    let b:host = a:info.host
    if a:info ->has_key('http')
        let b:scheme = "http"
    else
        let b:scheme = "https"
    endif
    if a:info ->has_key('sni')
        let b:sni = a:info.sni
    endif
endfunc

func s:ApplyH2Info(info)
    let b:is_h2 = 1
    let h2_info = get(a:info, 'h2_info', {})
    if h2_info ->has_key('authority')
        let b:authority = h2_info.authority
    endif
    if h2_info ->has_key('scheme')
        let b:h2_scheme = h2_info.scheme
    endif
endfunc

func SetBufVar(info)
    if a:info ->has_key('server_info') && !empty(a:info.server_info)
        call s:ApplyServerInfo(a:info.server_info)
    endif

    if a:info ->has_key('is_h2')
        if a:info.is_h2
            call s:ApplyH2Info(a:info)
        else
            let b:is_h2 = 0
        endif
    endif

    call SetHostStatusLine()
endfunc

command RepeaterSend call s:Send()
