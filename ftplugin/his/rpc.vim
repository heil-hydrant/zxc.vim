if !check_session#Check()
    finish
endif

" Description:
"       Build Addon info dictionary from current line.
"
" Synatx:
"       id | method | status | size | scheme | host
"
" Returns:
"       { "file": file_name,
"         "server_info": {
"               "host": host
"               "http": bool } }
"
" Steps:
"       1. Split line into list with | as delimiter.
"       2. Get id
"       3. Build file name, g:history_dir/$id/$id.req
"       4. Get scheme and host, by calling Get_Host_Scheme()
"       5. Build dictionary

func s:Build_Req_Info()
    let id = getline('.') ->split(' | ')[0] ->trim()
    let file = g:history_dir .. id .. "/" .. id .. ".req"
    let [scheme, host] = Get_Host_Scheme()
    let server_info = { 'host': host }
    if scheme == "http"
        let server_info['http'] = v:true
    endif
    let tosend = {"file": file, "server_info": server_info}
    let attrs = xattr#Read(file)
    if get(attrs, 'is_h2', '') == '1'
        let tosend['is_h2'] = v:true
        let h2_info = {}
        if has_key(attrs, 'authority')
            let h2_info['authority'] = attrs.authority
        endif
        if has_key(attrs, 'h2_scheme')
            let h2_info['scheme'] = attrs.h2_scheme
        endif
        if !empty(h2_info)
            let tosend['h2_info'] = h2_info
        endif
    endif
    return tosend
endfunc

" Description:
"       Send highlighted request to repeater.
"
" Arg:
"       to : string
"
" Data:
"       { "Forward": {
"           "to": "Repeater",
"           "file": ./history/$id/$id.req,
"           "server_info": {
"               "host": host
"               "http": bool } } }

func s:SendToBinary(to)
    let info = s:Build_Req_Info()
    let info["to"] = a:to
    let tosend = {"Forward": info}
    call logger#Log("Send to Repeater| " .. string(tosend))
    call ch_sendexpr(g:channel, tosend)
endfunc

" Description:
"       Send highlighted request to Addon.
"
" Arg:
"       addon : string
"
" Data:
"       { "Forward": {
"           "to": { "Addon": a:addon },
"           "file": ./history/$id/$id.req,
"           "server_info": {
"               "host": host
"               "http": bool } } }

func HistoryToAddon(addon)
    let addon = { "Addon": a:addon }
    call s:SendToBinary(addon)
endfunc

command-buffer HistoryToRepeater call s:SendToBinary("Repeater")
command-buffer HistoryToFuzz call HistoryToAddon("ffuf")
command-buffer HistoryToSql call HistoryToAddon("sqlmap")
