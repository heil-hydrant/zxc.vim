if !check_session#Check() && exists("b:did_ftplugin")
    finish
endif
let b:did_ftplugin = 1

" Arg:
"       to : string
"
" Data sent:
"           {   'to': a:to,
"               'file': expand('%'),
"               'server_info': {
"                   'http': v:true
"                   'host': b:host
"                   'sni': b:sni } }

func s:SendToBinary(to)
    let info = ServerInfo()
    let info["to"] = a:to
    let info["file"] = expand('%')
    let tosend = {"Forward": info}
    call logger#Log("Send to Repeater| " .. string(tosend))
    call ch_sendexpr(g:channel, tosend)
endfunc

func RequestToAddon(addon)
    let addon = { "Addon": a:addon }
    call s:SendToBinary(addon)
endfunc

func SetHostStatusLine()
    if !exists('b:scheme') 
        let b:scheme = "https"
    endif

    if !exists('b:host') 
        let b:host = ""
        if g:has_getfattr
            let cmd = "getfattr -dm user " .. expand('%')
            let result = system(cmd) ->split("\n") [1:-2]
            for e in result
                if stridx(e, "user.host") == 0
                    let b:host = e ->split("=")[1] ->trim('"')
                elseif stridx(e, "user.http") == 0
                    let b:scheme = "http"
                endif
            endfor
        endif
    endif
    setl statusline=\>
    setl statusline+=\ %{b:scheme}
    setl statusline+=%=
    setl statusline+=\>
    setl statusline+=\ %{b:host}
endfunc

" Steps:
"       1. Build dict
"           { "host"    : b:host
"             "scheme"  : http
"             "sni"     : b:sni
"             "update"  : b:update }
"
"       2. Call create_popup#Create with dict and current buffer number

func s:EditBufVar()
    let is_h2 = get(b:, 'is_h2', 0) == 1
    let vars = {}

    if is_h2
        let vars["authority"] = get(b:, 'authority', '')
        let vars["h2_scheme"] = get(b:, 'h2_scheme', '')
    else
        let vars["host"] = b:host
        if exists("b:scheme")
            let vars["scheme"] = b:scheme
        else
            let vars["scheme"] = "https"
        endif
    endif

    if exists("b:update")
        let vars["update"] = b:update
    else
        let vars["update"] = v:true
    endif

    " Sni only applies to new TLS connections, not multiplexed H2 streams
    if !is_h2 && vars["scheme"] == "https" && exists("b:sni")
        let vars["sni"] = b:sni
    endif

    call create_popup#Create(vars, bufnr("%"))
endfunc

func s:Exist_scheme_host()
    if !exists('b:host') && !empty('b:host')
        echom "no host"
        return v:false
    endif

    if !exists('b:scheme')
        let b:scheme = "https"
    endif
    return v:true
endfunc

" Steps:
"       If b:scheme is https set http to v:true. Else skip since, binary by
"       default sends to https.
"
" Returns:
"       { "server_info": {
"               "host"  : b:host
"               "http"  : v:true
"               "sni"   : b:sni } }

func ServerInfo()
    if !s:Exist_scheme_host()
        return
    endif
    let server_info = { "host": b:host }
    if b:scheme == 'http'
        let server_info["http"] = v:true
    elseif b:scheme == 'https' && exists('b:sni') && !empty(b:sni)
        let server_info["sni"] = b:sni
    endif
    let info = { "server_info": server_info}
    return info
endfunc

autocmd BufWinEnter *.req call SetHostStatusLine()

command-buffer RequestToRepeater call s:SendToBinary("Repeater")
command-buffer RequestToFuzz call RequestToAddon("ffuf")
command-buffer RequestToSql call RequestToAddon("sqlmap")
command-buffer EditBufVar call s:EditBufVar()
