include ../../makefile.inc


# The first target in any makefile is the default target.
# If you just type "make" then "make all" is assumed (because
# "all" is the first target in this makefile)
all: compile

MODS = $(wildcard *.erl)
compile: ${MODS:%.erl=$(OUT_DIR)/%.beam}

clean:
	rm -rf *.beam erl_crash.dump