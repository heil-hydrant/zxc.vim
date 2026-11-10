let s:ActiveWs = []

" Description:
"       Setup a websocket repeater tab.
"
" Argument:
"
"   {   "file": expand("%:p"),
"       "server_info": {
"           "host": b:scheme,
"           "http": v:true
"           "sni" : b:sni }}
"
" Steps:
"   1. Get scratch file
"   2. Build req file and session file
"   3. Open request file and set b:scheme and b:host

func repeater_helper#websocket#Repeat(query)
    let scratch_file = a:query['file']
    call logger#Log("scratch file| " .. scratch_file)
    let req_file = fnamemodify(scratch_file, ':h') .. "/rep.req"
    call tab#add()

    silent execute 'e ' .. req_file
    call SetBufVar(a:query)
    call logger#Log("scheme| " .. b:scheme)
    call logger#Log("host| " .. b:host)
endfunc

" Description:
"       Setup websocket session.
"
" Data Sent:
"       { "WsEstablish": {
"           "file": expand('%'),
"           "server_info": {
"               "http": v:true
"               "host": b:host,
"               "sni": b:sni    } } }
"
" Steps:
"       1. Build tosend dict.
"       2. Send to channel.
"       3. Receive id
"       4. Vertical split open session file
"       5. Split open scratch file
"       6. Iterate over each buffer in the current tab and set buffer variable
"       'rws_id' to id for "scratch.wreq" buffer
"       7. Add id to s:ActiveWs

func s:WsEstablish()
    let tosend = {}

    let tosend["WsEstablish"] = ServerInfo()
    let tosend["WsEstablish"]["file"] = expand('%')

    call logger#Log("WsEstablish| " .. json_encode(tosend))
    let result = ch_evalexpr(g:channel, tosend)

    if result ->has_key("id")
        let id = result.id
        let scratch_file = fnamemodify(expand('%'), ':h') .. "/scratch.wreq"
        let sess_file = fnamemodify(expand('%'), ':h') .. "/history.wsess"
        execute 'vsp ' .. sess_file
        write
        wincmd w
        execute 'sp ' .. scratch_file
        wincmd w
    elseif result ->has_key("error")
        let fail_msg = "ws establish error| " .. result ->get("error")
        call logger#Log(fail_msg)
        echom fail_msg
        return
    else
        let fail_msg = "Recv Error| " .. string(result)
        call logger#Log(fail_msg)
        echom fail_msg
        return
    endif

    " Set buffer variable rws_id
    for buf in tabpagebuflist()
        if fnamemodify(bufname(buf),":t") ==# "scratch.wreq"
            call logger#Log("ws id set| " .. json_encode(buf))
            call setbufvar(buf, 'rws_id', id)
            call add(s:ActiveWs, id)
            return
        endif
    endfor
    let fail_msg = "scratch buffer not found| " .. string(result)
    call logger#Log(fail_msg)
    echom fail_msg
endfunc

" Description:
"       Check if websocket session is closed.
"
" Steps:
"       1. Iterate over each buffer in buffer list.
"       2. Check if buffer name is "scratch.wreq".
"       3. Get buffer variable rws_id
"       4. Check if rws_id is in s:ActiveWs
"       5. If yes, send {WsClose, rws_id} to channel
"       6. Remove rws_id from s:ActiveWs

func s:CheckWsClose()
    for buf in getbufinfo()
        if fnamemodify(buf.name,":t") == "scratch.wreq"
            let rws_id = getbufvar(buf.bufnr, "rws_id")
            let index = index(s:ActiveWs, rws_id)
            if index != -1
                let tosend = {"WsClose": rws_id}
                call logger#Log("WsClosed| " .. string(rws_id))
                call ch_sendexpr(g:channel, tosend)
                call remove(s:ActiveWs, index)
                return
            endif
        endif
    endfor
endfunc

" Description:
"       Send websocket message.
"
" Data Sent:
"       { "WsSend": b:rws_id }

func repeater_helper#websocket#Send()
    let tosend = {"WsSend": b:rws_id}
    call ch_sendexpr(g:channel, tosend)
    call logger#Log("WsSend| " .. b:rws_id)
endfunc

autocmd FileType req command! WsEstablish call s:WsEstablish()
autocmd TabClosed * call s:CheckWsClose()
