include ../../makefile.inc


# The first target in any makefile is the default target.
# If you just type "make" then "make all" is assumed (because
# "all" is the first target in this makefile)
all: compile cfg

MODS = $(wildcard *.erl)
APPS = $(wildcard *.app)
compile: ${MODS:%.erl=$(OUT_DIR)/%.beam}

cfg: ${APPS:%.app=$(OUT_DIR)/%.app}

$(OUT_DIR)/%.app:%.app
	cp $< $(ROOT_DIR)/ebin

clean:
	rm -rf *.beam erl_crash.dump