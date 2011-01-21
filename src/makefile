include ../makefile.inc


# The first target in any makefile is the default target.
# If you just type "make" then "make all" is assumed (because
# "all" is the first target in this makefile)
all: compile subdirs

MODS = $(wildcard *.erl)
compile: ${MODS:%.erl=$(OUT_DIR)/%.beam}

subdirs:
	cd common && make
	cd ctl_node && make
	cd push_node && make
	cd conn_node && make	

clean:
	rm -rf *.beam erl_crash.dump
	cd common && make clean
	cd ctl_node && make clean
	cd push_node && make clean
	cd conn_node && make clean