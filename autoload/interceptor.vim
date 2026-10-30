if exists('g:did_session')
    finish
endif
let g:did_session = 1

let g:channel = socket#Connect("interceptor")
let g:toggle = 0
let g:history_dir = "./history/"

" Format:
"     {   'id': 1,
"         'ft': 'req',
"         'server_info': {
"               'host': 'www.google.com', 
"               'http': false,
"               'sni': 'admin.goolg.com'
"               },
"         'ws_info': {
"             'log_id': 1
"             'is_bin: true
"             }
"         }
"
" Steps:
"       1. Get extension and id from message
"
"       2. Build filename.
"           a. http request/response
"               g:history_dir / id / id . extension
"           b. websocket request/response
"               g:history_dir / id / websocket / log_id . extension
"
"       3. Find number of files in buffer
"           If buffer count is 1
"               a. check if buffer has name
"               b. If no name edit the file
"               c. else add to the buffer
"
"       4. Set id buf var
"
"       5. If filetype is request, set request specific variables,
"               host & scheme,
"               old_host & old_scheme (for verification if has been modified)
"               if sni exists, set old_sni and sni
"
"       6. If filetype is websocket request/response, set websocket specific
"           variables, log_id

func HandleMsg(msg)
    let ft = a:msg.ft
    let id = a:msg.id

    " 2. Build filename
    if ft == "req" || ft == "res"
        let filename = g:history_dir .. id .. "/" .. id .. "." .. ft
    elseif ft == "wreq" || ft == "wres"
        let filename = g:history_dir .. id .. "/websocket/" .. a:msg.ws_info.log_id .. "." .. ft
    endif
    call logger#Log("Filename| " .. filename)

    " 3. Add buffer
    let buf_count = len(getbufinfo({'buflisted': 1}))
    if buf_count == 1 && empty(bufname("%"))
        silent execute 'e! ' .. filename
    else
        let was_added = 1
        silent execute 'badd ' .. filename
    endif

    " 4. Set id Buffer variable
    call setbufvar('$', "id", id)

    " 5. Set Request Buffer variables
    if ft == "req"
        let is_h2 = get(a:msg, "is_h2", v:false) == v:true
        call setbufvar('$', "is_h2", is_h2 ? 1 : 0)

        " Destination host/scheme come from server_info. They are not the
        " HTTP/2 :authority / :scheme pseudo-headers.
        let host = a:msg.server_info.host
        if has_key(a:msg.server_info, "http")
            let scheme = "http"
        else
            let scheme = "https"
        endif

        call setbufvar('$', "host", host)
        call setbufvar('$', "scheme", scheme)
        call setbufvar('$', "old_host", host)
        call setbufvar('$', "old_scheme", scheme)

        if is_h2
            let authority = ""
            let h2_scheme = ""
            if has_key(a:msg, "h2_info")
                let authority = get(a:msg.h2_info, "authority", "")
                let h2_scheme = get(a:msg.h2_info, "scheme", "")
            endif
            call setbufvar('$', "authority", authority)
            call setbufvar('$', "old_authority", authority)
            call setbufvar('$', "h2_scheme", h2_scheme)
            call setbufvar('$', "old_h2_scheme", h2_scheme)
        endif

        " Sni
        if has_key(a:msg.server_info, "sni")
            call setbufvar('$', "old_sni", a:msg.server_info.sni)
            call setbufvar('$', "sni", a:msg.server_info.sni)
        endif
    endif

    " 7. Set Ws Buffer variables
    if ft == "wreq" || ft == "wres"
        if has_key(a:msg.ws_info, "is_bin")
            call setbufvar('$', "is_bin", v:true)
        endif
    endif

    if !exists('was_added')
        call s:SetStatusLine()
    endif
endfunc

func! s:WsStatusLine()
    if exists('b:is_bin')
        setl statusline=%=
        setl statusline+=\>
        setl statusline+=\ b
    endif
endfunc

" check if sni has been modified.
function! s:IsSniModified()
    return b:scheme == "https"
          \ && exists('b:sni')
          \ && !empty(b:sni)
          \ && exists('b:old_sni')
          \ && !empty(b:old_sni)
          \ && b:sni != b:old_sni
endfunction

" Description:
"       send message to binary.
"
" Args:
"       need_response : bool
"
" Data:
"
"   Common:
"       { Resume: {
"           id: b:id,
"           modified: &modified, } }
"
"   Request:
"       {req: {
"           need_response: a:need_response,
"           update: b:update,
"           server_info:  {
"               host: b:host,
"               scheme: http,
"               sni: b:sni } } }
"
"       HTTP/2 requests omit server_info and send instead:
"           {req: {
"               h2_info: {
"                   authority: b:authority,
"                   scheme: b:h2_scheme } } }
"
"   Response:
"       {res: { update: bool }
"
"   Websocket Request:
"       info: {"id":1,"ft":{"wreq":{ "need_response: "bool" } } } }
"
"   Websocket Response:
"       info: {"id":1,"ft":{"wres":{} } } }
"
" Steps:
"       1. Build file info.
"       2. Check if file is modified.
"       3. For ft req and wreq, check if need_response.
"       4. For ft req and res, check if update.
"       5. For ft req, build server_info on host/scheme/sni change, or
"          h2_info for HTTP/2 buffers.
"       6. Build tosend and send to channel.
"       7. Write and delete the buffer.

func s:Send(need_response)
    try
        let info = {'id': b:id, 'ft': {}}
    catch
        call logger#Log("Error| " .. v:exception)
        return
    endtry

    " 2. Check if file or h2 pseudo-headers are modified
    let is_h2 = get(b:, 'is_h2', 0) == 1
    let is_pseudo_mod = is_h2
          \ && ((exists('b:authority') && exists('b:old_authority')
          \      && b:authority !=# b:old_authority)
          \     || (exists('b:h2_scheme') && exists('b:old_h2_scheme')
          \      && b:h2_scheme !=# b:old_h2_scheme))
    if &modified || exists('b:modified') || is_pseudo_mod
        let info['modified'] = v:true
    endif

    let finfo = {}

    " 3. For ft req and wreq, add if need_response
    if (&ft == "req" || &ft == "wreq") && a:need_response == v:true
        let finfo.need_response = v:true
    endif

    " 4. For ft req and res, add if update
    if (&ft == "req" || &ft == "res")
        call add_update#Add(finfo)
    endif

    " 5. For filetype request, build server_info or h2_info
    if &ft == "req"
        if is_h2
            " HTTP/2 streams resume in-place: pseudo-headers travel in
            " h2_info. Destination changes are not supported yet; the backend
            " ignores NewConnection for HTTP/2 and sends on the existing
            " upstream connection.
            let finfo["h2_info"] = {
                        \ "authority": get(b:, "authority", ""),
                        \ "scheme": get(b:, "h2_scheme", "")
                        \ }
        else
            let addinfo = {}
            if (b:scheme != b:old_scheme) || (b:host != b:old_host)
                let addinfo = ServerInfo()
            endif

            " Add sni
            if empty(addinfo) && s:IsSniModified()
                let addinfo = ServerInfo()
            endif

            if !empty(addinfo)
                let finfo["server_info"] = addinfo["server_info"]
            endif
        endif
    endif

    " 7. Build tosend and send to channel
    if &ft != "wres"
        let info['ft'][&ft] = finfo
    else
        let info['ft'] = "wres"
    endif
    let tosend = {"Resume": info}

    " 8. Write and Delete the Buffer
    silent execute 'w!'
    silent execute 'bd'
    call logger#Log("Sent| " .. json_encode(tosend))
    call ch_sendexpr(g:channel, tosend)
endfunc

" Description:
"       Toggle interceptor status.
"
" Steps:
"       1. Check if toggle is on/off and invert it.
"       2. If on, delete all buffers
"       3. Redraw status line
"       4. Send toggle. {"Action": "Toggle"} to commander.

func s:Toggle()
    if g:toggle == 0
        call logger#Log("Toggled| On")
        let g:toggle = 1
    elseif g:toggle == 1
        call logger#Log("Toggled| Off")
        let g:toggle = 0
        silent execute ':%bd!'
    endif
    call s:SetStatusLine()
    let tosend = "Toggle"
    call ch_sendexpr(g:channel, tosend)
endfunc

func s:SetStatusLine()
    if g:toggle == 0
        hi! def link StatusLine ZXCIStatusLineOff
    elseif g:toggle == 1
        hi! def link StatusLine ZXCIStatusLineOn
    endif
    if &ft == "req"
        call SetHostStatusLine()
    elseif &ft == "wreq" || &ft == "wres"
        call s:WsStatusLine()
    endif
    redrawstatus
endfunc

" If the user by mistake writes the file, set b:modified to 1 which can be used
" to set info['modified']
func s:SetModified()
    let b:modified = 1
endfunc

" Description:
"       Show all open buffers in format
"
"       bufname | scheme | host
"
"       req file only

func s:Showq()
    let names = []
    for buf in getbufinfo({'buflisted':1})
        if empty(buf.name)
            continue
        endif
        call bufload(buf.bufnr)
        let toadd = buf.bufnr .. " | " .. buf.name ->split(g:history_dir)[-1]
        if getbufvar(buf.bufnr, '&ft') == "req"
            let scheme = getbufvar(buf.bufnr, "scheme")
            let host = getbufvar(buf.bufnr, "host")
            let toadd .= " | " .. scheme .. " | " .. host
        endif
        call add(names, toadd)
    endfor
    echo join(names, "\n")
    call input("Press ENTER to continue...")
endfunc

" Data Sent:
"       { "Drop": [ b:id, &ft ] }

func s:DropMsg()
    if !exists('b:id')
        return
    endif
    let tosend = {}
    let tosend["Drop"] = [ b:id, &ft ]
    call logger#Log("Sent| " .. json_encode(tosend))
    call ch_sendexpr(g:channel, tosend)
    execute 'bd!'
endfunc

" --- Autocmd
autocmd BufWritePre * call s:SetModified()

" --- Commands
command InterToggle call s:Toggle()
command InterForward call s:Send(v:false)
command InterForwardAll bufdo! InterForward
command InterForwardWithRes call s:Send(v:true)
command Showq call s:Showq()
command DropMsg call s:DropMsg()

" Check if user has set hl
" else set Default Status Line colors
if !hlexists('ZXCIStatusLineOff')
    hi ZXCIStatusLineOff guibg=black ctermbg=black
endif

if !hlexists('ZXCIStatusLineOn')
    hi ZXCIStatusLineOn guibg=red guifg=black ctermbg=red ctermfg=black
endif

autocmd BufEnter,BufWinEnter,WinEnter * call s:SetStatusLine()

" --- Start
call s:SetStatusLine()
