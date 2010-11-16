"=============================================================================
" File    : autoload/unite/source/outline.vim
" Author  : h1mesuke <himesuke@gmail.com>
" Updated : 2010-11-16
" Version : 0.0.9
" License : MIT license {{{
"
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following conditions:
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
"=============================================================================

function! unite#sources#outline#define()
  return s:source
endfunction

function! unite#sources#outline#alias(alias, src_filetype)
  let g:unite_source_outline_info[a:alias] = a:src_filetype
endfunction

function! unite#sources#outline#get_outline_info(filetype, ...)
  if a:0 && a:filetype == a:1
    throw "RuntimeError: unite-outline: " .
          \ "get_outline_info: infinite recursive call for '" . a:1 . "'"
  endif
  if has_key(g:unite_source_outline_info, a:filetype)
    if type(g:unite_source_outline_info[a:filetype]) == type("")
      " resolve the alias
      let src_filetype = g:unite_source_outline_info[a:filetype]
      return unite#sources#outline#get_outline_info(src_filetype, (a:0 ? a:1 : a:filetype))
    else
      return g:unite_source_outline_info[a:filetype]
    endif
  else
    let tries = [
          \ 'unite#sources#outline#',
          \ 'unite#sources#outline#defaults#',
          \ ]
    for path in tries
      let load_func = path . a:filetype . '#outline_info'
      try
        execute 'let outline_info = ' . load_func . '()'
        let g:unite_source_outline_info[a:filetype] = outline_info
        return outline_info
      catch /^Vim\%((\a\+)\)\=:E117:/
        " no file or undefined, go next
      endtry
    endfor
  endif
  return {}
endfunction

function! unite#sources#outline#adjust_scroll()
  let best = winheight(0) / 4
  execute 'normal! z.'
  while 1
    execute "normal! \<C-e>"
    if winline() < best
      break
    end
  endwhile
  execute "normal! \<C-y>"
endfunction

"---------------------------------------
" Utils

function! unite#sources#outline#indent(level)
  return printf('%*s', (a:level - 1) * g:unite_source_outline_indent_width, '')
endfunction

function! unite#sources#outline#capitalize(str, ...)
  let flag = (a:0 ? a:1 : '')
  return substitute(a:str, '\<\(\u\)\(\u\+\)\>', '\u\1\L\2', flag)
endfunction

function! unite#sources#outline#join_to(lines, idx, pattern, ...)
  let limit = (a:0 ? a:1 : 3)
  if limit < 0
    return s:join_to_backward(a:lines, a:idx, a:pattern, limit * -1)
  endif
  let idx = a:idx
  let lim_idx = min([a:idx + limit, len(a:lines) - 1])
  while idx <= lim_idx
    let line = a:lines[idx]
    if line =~ a:pattern
      break
    endif
    let idx += 1
  endwhile
  return join(a:lines[a:idx : idx], "\n")
endfunction

function! s:join_to_backward(lines, idx, pattern, ...)
  let limit = (a:0 ? a:1 : 3)
  let idx = a:idx
  let lim_idx = max(0, a:idx - limit])
  while idx > 0
    let line = a:lines[idx]
    if line =~ a:pattern
      break
    endif
    let idx -= 1
  endwhile
  return join(a:lines[idx : a:idx], "\n")
endfunction

function! unite#sources#outline#neighbor_match(lines, idx, pattern, ...)
  let nb = (a:0 ? a:1 : 1)
  if type(nb) == type([])
    let prev = nb[0]
    let next = nb[1]
  else
    let prev = nb
    let next = nb
  endif
  let nb_range = range(max([0, a:idx - prev]), min([a:idx + next, len(a:lines) - 1]))
  for idx in nb_range
    if a:lines[idx] =~ a:pattern
      return 1
    endif
  endfor
  return 0
endfunction

"-----------------------------------------------------------------------------
" Variables

if !exists('g:unite_source_outline_info')
  let g:unite_source_outline_info = {}
endif

if !exists('g:unite_source_outline_indent_width')
  let g:unite_source_outline_indent_width = 2
endif

if !exists('g:unite_source_outline_cache_buffers')
  let g:unite_source_outline_cache_buffers = 10
endif

if !exists('g:unite_source_outline_cache_limit')
  let g:unite_source_outline_cache_limit = 100
endif

if !exists('g:unite_source_outline_after_jump_command')
  let g:unite_source_outline_after_jump_command = 'call unite#sources#outline#adjust_scroll()'
endif

"-----------------------------------------------------------------------------
" Aliases

call unite#sources#outline#alias('cfg',      'dosini')
call unite#sources#outline#alias('plaintex', 'tex')
call unite#sources#outline#alias('xhtml',    'html')
call unite#sources#outline#alias('zsh',      'sh')

"-----------------------------------------------------------------------------
" Source

let s:source = {
      \ 'name': 'outline',
      \ 'action_table': {},
      \ 'default_action': {},
      \ 'is_volatile': 1,
      \ }

function! s:source.on_init(args, context)
  let s:buffer = {
        \ 'path'    : expand('%:p'),
        \ 'filetype': getbufvar('%', '&filetype'),
        \ 'tabstop' : getbufvar('%', '&tabstop'),
        \ 'lines'   : getbufline('%', 1, '$'),
        \ }
endfunction

function! s:source.gather_candidates(args, context)
  try
    if exists('g:unite_source_outline_profile') && g:unite_source_outline_profile && has("reltime")
      let start_time = reltime()
    endif

    let is_force = ((len(a:args) > 0 && a:args[0] == '!') || a:context.is_redraw)
    let path = s:buffer.path
    if s:cache.has(path) && !is_force
      return s:cache.read(path)
    endif

    let filetype = s:buffer.filetype
    let outline_info = unite#sources#outline#get_outline_info(filetype)
    if len(outline_info) == 0
      call unite#print_error("unite-outline: not supported filetype: " . filetype)
      return []
    endif

    let lines = s:buffer.lines
    let idx = 0 | let n_lines = len(lines)

    " skip the header of the file
    if has_key(outline_info, 'skip_header')
      let idx = outline_info.skip_header(lines, { 'outline_info': outline_info })

    elseif has_key(outline_info, 'skip') && has_key(outline_info.skip, 'header')
      " eval once
      let val_type = type(outline_info.skip.header)
      if val_type == type("")
        let skip_header_lead = 1 | let skip_header_block = 0
        let header_lead = outline_info.skip.header
      elseif val_type == type([])
        let skip_header_lead = 0 | let skip_header_block = 1
        let header_begin = outline_info.skip.header[0]
        let header_end   = outline_info.skip.header[1]
      elseif val_type == type({})
        let skip_header_lead = has_key(outline_info.skip.header, 'leading')
        if skip_header_lead
          let header_lead = outline_info.skip.header.leading
        endif
        let skip_header_block = has_key(outline_info.skip.header, 'block')
        if skip_header_block
          let header_begin = outline_info.skip.header.block[0]
          let header_end   = outline_info.skip.header.block[1]
        endif
      endif

      while idx < n_lines
        let line = lines[idx]
        if skip_header_lead && line =~# header_lead
          let idx += 1
          while idx < n_lines
            let line = lines[idx]
            if line !~# header_lead
              break
            endif
            let idx += 1
          endwhile
        elseif skip_header_block && line =~# header_begin
          let idx += 1
          while idx < n_lines
            let line = lines[idx]
            if line =~# header_end
              break
            endif
            let idx += 1
          endwhile
          let idx += 1
        else
          break
        endif
      endwhile
    endif

    " eval once
    let skip_block = has_key(outline_info, 'skip') && has_key(outline_info.skip, 'block')
    if skip_block
      let skip_block_begin = outline_info.skip.block[0]
      let skip_block_end   = outline_info.skip.block[1]
    endif
    let match_head_prev = has_key(outline_info, 'heading-1')
    if match_head_prev
      let head_prev = outline_info['heading-1']
    endif
    let match_head_line = has_key(outline_info, 'heading')
    if match_head_line
      let head_line = outline_info.heading
    endif
    let match_head_next = has_key(outline_info, 'heading+1')
    if match_head_next
      let head_next = outline_info['heading+1']
    endif

    " collect headings
    let headings = []
    let heading_id = 1
    while idx < n_lines
      let line = lines[idx]
      if skip_block && line =~# skip_block_begin
        " skip a documentation block
        let idx += 1
        while idx < n_lines
          let line = lines[idx]
          if line =~# skip_block_end
            break
          endif
          let idx += 1
        endwhile

      elseif match_head_prev && line =~# head_prev && idx < n_lines - 3
        " matched: heading-1
        let next_line = lines[idx + 1]
        if next_line =~ '[[:punct:]]\@!\S'
          if has_key(outline_info, 'create_heading')
            let heading = outline_info.create_heading('heading-1', next_line, line, {
                  \ 'heading_index': idx + 1, 'matched_index': idx, 'lines': lines,
                  \ 'heading_id': heading_id, 'outline_info': outline_info })
            if heading != ""
              call add(headings, [heading, next_line, idx + 1])
              let heading_id += 1
            endif
          else
            call add(headings, [next_line, next_line, idx + 1])
          endif
        elseif next_line =~ '\S' && idx < n_lines - 4
          " see one more next
          let next_line = lines[idx + 2]
          if next_line =~ '[[:punct:]]\@!\S'
            if has_key(outline_info, 'create_heading')
              let heading = outline_info.create_heading('heading-1', next_line, line, {
                    \ 'heading_index': idx + 2, 'matched_index': idx, 'lines': lines,
                    \ 'heading_id': heading_id, 'outline_info': outline_info })
              if heading != ""
                call add(headings, [heading, next_line, idx + 2])
                let heading_id += 1
              endif
            else
              call add(headings, [next_line, next_line, idx + 2])
            endif
          endif
          let idx += 1
        endif
        let idx += 1

      elseif match_head_line && line =~# head_line
        " matched: heading
        if has_key(outline_info, 'create_heading')
          let heading = outline_info.create_heading('heading', line, line, {
                \ 'heading_index': idx, 'matched_index': idx, 'lines': lines,
                \ 'heading_id': heading_id, 'outline_info': outline_info })
          if heading != ""
            call add(headings, [heading, line, idx])
            let heading_id += 1
          endif
        else
          call add(headings, [line, line, idx])
        endif

      elseif match_head_next && line =~# head_next && idx > 0
        " matched: heading+1
        let prev_line = lines[idx - 1]
        if prev_line =~ '[[:punct:]]\@!\S'
          if has_key(outline_info, 'create_heading')
            let heading = outline_info.create_heading('heading+1', prev_line, line, {
                  \ 'heading_index': idx - 1, 'matched_index': idx, 'lines': lines,
                  \ 'heading_id': heading_id, 'outline_info': outline_info })
            if heading != ""
              call add(headings, [heading, prev_line, idx - 1])
              let heading_id += 1
            endif
          else
            call add(headings, [prev_line, prev_line, idx - 1])
          endif
        endif
      endif
      let idx += 1
    endwhile

    let ts = s:buffer.tabstop
    let cands = map(headings, '{
          \ "word": s:expand_leading_tabs(v:val[0], ts),
          \ "source": "outline",
          \ "kind": "jump_list",
          \ "action__path": path,
          \ "action__pattern": "^" . s:escape_regex(v:val[1]) . "$",
          \ "action__signature": s:signature2(lines, v:val[2]),
          \ }')

    if n_lines > g:unite_source_outline_cache_limit
      call s:cache.write(path, cands)
    endif

    if exists('g:unite_source_outline_profile') && g:unite_source_outline_profile && has("reltime")
      let used_time = split(reltimestr(reltime(start_time)))[0]
      let phl = str2float(used_time) * (100.0 / n_lines)
      echomsg "unite-outline: used=" . used_time . "s, 100l=". string(phl) . "s"
    endif

    return cands
  catch
    call unite#print_error(v:throwpoint)
    call unite#print_error(v:exception)
    return []
  endtry
endfunction

function! s:expand_leading_tabs(str, ts)
  let lead_tabs = matchstr(a:str, '^\t\+')
  let ntab = strlen(lead_tabs)
  if ntab > 0
    return substitute(a:str, '^\t\+', printf('%*s', ntab * a:ts, ""), '')
  else
    return a:str
  endif
endfunction

function! s:escape_regex(str)
  return escape(a:str, '^$[].*\~')
endfunction

function! s:signature(lnum)
  let r = 2
  let from = max([1, a:lnum - r])
  let to   = min([a:lnum + r, line('$')])
  return join(getline(from, to))
endfunction

function! s:signature2(lines, idx)
  let r = 2
  let from = max([0, a:idx - r])
  let to   = min([a:idx + r, len(a:lines) - 1])
  return join(a:lines[from : to])
endfunction

"---------------------------------------
" Action

let s:action_table = {}
let s:action_table.jump = {
      \ 'description': 'jump to this heading',
      \ 'is_selectable': 0,
      \ }

function! s:action_table.jump.func(candidate)
  let cand = a:candidate
  edit `=cand.action__path`
  call search(cand.action__pattern, 'w')
  let lnum0 = line('.')
  call search(cand.action__pattern, 'w')
  let lnum = line('.')
  if lnum != lnum0
    " same heading lines detected!!
    let start_lnum = lnum
    while 1
      if s:signature(lnum) ==# cand.action__signature
        " found
        break
      endif
      call search(cand.action__pattern, 'w')
      let lnum = line('.')
      if lnum == start_lnum
        " not found
        call unite#print_error("unite-outline: target heading not found, please update the cache")
        return
      endif
    endwhile
  endif
  normal! zv
  if g:unite_source_outline_after_jump_command != ''
    execute g:unite_source_outline_after_jump_command
  endif
endfunction

let s:source.action_table.jump_list = s:action_table
let s:source.default_action.jump_list = 'jump'

unlet s:action_table

"-----------------------------------------------------------------------------
" Cache

let s:cache = { 'data': {} }

function! s:cache.has(path)
  return has_key(self.data, a:path)
endfunction

function! s:cache.read(path)
  let item = self.data[a:path]
  let item.touched = localtime()
  return item.candidates
endfunction

function! s:cache.write(path, cands)
  let self.data[a:path] = {
        \ 'candidates': a:cands,
        \ 'touched': localtime(), 
        \ }
  if len(self.data) > g:unite_source_outline_cache_buffers
    let oldest = sort(items(self.data), 's:compare_timestamp')[0]
    unlet self.data[oldest[0]]
  endif
endfunction

function! s:compare_timestamp(item1, item2)
  let t1 = a:item1[1].touched
  let t2 = a:item2[1].touched
  return t1 == t2 ? 0 : t1 > t2 ? 1 : -1
endfunction

" vim: filetype=vim
