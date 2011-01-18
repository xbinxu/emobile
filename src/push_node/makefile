include ../../makefile.inc


# The first target in any makefile is the default target.
# If you just type "make" then "make all" is assumed (because
# "all" is the first target in this makefile)
all: compile cfg

MODS = $(wildcard *.erl)
compile: ${MODS:%.erl=%.beam}

cfg:
	cp *.app $(ROOT_DIR)/ebin

clean:
	rm -rf *.beam erl_crash.dump