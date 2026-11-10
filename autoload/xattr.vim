" Description:
"       Read user extended attributes from a file.
"
" Arg:
"       path : file path
"
" Returns:
"       Dictionary of user attribute names to values, with the "user."
"       prefix removed. Returns an empty dictionary when no reader is
"       available.
"
" Steps:
"       1. Use getfattr when installed (Linux).
"       2. Fall back to xattr on macOS.
"       3. Ignore non-user attributes.

func xattr#Read(path)
    if !filereadable(a:path)
        return {}
    endif
    if get(g:, 'has_getfattr', 0)
        return s:ReadGetfattr(a:path)
    elseif has('macunix')
        return s:ReadMacXattr(a:path)
    endif
    return {}
endfunc

" getfattr output:
"       # file: path
"       user.host="example.com:443"
"       user.is_h2="1"

func s:ReadGetfattr(path)
    let attrs = {}
    let lines = systemlist("getfattr -dm user " .. shellescape(a:path))
    for line in lines
        if empty(line) || line[0] ==# '#'
            continue
        endif
        let eq_idx = stridx(line, '=')
        if eq_idx < 1
            continue
        endif
        let key = line[: eq_idx - 1]
        if stridx(key, 'user.') != 0
            continue
        endif
        let attrs[key[5:]] = line[eq_idx + 1 :] ->trim('"')
    endfor
    return attrs
endfunc

" macOS xattr output:
"       user.host: example.com:443
"       user.is_h2: 1

func s:ReadMacXattr(path)
    let attrs = {}
    let lines = systemlist("xattr -l " .. shellescape(a:path))
    for line in lines
        let sep_idx = stridx(line, ': ')
        if sep_idx < 1
            continue
        endif
        let key = line[: sep_idx - 1]
        if stridx(key, 'user.') != 0
            continue
        endif
        let attrs[key[5:]] = line[sep_idx + 2 :]
    endfor
    return attrs
endfunc
