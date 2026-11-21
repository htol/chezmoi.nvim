NVIM ?= nvim
STYLUA ?= stylua
LUALS ?= lua-language-server
MINI_URL ?= https://github.com/echasnovski/mini.nvim

LUA_DIRS := lua plugin tests

.PHONY: deps test lint

deps: deps/mini.nvim

deps/mini.nvim:
	git clone --filter=blob:none --depth 1 $(MINI_URL) $@

test: deps
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run()"

lint:
	$(STYLUA) --check $(LUA_DIRS)
	VIMRUNTIME="$$($(NVIM) --clean --headless --cmd 'lua io.write(vim.env.VIMRUNTIME)' --cmd q)" \
		$(LUALS) --check=. --checklevel=Warning --configpath=$(CURDIR)/.luarc.json
