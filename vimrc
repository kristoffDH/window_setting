''
call plug#begin('~/.vim/plugged')

" one-half-dark theme - �׸�
Plug 'sonph/onehalf', { 'rtp': 'vim' }

" airline - �ϴ� ���¹�
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

" File Browser
Plug 'ctrlpim/ctrlp.vim'

call plug#end()

" ��ġ�� �÷����� �����ϱ�
colorscheme onehalfdark
let g:airline_theme='onehalfdark'
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#left_sep = ' '
let g:airline#extensions#tabline#left_alt_sep = '|'
let g:airline#extensions#tabline#formatter = 'default'


" vim ����
" ���� ����
if has("syntax")
    syntax on
endif

" ���ڵ� ����
set encoding=utf-8

" GUI-Color�� ��� �����ϵ��� ����
set termguicolors

" �� ����
set tabstop=4

" shift �̵��Ÿ�
set shiftwidth=4

" �ٹ�ȣ ǥ��
set number

" ��ȣ ¥ ����
set showmatch

" �׻� ��ܿ� �� ������ ���
set showtabline=2

" �� ǥ�ü� ���
set colorcolumn=100

" nvim ����� ��� �ǽð� ���� Ȱ��ȭ
if has('nvi')
    set inccommand=nosplit
endif

" ���̶���Ʈ ����
" ����(â)�� ������ ��(â�� ��)�� �����ϰ�
highlight Normal guibg=NONE
highlight EndOfBuffer guibg=NONE

" �ٹ�ȣ ������ ����(NULL)�ϰ�,
" ���ڴ� ����(bold), ���ڻ��� �Ͼ��(White)
highlight LineNr guibg=NONE gui=bold guifg=white

" �� ǥ�ü� ����
highlight ColorColumn guibg=White
