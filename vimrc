''
call plug#begin('~/.vim/plugged')

" one-half-dark theme - 테마
Plug 'sonph/onehalf', { 'rtp': 'vim' }

" airline - 하단 상태바
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

" File Browser
Plug 'ctrlpim/ctrlp.vim'

call plug#end()

" 설치된 플러그인 적용하기
colorscheme onehalfdark
let g:airline_theme='onehalfdark'
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#left_sep = ' '
let g:airline#extensions#tabline#left_alt_sep = '|'
let g:airline#extensions#tabline#formatter = 'default'


" vim 설정
" 문법 설정
if has("syntax")
    syntax on
endif

" 인코딩 설정
set encoding=utf-8

" GUI-Color를 사용 가능하도록 설정
set termguicolors

" 탭 정지
set tabstop=4

" shift 이동거리
set shiftwidth=4

" 줄번호 표시
set number

" 괄호 짜 강조
set showmatch

" 항상 상단에 탭 라인을 출력
set showtabline=2

" 행 표시선 출력
set colorcolumn=100

" nvim 사용일 경우 실시간 강조 활성화
if has('nvi')
    set inccommand=nosplit
endif

" 하이라이트 설정
" 버퍼(창)과 버퍼의 끝(창의 끝)을 투명하게
highlight Normal guibg=NONE
highlight EndOfBuffer guibg=NONE

" 줄번호 배경색은 투명(NULL)하게,
" 글자는 굵게(bold), 글자색은 하얗게(White)
highlight LineNr guibg=NONE gui=bold guifg=white

" 행 표시선 색상
highlight ColorColumn guibg=White
