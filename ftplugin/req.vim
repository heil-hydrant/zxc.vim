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
"                   'sni': b:sni },
"               'is_h2': v:true,
"               'h2_info': {
"                   'authority': b:authority,
"                   'scheme': b:h2_scheme } }

func s:BuildForwardInfo()
    call SetHostStatusLine()
    let info = ServerInfo()
    if empty(info)
        return {}
    endif

    if get(b:, 'is_h2', 0) == 1
        let info["is_h2"] = v:true
        let h2_info = {}
        if exists('b:authority')
            let h2_info["authority"] = b:authority
        endif
        if exists('b:h2_scheme')
            let h2_info["scheme"] = b:h2_scheme
        endif
        if !empty(h2_info)
            let info["h2_info"] = h2_info
        endif
    endif

    return info
endfunc

func s:SendToBinary(to)
    let info = s:BuildForwardInfo()
    if empty(info)
        echom "no host"
        return
    endif
    let info["to"] = a:to
    let info["file"] = expand('%')
    let tosend = {"Forward": info}
    call logger#Log("Sent| " .. string(tosend))
    call ch_sendexpr(g:channel, tosend)
endfunc

func RequestToAddon(addon)
    let addon = { "Addon": a:addon }
    call s:SendToBinary(addon)
endfunc

" Description:
"       Load request metadata from extended attributes.
"
"       ForwardInfo values already set on the buffer take priority. Xattrs
"       only fill variables that are still missing, which keeps directly
"       opened request files working on both Linux and macOS.

func s:LoadXattrVars()
    if get(b:, 'xattr_loaded', 0)
        return
    endif
    let b:xattr_loaded = 1

    let attrs = xattr#Read(expand('%'))
    if empty(attrs)
        return
    endif

    if !exists('b:host') && has_key(attrs, 'host')
        let b:host = attrs.host
    endif

    if !exists('b:scheme')
        let b:scheme = has_key(attrs, 'http') ? "http" : "https"
    endif

    if !exists('b:sni') && has_key(attrs, 'sni')
        let b:sni = attrs.sni
    endif

    if !exists('b:is_h2') && get(attrs, 'is_h2', '') == '1'
        let b:is_h2 = 1
    endif

    if get(b:, 'is_h2', 0) == 1
        if !exists('b:authority') && has_key(attrs, 'authority')
            let b:authority = attrs.authority
        endif
        if !exists('b:h2_scheme') && has_key(attrs, 'h2_scheme')
            let b:h2_scheme = attrs.h2_scheme
        endif
    endif
endfunc

func SetHostStatusLine()
    if !exists('b:host') || !exists('b:scheme')
          \ || (get(b:, 'is_h2', 0) == 1
          \     && (!exists('b:authority') || !exists('b:h2_scheme')))
        call s:LoadXattrVars()
    endif

    if !exists('b:scheme')
        let b:scheme = "https"
    endif

    if !exists('b:host')
        let b:host = ""
    endif

    setl statusline=\>
    setl statusline+=\ %{b:scheme}
    setl statusline+=%=
    setl statusline+=\>
    setl statusline+=\ %{b:host}
    if get(b:, 'is_h2', 0) == 1
        setl statusline+=\ [h2]
    endif
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
