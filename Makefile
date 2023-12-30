HOOGLE_PROJECT_PORT := 8080
HOOGLE_DEPS_PORT := 8081

usage:
	@echo "usage: make <command>"
	@echo
	@echo "Available commands:"
	@echo ""
	# Code
	@echo "    format                 -- Formats .hs, .cabal, .nix files"
	@echo "    format_check           -- Check formatting of .hs, .cabal, .nix files"
	@echo "    format_haskell         -- Formats .hs files"
	@echo "    format_check_haskell   -- Check formatting of .hs files"
	@echo "    format_nix             -- Formats .nix files"
	@echo "    format_check_nix       -- Check formatting of .nix files"
	@echo "    format_cabal           -- Formats .cabal files"
	@echo "    format_check_cabal     -- Check formatting of .cabal files"
	@echo "    lint                   -- Auto-refactors code"
	@echo "    lint_check             -- Run code linting"
	@echo ""
	# Documentation (haskell)
	@echo "    haddock                -- Generates haddock documentation, does not check if documentation was already updated and tries again"
	@echo "    hoogle_start           -- Kills hoogle servers, generates haddock documentation, generates hoogle databases, run two hoogle servers (project and dependencies)"
	@echo "    hoogle_server_projects  -- Generates hoogle database for project files, starts a hoogle server with the generated database on port: $(HOOGLE_PROJECT_PORT)"
	@echo "    hoogle_server_deps     -- Generates hoogle database for the project dependencies, starts a hoogle server with the generated database on port: $(HOOGLE_DEPS_PORT)"
	@echo "    hoogle_stop            -- Kills hoogle servers"
	@echo ""
    # CI
	@echo "    ci                     -- Runs a set of checks similar to the CI suite"

################################################################################
# Code
FIND_EXCLUDE_PATH := -not -path './dist-*/*'

FIND_HASKELL_SOURCES := find -name '*.hs' $(FIND_EXCLUDE_PATH)
FIND_NIX_SOURCES := find -name '*.nix' $(FIND_EXCLUDE_PATH)
FIND_CABAL_SOURCES := find -name '*.cabal' $(FIND_EXCLUDE_PATH)

# Runs as command on all results of the `find` call at one.
# e.g.
#   foo found_file_1 found_file_2
find_exec_all_fn = $(1) -exec $(2) {} +

# Runs a command on all results of the `find` call one-by-one
# e.g.
#   foo found_file_1
#   foo found_file_2
find_exec_one_by_one_fn = $(1) | xargs -i $(2) {}

.PHONY: format
format: format_haskell format_nix format_cabal
format_check : format_check_haskell format_check_nix format_check_cabal

# Run stylish-haskell of .hs files
.PHONY: format_haskell
format_haskell: requires_nix_shell
	$(call find_exec_all_fn, $(FIND_HASKELL_SOURCES), fourmolu -c -m inplace)

.PHONY: format_check_haskell
format_check_haskell: requires_nix_shell
	$(call find_exec_one_by_one_fn, $(FIND_HASKELL_SOURCES), bash -c 'diff -u <(cat $$0) <(stylish-haskell $$0)')

# Run nixpkgs-fmt of .nix files
.PHONY: format_nix
format_nix: requires_nix_shell
	$(call find_exec_all_fn, $(FIND_NIX_SOURCES), nixpkgs-fmt)

.PHONY: format_check_nix
format_check_nix: requires_nix_shell
	$(call find_exec_all_fn, $(FIND_NIX_SOURCES), nixpkgs-fmt --check)

# Run cabal-fmt of .cabal files
.PHONY: format_cabal
format_cabal: requires_nix_shell
	$(call find_exec_all_fn, $(FIND_CABAL_SOURCES), cabal-fmt -i)

.PHONY: format_check_cabal
format_check_cabal: requires_nix_shell
	$(call find_exec_all_fn, $(FIND_CABAL_SOURCES), cabal-fmt --check)


# Apply hlint suggestions
.PHONY: lint
lint: requires_nix_shell
	$(call find_exec_one_by_one_fn, $(FIND_HASKELL_SOURCES), hlint -j --refactor --refactor-options="-i")

# Check hlint suggestions
.PHONY: lint_check
lint_check: requires_nix_shell
	$(call find_exec_all_fn, $(FIND_HASKELL_SOURCES), hlint -j)

################################################################################
# Docs
# Limitations: two different hoogle database are generated:
# 1) one for the code defined in the project
# 2) one for the dependencies
# This forces us to expose two different hoogle servers, this problem has its root in the way cabal haddock
# treat dependencies and in particular - at the time of writing - is it not building documentation for dependencies.
# We can still create a database as we do in the `hoogle_start_deps` rule: we are basically using ghc-pkg
# but the presence of the documentation depends on individual dependencies.

# Here are possible solution to investigate:
# - cabal-install package: currently broken on nixpkgs (may not be compatible with GHC8.10.7)
# - cabal haddock-projeck: supported in cabal but requires an higher version of haddock (which may not be compatible with GHC8.10.7)
.PHONY: haddock
haddock:
	cabal haddock --haddock-html --haddock-hoogle all

.PHONY: hoogle_server_project
hoogle_start_project: requires_nix_shell
	hoogle generate --local=dist-newstyle/build --database project.hoo
	hoogle server --local=true --database=project.hoo -p $(HOOGLE_PROJECT_PORT) >> /dev/null &
	@ echo "hoogle server for project starts on http://127.0.0.1:$(HOOGLE_PROJECT_PORT)"

.PHONY: hoogle_server_deps
hoogle_start_deps: requires_nix_shell
	hoogle generate --local --database deps.hoo
	hoogle server --local=true --database=deps.hoo -p $(HOOGLE_DEPS_PORT) >> /dev/null &
	@ echo "hoogle server for project dependencies starts on http://127.0.0.1:$(HOOGLE_DEPS_PORT)"

.PHONY: hoogle_start
hoogle_start: requires_nix_shell hoogle_stop haddock hoogle_start_deps hoogle_start_project

.PHONY: hoogle_stop
hoogle_stop:
	-pkill hoogle


################################################################################
# Build
.PHONY: build_all
build_all:
	cabal build -j all

################################################################################
# ci

# runs a set of command similar to the CI suite
ci: format_check test_djed_rate test_offchain_v2_emulator integration_test_djed_offchain_v2

################################################################################
# Utils

.PHONY: requires_nix_shell
requires_nix_shell:
	@ [ "$(IN_NIX_SHELL)" ] || echo "The $(MAKECMDGOALS) target must be run from inside a nix shell"
	@ [ "$(IN_NIX_SHELL)" ] || (echo "    run 'nix develop' first" && false)

.PHONY: clean
clean:
	cabal clean
